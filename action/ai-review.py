#!/usr/bin/env python3
"""AI review of the plugin code changed by a commit or pull request, or of the whole plugin.

Sends the diff (plus the full changed files, readme.txt and the main plugin file for context),
the WPPOOL review rules and the reviewer skill's knowledge files to Claude (if
ANTHROPIC_API_KEY is set) or Gemini (if GEMINI_API_KEY is set) and writes:

  ai-findings.json   structured findings
  ai-report.md       Markdown report (run summary + PR comment)
  $GITHUB_OUTPUT     ai_status, ai_blockers, ai_warnings, ai_provider

An API failure is reported as ai_status=error and never fails the job by itself, so a
provider outage cannot block merges. Real findings are judged by the Compliance Gate.

AUDIT_MODE=full reviews every shipped code file instead of the change, in batches.
"""

import fnmatch
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

PLUGIN_DIR = os.environ.get('PLUGIN_DIR', '.') or '.'
RULES_FILE = os.environ.get('RULES_FILE', 'ai-review-rules.md')
EVENT = os.environ.get('EVENT_NAME', '')
BEFORE = os.environ.get('BEFORE_SHA', '')
HEAD = os.environ.get('HEAD_SHA', '') or 'HEAD'
BASE_REF = os.environ.get('BASE_REF', '')
REF_NAME = os.environ.get('REF_NAME', '')
DEFAULT_BRANCH = os.environ.get('DEFAULT_BRANCH', '')
TEXT_DOMAIN = os.environ.get('TEXT_DOMAIN', '')
GEMINI_KEY = os.environ.get('GEMINI_API_KEY', '')
ANTHROPIC_KEY = os.environ.get('ANTHROPIC_API_KEY', '')
GEMINI_MODEL = os.environ.get('GEMINI_MODEL', '') or 'gemini-flash-lite-latest'
CLAUDE_MODEL = os.environ.get('CLAUDE_MODEL', '') or 'claude-opus-5-5'
FULL_AUDIT = os.environ.get('AUDIT_MODE', '').lower() == 'full'

# Reference material from the wppool-plugin-reviewer skill, appended to the rules.
KNOWLEDGE_FILES = (
    'closure-case-studies.md',
    'compliant-trialware-pattern.md',
    'official-guidelines-and-pcp.md',
    'grep-patterns.md',
)

CODE_EXTENSIONS = ('.php', '.js', '.jsx', '.ts', '.tsx', '.mjs', '.vue')
ALWAYS_SKIP = ('vendor/', 'node_modules/', '.git/', '.github/', 'build/', 'dist/')
MAX_FILE_CHARS = 60000
MAX_TOTAL_CHARS = 350000
MAX_CONTEXT_CHARS = 40000
BATCH_PAUSE_SECONDS = 45  # Keeps full audits under the Gemini free-tier tokens-per-minute limit.

FINDINGS_SCHEMA = {
    'type': 'object',
    'properties': {
        'summary': {'type': 'string'},
        'findings': {
            'type': 'array',
            'items': {
                'type': 'object',
                'properties': {
                    'severity': {'type': 'string', 'enum': ['BLOCKER', 'WARNING']},
                    'category': {'type': 'string'},
                    'file': {'type': 'string'},
                    'line': {'type': 'integer'},
                    'message': {'type': 'string'},
                    'fix': {'type': 'string'},
                },
                'required': ['severity', 'category', 'file', 'line', 'message', 'fix'],
                'additionalProperties': False,
            },
        },
    },
    'required': ['summary', 'findings'],
    'additionalProperties': False,
}


def git(*args):
    return subprocess.run(['git', *args], capture_output=True, text=True, errors='replace').stdout


def git_ok(*args):
    return subprocess.run(['git', *args], capture_output=True, text=True).returncode == 0


def set_output(**values):
    path = os.environ.get('GITHUB_OUTPUT')
    if not path:
        return
    with open(path, 'a', encoding='utf-8') as fh:
        for key, value in values.items():
            fh.write(f'{key}={value}\n')


def distignore_patterns():
    path = os.path.join(PLUGIN_DIR, '.distignore')
    if not os.path.isfile(path):
        return []
    patterns = []
    for raw in open(path, encoding='utf-8', errors='replace'):
        line = raw.strip()
        if line and not line.startswith('#'):
            patterns.append(line)
    return patterns


def is_reviewable(rel, patterns):
    if not (rel.endswith(CODE_EXTENSIONS) or os.path.basename(rel) == 'readme.txt'):
        return False
    if rel.endswith(('.min.js', '.min.css', '.asset.php', '.l10n.php')):
        return False
    if any(('/' + rel).find('/' + skip) != -1 for skip in ALWAYS_SKIP):
        return False
    for pattern in patterns:
        glob = pattern.strip('/').replace('**', '*')
        anchored = pattern.startswith('/')
        candidates = [rel] if anchored else [rel] + ['/'.join(rel.split('/')[i:]) for i in range(1, rel.count('/') + 1)]
        for cand in candidates:
            if fnmatch.fnmatch(cand, glob) or fnmatch.fnmatch(cand, glob + '/*'):
                return False
    return True


def diff_range():
    """Return (base, head, description) for the change to review."""
    zero = '0' * 40
    if EVENT == 'pull_request' and BASE_REF:
        git('fetch', '--no-tags', '--depth=200', 'origin', BASE_REF)
        base = git('merge-base', f'origin/{BASE_REF}', HEAD).strip()
        if base:
            return base, HEAD, f'pull request against {BASE_REF}'
    if EVENT == 'push' and DEFAULT_BRANCH and REF_NAME and REF_NAME != DEFAULT_BRANCH:
        # Feature branch: review everything the branch changes, like a pull request would.
        git('fetch', '--no-tags', '--depth=200', 'origin', DEFAULT_BRANCH)
        base = git('merge-base', f'origin/{DEFAULT_BRANCH}', HEAD).strip()
        if base:
            return base, HEAD, f'branch {REF_NAME} compared to {DEFAULT_BRANCH}'
    if EVENT == 'push' and BEFORE and BEFORE != zero and git_ok('cat-file', '-e', f'{BEFORE}^{{commit}}'):
        return BEFORE, HEAD, 'commits in this push'
    if git_ok('rev-parse', '--verify', f'{HEAD}~1'):
        return f'{HEAD}~1', HEAD, 'latest commit'
    return None, HEAD, 'first commit'


def collect_changes():
    base, head, label = diff_range()
    patterns = distignore_patterns()
    prefix = os.path.normpath(PLUGIN_DIR).replace('\\', '/')
    prefix = '' if prefix in ('.', '') else prefix.rstrip('/') + '/'

    if base:
        names = git('diff', '--name-only', '--diff-filter=AMR', base, head).splitlines()
    else:
        names = git('ls-tree', '-r', '--name-only', head).splitlines()

    files = []
    for name in names:
        if prefix and not name.startswith(prefix):
            continue
        rel = name[len(prefix):]
        if is_reviewable(rel, patterns) and os.path.isfile(name):
            files.append(name)

    parts, total, truncated = [], 0, []
    for name in files:
        diff = git('diff', '--unified=8', base, head, '--', name) if base else ''
        numbered = numbered_lines(name)
        if len(numbered) > MAX_FILE_CHARS:
            numbered = numbered[:MAX_FILE_CHARS] + '\n... (file truncated for length)'
        block = f'### FILE: {name}\n\n#### Diff\n```diff\n{diff or "(new file / no diff available)"}\n```\n\n#### Full file (new version, with line numbers)\n```\n{numbered}\n```\n'
        if total + len(block) > MAX_TOTAL_CHARS:
            truncated.append(name)
            continue
        parts.append(block)
        total += len(block)
    return files, parts, truncated, label


def plugin_prefix():
    prefix = os.path.normpath(PLUGIN_DIR).replace('\\', '/')
    return '' if prefix in ('.', '') else prefix.rstrip('/') + '/'


def numbered_lines(name):
    try:
        content = open(name, encoding='utf-8', errors='replace').read()
    except OSError:
        content = ''
    return '\n'.join(f'{i + 1:5d}| {line}' for i, line in enumerate(content.splitlines()))


def main_plugin_file():
    prefix = plugin_prefix()
    root = prefix or '.'
    for entry in sorted(os.listdir(root)):
        path = os.path.join(root, entry)
        if entry.endswith('.php') and os.path.isfile(path):
            with open(path, encoding='utf-8', errors='replace') as fh:
                if 'Plugin Name:' in fh.read(8192):
                    return prefix + entry
    return ''


def context_blocks(skip):
    """readme.txt and the main plugin file, so the AI can check documentation and headers."""
    blocks = []
    for name in (plugin_prefix() + 'readme.txt', main_plugin_file()):
        if not name or name in skip or not os.path.isfile(name):
            continue
        numbered = numbered_lines(name)
        if len(numbered) > MAX_CONTEXT_CHARS:
            numbered = numbered[:MAX_CONTEXT_CHARS] + '\n... (truncated)'
        blocks.append(f'### CONTEXT FILE (unchanged, for reference): {name}\n```\n{numbered}\n```\n')
    return blocks


def collect_audit():
    """Every shipped code file, split into batches that fit one request."""
    patterns = distignore_patterns()
    prefix = plugin_prefix()
    files = []
    for name in git('ls-files').splitlines():
        if prefix and not name.startswith(prefix):
            continue
        rel = name[len(prefix):]
        if is_reviewable(rel, patterns) and os.path.isfile(name):
            files.append(name)

    batches, current, size = [], [], 0
    for name in files:
        chunks, chunk, chunk_size = [], [], 0
        for line in numbered_lines(name).split('\n'):
            if chunk and chunk_size + len(line) > MAX_FILE_CHARS:
                chunks.append('\n'.join(chunk))
                chunk, chunk_size = [], 0
            chunk.append(line)
            chunk_size += len(line) + 1
        chunks.append('\n'.join(chunk))
        for i, text in enumerate(chunks):
            part = f' (part {i + 1} of {len(chunks)})' if len(chunks) > 1 else ''
            block = f'### FILE: {name}{part}\n```\n{text}\n```\n'
            if current and size + len(block) > MAX_TOTAL_CHARS:
                batches.append(current)
                current, size = [], 0
            current.append(block)
            size += len(block)
    if current:
        batches.append(current)
    return files, batches


def build_prompt(parts, truncated, label, context=(), batch=''):
    if FULL_AUDIT:
        lines = [
            f'FULL PLUGIN AUDIT{batch}: there is no diff. Review ALL the code shown below as if it were about to',
            'be submitted to WordPress.org; the "review only the changed code" rule does not apply.',
        ]
    else:
        lines = [f'Review the following WordPress plugin changes ({label}).']
    lines += [
        f'Plugin text domain / slug: {TEXT_DOMAIN or "(not provided)"}.',
        'Return JSON matching this shape: {"summary": string, "findings": [{"severity": "BLOCKER"|"WARNING", '
        '"category": string, "file": string, "line": integer, "message": string, "fix": string}]}.',
        'Use the exact file paths shown after "FILE:" and the line numbers shown in the listing.',
        'CONTEXT FILEs are reference only (for example: is an external service documented in readme.txt?). '
        'Report a missing readme disclosure at the code line that contacts the service.',
    ]
    if not FULL_AUDIT:
        lines.append('Report only real problems in the changed code.')
    lines.append('')
    if truncated:
        lines.append('These changed files were too large to include and were not reviewed: ' + ', '.join(truncated))
        lines.append('')
    return '\n'.join(lines) + '\n'.join(list(context) + list(parts))


def load_rules():
    rules = open(RULES_FILE, encoding='utf-8').read()
    here = os.path.dirname(os.path.abspath(__file__))
    folders = [os.environ.get('KNOWLEDGE_DIR', ''), os.path.dirname(os.path.abspath(RULES_FILE)),
               os.path.join(here, '..', 'knowledge')]
    extra = []
    for name in KNOWLEDGE_FILES:
        for folder in folders:
            path = os.path.join(folder, name) if folder else ''
            if path and os.path.isfile(path):
                extra.append(f'\n\n---\n\n# Reference: {name}\n\n' + open(path, encoding='utf-8').read())
                break
    if extra:
        rules += ('\n\n## 6. Reference knowledge from the WPPOOL reviewer skill\n\n'
                  'The documents below are the detailed sources behind the rules above: real closure emails, '
                  'the compliant free/pro pattern, the official guidelines and Plugin Check rules. Use them to '
                  'judge borderline cases; the rules above still decide what is a BLOCKER.' + ''.join(extra))
    return rules


def http_json(url, payload, headers, timeout=300):
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json', **headers})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode('utf-8'))


def pick_gemini_model(lite=False):
    """Newest available Flash model (or Flash-Lite) for when the configured one is missing or out of quota."""
    req = urllib.request.Request('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200',
                                 headers={'x-goog-api-key': GEMINI_KEY})
    with urllib.request.urlopen(req, timeout=60) as resp:
        models = json.loads(resp.read().decode('utf-8')).get('models', [])
    usable = [m['name'].split('/', 1)[-1] for m in models
              if 'generateContent' in m.get('supportedGenerationMethods', [])
              and 'flash' in m['name'] and (('lite' in m['name']) == lite)
              and not any(x in m['name'] for x in ('tts', 'image', 'live', 'embedding', 'audio', 'exp', 'preview'))]
    return sorted(usable)[-1] if usable else None


def review_with_gemini(rules, prompt):
    model = GEMINI_MODEL
    tried_lite = False
    payload = {
        'systemInstruction': {'parts': [{'text': rules}]},
        'contents': [{'role': 'user', 'parts': [{'text': prompt}]}],
        'generationConfig': {'temperature': 0.1, 'responseMimeType': 'application/json'},
    }
    for attempt in range(5):
        url = f'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent'
        try:
            data = http_json(url, payload, {'x-goog-api-key': GEMINI_KEY})
            text = ''.join(p.get('text', '') for p in data['candidates'][0]['content']['parts'])
            return json.loads(text), f'gemini ({model})'
        except urllib.error.HTTPError as err:
            body = err.read().decode('utf-8', 'replace')
            print(f'Gemini API error {err.code} for {model}:')
            print(body)
            if err.code == 404 and attempt == 0:
                fallback = pick_gemini_model()
                if fallback and fallback != model:
                    print(f'Gemini model {model} not available; using {fallback}.')
                    model = fallback
                    continue
            if err.code == 429 and 'quota' in body.lower() and not tried_lite:
                # Out of quota for this model (often: free tier has none): try Flash-Lite once.
                tried_lite = True
                lite = pick_gemini_model(lite=True)
                if lite and lite != model:
                    print(f'Out of quota for {model}; trying {lite}.')
                    model = lite
                    continue
            if err.code in (429, 500, 503) and attempt < 3:
                time.sleep(15 * (attempt + 1))
                continue
            first = json.loads(body).get('error', {}).get('message', body) if body.startswith('{') else body
            raise RuntimeError(f'Gemini API error {err.code}: {first[:400]}')
    raise RuntimeError('Gemini API kept failing')


def review_with_claude(rules, prompt):
    import anthropic

    client = anthropic.Anthropic(api_key=ANTHROPIC_KEY, max_retries=3)
    response = client.beta.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=16000,
        betas=['server-side-fallback-2026-07-01'],
        fallbacks='default',
        system=rules,
        output_config={'effort': 'high', 'format': {'type': 'json_schema', 'schema': FINDINGS_SCHEMA}},
        messages=[{'role': 'user', 'content': prompt}],
    )
    if response.stop_reason == 'refusal':
        raise RuntimeError('Claude declined to review this change (refusal).')
    text = next(block.text for block in response.content if block.type == 'text')
    return json.loads(text), f'claude ({response.model})'


def clean(findings, files):
    out = []
    for f in findings if isinstance(findings, list) else []:
        if not isinstance(f, dict):
            continue
        severity = str(f.get('severity', 'WARNING')).upper()
        try:
            line = int(f.get('line') or 0)
        except (TypeError, ValueError):
            line = 0
        out.append({
            'severity': 'BLOCKER' if severity == 'BLOCKER' else 'WARNING',
            'category': str(f.get('category', 'AI review'))[:60],
            'file': str(f.get('file', '')),
            'line': line,
            'message': str(f.get('message', '')).strip(),
            'fix': str(f.get('fix', '')).strip(),
        })
    order = {'BLOCKER': 0, 'WARNING': 1}
    return sorted(out, key=lambda x: (order[x['severity']], x['file'], x['line']))


def cell(value, limit):
    return str(value).replace('|', '\\|').replace('\n', ' ')[:limit]


def write_report(status, provider, summary, findings, files, truncated, label, note=''):
    blockers = [f for f in findings if f['severity'] == 'BLOCKER']
    warnings = [f for f in findings if f['severity'] == 'WARNING']
    md = ['## AI Review (WP.org rules + security)', '']
    if status == 'skipped':
        md.append(note or 'Skipped.')
    elif status == 'error':
        md.append(f':warning: The AI review could not run: {cell(note, 400)}')
        md.append('')
        md.append('This does not block the merge; the pattern-based checks above still apply.')
    elif not files:
        md.append(summary or 'No reviewable plugin code changed.')
    else:
        result = 'FAIL: fix the AI-reported blockers before merging' if blockers else 'PASS: no blockers found by the AI review'
        done = len(files) - len(truncated)
        scope = (f'{done} of {len(files)} file(s) ({label})' if FULL_AUDIT and truncated
                 else f'{len(files)} file(s) ({label})' if FULL_AUDIT
                 else f'{len(files)} changed file(s) in the {label}')
        md += [f'**Result: {result}**', '', f'Reviewed {scope} with {provider}.', '']
        if summary:
            md += [cell(summary, 1500), '']
        md += ['| Blockers | Warnings |', '|---|---|', f'| {len(blockers)} | {len(warnings)} |']
        for title, rows in (('Blockers', blockers), ('Warnings', warnings)):
            if rows:
                md += ['', f'### {title}', '', '| Category | File | Issue | How to fix |', '|---|---|---|---|']
                for f in rows[:100]:
                    where = f"{f['file']}:{f['line']}" if f['line'] else f['file']
                    md.append(f"| {cell(f['category'], 40)} | `{cell(where, 120)}` | {cell(f['message'], 400)} | {cell(f['fix'], 300)} |")
        if truncated:
            why = 'the request for these files failed' if FULL_AUDIT else 'too large'
            md += ['', f'Not reviewed ({why}): ' + ', '.join(f'`{t}`' for t in truncated)]
        md += ['', '_AI findings can be wrong. If a blocker is a false positive, explain it in the PR and ask a maintainer to override._']
    report = '\n'.join(md) + '\n'
    open('ai-report.md', 'w', encoding='utf-8').write(report)
    json.dump({'status': status, 'provider': provider, 'summary': summary, 'findings': findings},
              open('ai-findings.json', 'w', encoding='utf-8'), indent=2)
    summary_path = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary_path:
        open(summary_path, 'a', encoding='utf-8').write(report)
    set_output(ai_status=status, ai_blockers=len(blockers), ai_warnings=len(warnings), ai_provider=provider or 'none')
    print(report)


def review(rules, prompt):
    if ANTHROPIC_KEY:
        return review_with_claude(rules, prompt)
    return review_with_gemini(rules, prompt)


def run_audit(rules):
    files, batches = collect_audit()
    label = 'full plugin audit'
    if not files:
        write_report('ok', 'none', 'No reviewable plugin code found.', [], [], [], label)
        return
    context = context_blocks(set())
    findings, summaries, provider = [], [], ''
    pending = list(enumerate(batches))
    for attempt in range(2):
        retry = []
        for n, (i, batch) in enumerate(pending):
            if (n or attempt) and not ANTHROPIC_KEY:
                time.sleep(BATCH_PAUSE_SECONDS)
            names = sorted({b.split('\n', 1)[0].replace('### FILE: ', '').split(' (part ')[0] for b in batch})
            print(f'Audit batch {i + 1}/{len(batches)}: {len(names)} file(s)' + (' (retry)' if attempt else ''))
            tag = f' (batch {i + 1} of {len(batches)})' if len(batches) > 1 else ''
            try:
                result, provider = review(rules, build_prompt(batch, [], label, context, tag))
            except Exception as err:  # noqa: BLE001 - keep going; report what could not be reviewed
                print(f'Batch {i + 1} failed: {err}')
                retry.append((i, batch))
                continue
            if isinstance(result.get('findings'), list):
                findings += result['findings']
            if result.get('summary'):
                summaries.append(str(result['summary']))
        pending = retry
        if not pending:
            break
        if attempt == 0:
            # Provider overload (503) or rate limits usually clear within a couple of minutes.
            print(f'{len(pending)} batch(es) failed; retrying once in 2 minutes.')
            time.sleep(120)
    failed = sorted({b.split('\n', 1)[0].replace('### FILE: ', '').split(' (part ')[0]
                     for _, batch in pending for b in batch})
    if len(failed) == len(files):
        write_report('error', '', '', [], files, [], label, 'every audit batch failed; see the job log')
        return
    write_report('ok', provider, ' '.join(summaries), clean(findings, files), files, failed, label)


def main():
    if not GEMINI_KEY and not ANTHROPIC_KEY:
        write_report('skipped', '', '', [], [], [], '', 'No AI key configured (add a GEMINI_API_KEY or ANTHROPIC_API_KEY secret to enable the AI review).')
        return
    rules = load_rules()
    if FULL_AUDIT:
        run_audit(rules)
        return
    files, parts, truncated, label = collect_changes()
    if not files:
        write_report('ok', 'none', 'No reviewable plugin code changed in this commit.', [], [], [], label)
        return
    prompt = build_prompt(parts, truncated, label, context_blocks(set(files)))
    try:
        result, provider = review(rules, prompt)
    except Exception as err:  # noqa: BLE001 - any provider failure is reported, not fatal
        write_report('error', '', '', [], files, truncated, label, str(err))
        return
    write_report('ok', provider, str(result.get('summary', '')), clean(result.get('findings', []), files), files, truncated, label)


if __name__ == '__main__':
    sys.exit(main())

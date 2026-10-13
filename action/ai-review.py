#!/usr/bin/env python3
"""AI review of the plugin code changed by a commit or pull request.

Sends the diff (plus the full changed files for context) and the WPPOOL review rules to
Claude (if ANTHROPIC_API_KEY is set) or Gemini (if GEMINI_API_KEY is set) and writes:

  ai-findings.json   structured findings
  ai-report.md       Markdown report (run summary + PR comment)
  $GITHUB_OUTPUT     ai_status, ai_blockers, ai_warnings, ai_provider

An API failure is reported as ai_status=error and never fails the job by itself, so a
provider outage cannot block merges. Real findings are judged by the Compliance Gate.
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

CODE_EXTENSIONS = ('.php', '.js', '.jsx', '.ts', '.tsx', '.mjs', '.vue')
ALWAYS_SKIP = ('vendor/', 'node_modules/', '.git/', '.github/', 'build/', 'dist/')
MAX_FILE_CHARS = 60000
MAX_TOTAL_CHARS = 350000

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
        try:
            content = open(name, encoding='utf-8', errors='replace').read()
        except OSError:
            content = ''
        numbered = '\n'.join(f'{i + 1:5d}| {line}' for i, line in enumerate(content.splitlines()))
        if len(numbered) > MAX_FILE_CHARS:
            numbered = numbered[:MAX_FILE_CHARS] + '\n... (file truncated for length)'
        block = f'### FILE: {name}\n\n#### Diff\n```diff\n{diff or "(new file / no diff available)"}\n```\n\n#### Full file (new version, with line numbers)\n```\n{numbered}\n```\n'
        if total + len(block) > MAX_TOTAL_CHARS:
            truncated.append(name)
            continue
        parts.append(block)
        total += len(block)
    return files, parts, truncated, label


def build_prompt(parts, truncated, label):
    lines = [
        f'Review the following WordPress plugin changes ({label}).',
        f'Plugin text domain / slug: {TEXT_DOMAIN or "(not provided)"}.',
        'Return JSON matching this shape: {"summary": string, "findings": [{"severity": "BLOCKER"|"WARNING", '
        '"category": string, "file": string, "line": integer, "message": string, "fix": string}]}.',
        'Use the exact file paths shown after "FILE:". Report only real problems in the changed code.',
        '',
    ]
    if truncated:
        lines.append('These changed files were too large to include and were not reviewed: ' + ', '.join(truncated))
        lines.append('')
    return '\n'.join(lines) + '\n'.join(parts)


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
        md += [f'**Result: {result}**', '', f'Reviewed {len(files)} changed file(s) in the {label} with {provider}.', '']
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
            md += ['', 'Not reviewed (too large): ' + ', '.join(f'`{t}`' for t in truncated)]
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


def main():
    if not GEMINI_KEY and not ANTHROPIC_KEY:
        write_report('skipped', '', '', [], [], [], '', 'No AI key configured (add a GEMINI_API_KEY or ANTHROPIC_API_KEY secret to enable the AI review).')
        return
    files, parts, truncated, label = collect_changes()
    if not files:
        write_report('ok', 'none', 'No reviewable plugin code changed in this commit.', [], [], [], label)
        return
    rules = open(RULES_FILE, encoding='utf-8').read()
    prompt = build_prompt(parts, truncated, label)
    try:
        if ANTHROPIC_KEY:
            result, provider = review_with_claude(rules, prompt)
        else:
            result, provider = review_with_gemini(rules, prompt)
    except Exception as err:  # noqa: BLE001 - any provider failure is reported, not fatal
        write_report('error', '', '', [], files, truncated, label, str(err))
        return
    write_report('ok', provider, str(result.get('summary', '')), clean(result.get('findings', []), files), files, truncated, label)


if __name__ == '__main__':
    sys.exit(main())

# WPPOOL Plugin Reviewer

Comprehensive WordPress plugin reviewer for WP.org compliance, security, and coding standards. Built from 9 real WP.org plugin closures (Aug 2026) plus full WP.org guideline set and PCP Plugin Check source.

## What It Does

- **Finds ALL issues** across 10 audit categories + 7 bonus checks
- **Suggests specific fixes** with before→after code for each finding
- **Auto-applies fixes** when you confirm (`--fix` flag)
- **Generates pro plugin filter scaffold** for trialware (Guideline 5) fixes
- **WPPOOL-specific patterns**: Appsero SDK, Headway changelog widget, IP-fetch services

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- Git (for cloning this repo)

## Installation

### Option 1: Git Clone (Recommended — supports auto-update)

Clone directly into Claude Code skills directory. Skill auto-checks for updates on every run.

**Mac/Linux:**
```bash
# Account-level (available in ALL projects)
git clone https://github.com/WPPOOL/wppool-plugin-reviewer.git ~/.claude-account2/skills/wppool-plugin-reviewer

# OR project-level (current project only)
git clone https://github.com/WPPOOL/wppool-plugin-reviewer.git ./.claude/skills/wppool-plugin-reviewer
```

**Windows (PowerShell):**
```powershell
# Account-level
git clone https://github.com/WPPOOL/wppool-plugin-reviewer.git "$env:USERPROFILE\.claude-account2\skills\wppool-plugin-reviewer"

# OR project-level
git clone https://github.com/WPPOOL/wppool-plugin-reviewer.git ".\.claude\skills\wppool-plugin-reviewer"
```

> **Auto-update**: When installed via git clone, skill checks for updates at the start of every audit. If new version available, it asks to pull before proceeding.

### Option 2: Install Script

```bash
# Clone repo first
git clone https://github.com/WPPOOL/wppool-plugin-reviewer.git
cd wppool-plugin-reviewer

# Mac/Linux
./install.sh

# Windows (PowerShell)
.\install.ps1
```

> Note: Install script copies files (no .git), so auto-update won't work. Use Option 1 for auto-update.

### Option 3: Manual Copy

**Windows:**
```powershell
Copy-Item -Recurse -Force ".\wppool-plugin-reviewer" "$env:USERPROFILE\.claude-account2\skills\wppool-plugin-reviewer"
```

**Mac/Linux:**
```bash
cp -r ./wppool-plugin-reviewer ~/.claude-account2/skills/wppool-plugin-reviewer
```

> Note: Manual copy has no auto-update. Use Option 1 for auto-update.

## Verify Installation

Start Claude Code and type:

```
/wppool-plugin-reviewer
```

If skill shows in autocomplete, installation successful.

## Usage

### Full Audit (Default)

```
/wppool-plugin-reviewer /path/to/your-plugin --full
```

Runs all 10 audit categories:

| # | Category | What It Checks |
|---|---|---|
| 1 | Trialware (G5) | `is_pro` gates, bad filter defaults, locked features |
| 2 | External Services (G6/G7/G8) | Undocumented API calls, remote JS/CSS, tracking |
| 3 | Security I/O | Sanitization, escaping, nonces, capabilities, ABSPATH |
| 4 | Security Advanced | SQL injection, file ops, eval/exec, object injection |
| 5 | Build & Source | Minified without source, missing build configs |
| 6 | Readme & Headers | Stable tag, version mismatch, tags count, license |
| 7 | Naming & Prefixes | Global prefix check, text domain mismatch |
| 8 | Core Library Bundling | jQuery, PHPMailer, SimplePie duplicates |
| 9 | Admin UX | Sitewide nags, forced credits, review manipulation |
| 10 | WPPOOL Common | Appsero SDK, Headway widget, IP-fetch patterns |

### Quick Scan (Top 5 Closure Causes)

```
/wppool-plugin-reviewer /path/to/your-plugin --quick
```

Checks only: trialware, external services, build/source, Appsero, prefixes.

### Category-Specific Scans

```
/wppool-plugin-reviewer /path/to/your-plugin --trialware   # G5 deep scan only
/wppool-plugin-reviewer /path/to/your-plugin --security     # Security categories only
/wppool-plugin-reviewer /path/to/your-plugin --services     # External services only
```

### Fix Mode

```
/wppool-plugin-reviewer /path/to/your-plugin --fix
```

Runs full audit, then for each finding:

1. **Shows fix plan** with exact before→after changes and risk level
2. **Asks confirmation** — apply all, or select individual fixes
3. **Applies fixes** by priority (blockers first)
4. **Generates pro filter scaffold** in `ai-docs/pro-filters-scaffold.php`
5. **Verifies** no regressions introduced

### Natural Language Triggers

Skill auto-triggers when you say things like:

- "review this plugin"
- "check compliance"
- "audit before submission"
- "prepare for WP.org"
- "fix closure issues"
- "fix all issues"
- "pre-submission check"

## Report Format

Audit produces structured report:

```
=== WPPOOL PLUGIN REVIEWER REPORT ===
Plugin: your-plugin-name
Date: 2026-10-11
Mode: --full

BLOCKERS (will cause closure): 3
WARNINGS (may cause closure): 7
INFO: 2

--- CATEGORY 1: TRIALWARE (G5) ---
[BLOCKER] src/class-settings.php:142
  is_pro gate wrapping save handler
  FIX: Remove gate, wrap in apply_filters('prefix_can_save', true)
  Auto-fixable: YES

[BLOCKER] src/class-render.php:89
  apply_filters('prefix_styles', []) — empty array as lock
  FIX: Replace default with real style list from config
  Auto-fixable: YES
...
```

## Knowledge Files

Skill includes 5 reference documents in `knowledge/`:

| File | Content |
|---|---|
| `closure-case-studies.md` | Patterns from 9 real WP.org plugin closures |
| `compliant-trialware-pattern.md` | Fix patterns from EchoRewards + WP Dark Mode |
| `grep-patterns.md` | Copy-paste grep commands by category |
| `official-guidelines-and-pcp.md` | 18 WP.org guidelines + 20 PCP checks |
| `reviewer-response-templates.md` | Reply templates for WP.org closure emails |

## File Structure

```
wppool-plugin-reviewer/
├── README.md                    # This file
├── install.sh                   # Install script (Mac/Linux)
├── install.ps1                  # Install script (Windows)
├── SKILL.md                     # Main skill definition (1310 lines)
└── knowledge/
    ├── closure-case-studies.md
    ├── compliant-trialware-pattern.md
    ├── grep-patterns.md
    ├── official-guidelines-and-pcp.md
    └── reviewer-response-templates.md
```

## Updating

### Auto-Update (Git Clone install)

If installed via git clone (Option 1), skill auto-checks for updates every time it runs. When update found, it asks before pulling.

You can also manually update anytime:

```bash
cd ~/.claude-account2/skills/wppool-plugin-reviewer
git pull
```

### Manual Update (Script/Copy install)

Re-run install script or copy files again:

```bash
cd wppool-plugin-reviewer
git pull
./install.sh   # or .\install.ps1 on Windows
```

## Contributing

To add new closure patterns or detection rules:

1. Add grep patterns to `knowledge/grep-patterns.md`
2. Add case study to `knowledge/closure-case-studies.md`
3. Update relevant category in `SKILL.md`
4. Test against known-good and known-bad plugin

## License

MIT

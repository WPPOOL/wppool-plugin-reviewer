---
name: wppool-plugin-reviewer
description: >
  Comprehensive WordPress plugin reviewer for WP.org compliance, security, and
  coding standards. Built from 9 real WP.org plugin closures (Aug 2026) plus
  the full WP.org guideline set. Finds AND fixes: trialware (G5), undocumented
  services, security gaps, escaping/sanitization, prefix collisions, build-source
  gaps, and WPPOOL-common patterns (bundled SDKs, changelog widgets, IP-fetch
  services). Use --fix flag to auto-apply fixes after audit. Generates pro plugin
  filter scaffold when fixing trialware issues. Use when: auditing a plugin before
  WP.org submission, responding to a closure email, reviewing a plugin diff,
  running a pre-release gate, fixing all compliance issues, or whenever asked to
  "review plugin", "check compliance", "audit before submission", "prepare for
  WP.org", "fix closure issues", "fix all issues", "plugin review",
  "pre-submission check", "review before release", "fix plugin".
  Auto-triggers on any WordPress plugin codebase when the user asks for a review,
  audit, or fix.
argument-hint: "plugin-path [--full|--trialware|--security|--services|--quick|--fix]"
---

# WPPOOL Plugin Reviewer

Expert WordPress plugin reviewer combining WP.org compliance, security audit,
and coding standards enforcement. Built from 9 real plugin closures and the
complete WP.org guideline set.

---

## How This Skill Works

This skill runs a **structured, grep-driven audit** across every category that
has caused real WP.org closures. It does not duplicate the deep-dive reference
material in `wp-standards-checker` (compliance) or `wp-plugin-security-review`
(security); it orchestrates them and adds the layer they miss: **real closure
patterns, WPPOOL-specific tech debt, and a master pre-submission gate**.

### Execution Modes

| Flag | What runs |
|------|-----------|
| `--full` (default) | All 10 audit categories |
| `--trialware` | Category 1 only (G5 deep scan) |
| `--security` | Categories 3-4 only |
| `--services` | Category 2 only (external services) |
| `--quick` | Top-5 closure causes only (G5, services, source, Appsero, prefixes) |
| `--fix` | Run full audit, then apply fixes for all findings (with user confirmation) |

---

## Execution Pipeline

### STEP 0 — Setup

1. Detect plugin root from argument or open file context
2. Find main plugin file: `grep -rl "Plugin Name:" <path> --include="*.php" | head -1`
3. Extract plugin slug from directory name
4. Extract text domain from plugin header
5. Check if `wp-standards-checker` and `wp-plugin-security-review` skills exist

### STEP 1 — Attack Surface Map

Before diving into categories, build a map:

```bash
# Entry points — ordered by risk (unauthenticated first)
grep -rn "wp_ajax_nopriv_" <path> --include="*.php"
grep -rn "register_rest_route" <path> --include="*.php"
grep -rn "wp_ajax_" <path> --include="*.php"
grep -rn "add_shortcode" <path> --include="*.php"
grep -rn "admin_init" <path> --include="*.php"

# External calls
grep -rn "wp_remote_get\|wp_remote_post\|wp_remote_request\|wp_remote_head" <path> --include="*.php"
grep -rn "fetch(\|XMLHttpRequest\|axios\.\|\.ajax(" <path> --include="*.js" --include="*.jsx" --include="*.ts"
grep -rn "https\?://" <path> --include="*.js" --include="*.min.js" | grep -v "node_modules\|vendor"

# Pro/license gates
grep -rni "is_pro\|isPro\|is_premium\|license_status\|license_key\|can_use_premium" <path> --include="*.php"
grep -rni "is_pro\|isPro\|is_premium\|proActive\|isProActive" <path> --include="*.js" --include="*.jsx"
```

### STEP 2 — Run All 10 Audit Categories

Run each category below in order. For each finding:
- Record: file, line, category, severity, grep pattern that found it
- Classify: BLOCKER (will cause closure) vs WARNING (may cause closure) vs INFO

### STEP 3 — Generate Report

Output structured report per the format at the bottom of this file.

### STEP 4 — Cross-Reference Other Skills

If installed, invoke:
- `wp-standards-checker` for PHPCS/WPCS automated scan
- `wp-plugin-security-review` for deep security audit on flagged endpoints

### STEP 5 — Fix Mode (`--fix` or user says "fix it")

After generating report, if `--fix` flag or user confirms, apply fixes in order:

**Phase 1: Show fix plan** — For each finding, show:
```
FINDING: [category] [file:line]
ISSUE: [what's wrong]
FIX: [exact before → after change]
RISK: [LOW/MEDIUM/HIGH — can this break something?]
```

Ask user: "Apply all fixes? Or select which ones?"

**Phase 2: Apply fixes by category priority** (blockers first):

1. **Trialware (G5)** — Most complex; per-finding:
   - `is_pro` PHP gate wrapping functionality →
     Remove gate, wrap value in `apply_filters('prefix_feature', $real_default)`
   - `apply_filters()` with bad default (null/false/[]) →
     Replace default with real working value from plugin's config/defaults
   - Disabled UI + active backend →
     Remove PHP disabled attr; keep JS-only lock via `wp_localize_script()`
   - Feature code that returns early without Pro →
     Convert to filter hook pattern: `apply_filters()` in free, `add_filter()` in pro
   - Missing `wp_localize_script()` for `is_pro` →
     Add to existing enqueue function: `'is_pro' => apply_filters('prefix_is_pro', false)`
   - **Generate pro-side filter file** — Create `ai-docs/pro-filters-scaffold.php`
     showing all `add_filter()` calls pro plugin needs to register

2. **External Services (G6/G7/G8)** —
   - Missing readme disclosure →
     Generate `== External services ==` section with all found URLs
   - Headway widget undisclosed →
     Add to readme + wrap in opt-in check
   - IP-fetch undisclosed →
     Add to readme with ToS/Privacy links
   - Remote JS/CSS loading →
     Flag for manual fix (must bundle locally)

3. **Security — I/O** —
   - Raw `$_POST`/`$_GET` →
     Replace with `isset($_POST['key']) ? sanitize_text_field(wp_unslash($_POST['key'])) : ''`
   - `wp_unslash($_POST)` (bulk unslash) →
     Replace with per-key sanitization
   - `filter_input()` without FILTER →
     Add `FILTER_SANITIZE_FULL_SPECIAL_CHARS` or appropriate filter
   - `json_encode` →
     Replace with `wp_json_encode`
   - `register_setting` without `sanitize_callback` →
     Add sanitize_callback to third arg array
   - `echo $var` without escaping →
     Wrap in `esc_html()`, `esc_attr()`, or `wp_kses_post()` based on context
   - SQL without `$wpdb->prepare()` →
     Wrap query in `$wpdb->prepare()` with proper placeholders

4. **Security — Auth** —
   - AJAX handler missing nonce →
     Add `check_ajax_referer('prefix_nonce', 'nonce')` at top
   - AJAX handler missing capability check →
     Add `if (!current_user_can('manage_options')) wp_send_json_error()`
   - REST route missing `permission_callback` →
     Add `'permission_callback' => function() { return current_user_can('manage_options'); }`
   - `wp_ajax_nopriv_` for privileged action →
     Change to `wp_ajax_` only

5. **Libraries** —
   - Appsero outdated →
     Flag for Composer update (can't auto-fix version)
   - Core include instead of require_once →
     Replace `include ABSPATH` with `if (!function_exists('fn')) { require_once ABSPATH...}`
   - Custom updater hooks →
     Comment out / remove `pre_set_site_transient_update_plugins` and `plugins_api` hooks
   - Bundled jQuery →
     Remove file, use WP's jQuery dependency in enqueue

6. **Build & Source** —
   - HEREDOC →
     Replace with string concatenation
   - Binary zip files →
     Flag for removal (manual action)
   - Filenames with spaces →
     Rename file, update all references

7. **Naming & i18n** —
   - Wrong text domain →
     Replace all instances with correct plugin slug
   - Variables as text domain →
     Replace `$variable` with literal string
   - Unprefixed AJAX actions →
     Add plugin prefix: `wp_ajax_prefix_action_name`
   - Unprefixed cache groups →
     Add plugin prefix to cache group string

8. **Plugin Behavior** —
   - Global hook hijacking (`clean_url` etc.) →
     Scope filter to plugin's own URLs only, or remove
   - Defining core constants →
     Remove the `define()` call
   - Hardcoded `wp-content` paths →
     Replace with `WP_PLUGIN_DIR`, `plugin_dir_path()`, `rest_url()`
   - Missing ABSPATH guard →
     Add `if ( ! defined( 'ABSPATH' ) ) { exit; }` after opening `<?php`
   - Activation output (echo during activation) →
     Remove echo/print from activation callback
   - `flush_rewrite_rules()` on every load →
     Move to activation/deactivation hook only

9. **Assets** —
   - Sourcemap remote URLs →
     Remove sourcemap reference or make local
   - Dead vendor dirs →
     Flag for removal (manual action)

10. **A11y & UX** —
    - 5-star filtered review link →
      Remove `?filter=5` from URL
    - Non-dismissible admin notice →
      Add `is-dismissible` class
    - Powered-by link default ON →
      Change default to OFF, add opt-in setting

**Phase 3: Post-fix verification**
- Re-run grep patterns for all fixed categories
- Report: "X findings fixed, Y remaining (manual action needed)"
- List remaining manual items user must handle

**Phase 4: Generate pro plugin scaffold** (if trialware fixes applied)
- Create `ai-docs/pro-filters-scaffold.php` with:
  - All `add_filter()` registrations pro plugin needs
  - Callback stubs that read saved options
  - License check wrapper pattern
  - Based on real EchoRewards/WP Dark Mode architecture

---

## THE 10 AUDIT CATEGORIES

---

### CATEGORY 1: TRIALWARE & LOCKED FEATURES (Guideline 5)

**Priority: CRITICAL — #1 closure cause. Flagged in 9/9 real closures.**

This is the most nuanced category. WP.org uses AI + human review to find it.
The test is simple: **"If Pro were deactivated, does any feature the free
plugin's UI exposes stop working, degrade, or reject input?"**

#### 1.1 — Direct `is_pro` / license gates

**Detection:**
```bash
# PHP-side gates
grep -rn "is_pro\b\|->is_pro\|is_premium\b\|license_status\|license_key\|can_use_premium\|is_ultimate" <path> --include="*.php" | grep -v "vendor/"

# Class/function existence checks used as gates
grep -rn "class_exists.*Pro\|defined.*PRO_VERSION\|function_exists.*pro" <path> --include="*.php" | grep -v "vendor/"

# JS-side gates that control functionality (not just UI badges)
grep -rn "isPro\|isProActive\|is_pro\|proActive\|premiumActive" <path> --include="*.js" --include="*.jsx" --include="*.ts" --include="*.tsx" | grep -v node_modules
```

**What's a violation:**
- PHP `if ($this->is_pro)` wrapping save handlers, render logic, AJAX responses, REST endpoints, cron jobs
- `apply_filters('prefix_feature', null/false/[])` where default = locked/empty/rejected
- `disabled` UI control + backend `register_setting()` still registered for that option
- Feature code exists in free but returns early / strips keys / shows error when Pro absent

**What's NOT a violation:**
- `wp_localize_script()` passing `is_pro` flag purely for UI badges/lock icons (zero PHP branching)
- Pro plugin adding entirely new features via `add_filter()` that don't exist in free at all
- Free plugin exposing `apply_filters()` with a REAL working default (not null/false/empty)

**Fix (per violation type):**

| Violation | Fix |
|---|---|
| `if ($this->is_pro) { process(); }` | Remove gate. Wrap value: `$val = apply_filters('prefix_feature', $real_default);` |
| `apply_filters('x', null)` as lock | Change default to real working value from plugin config |
| PHP disabled control + active backend | Remove PHP `disabled`; lock in JS only via `wp_localize_script` |
| Feature returns early without Pro | Convert to filter hook: free has `apply_filters()` with default, pro hooks via `add_filter()` |
| No `wp_localize_script` for is_pro | Add to existing enqueue: `'is_pro' => apply_filters('prefix_is_pro', false)` |
| Pro code in free plugin files | Move to pro plugin; replace with `apply_filters()` / `do_action()` extension points |

**The definitive test (per real WP.org pass):**
> Deactivate Pro. Exercise every feature free's UI exposes. If anything fails
> to save, silently strips data, or returns a rejection reason — it's trialware,
> regardless of whether `if($is_pro)` or a filter hook does the gating.

#### 1.1b — Compliant Fix Pattern (how to PASS review)

Full reference: `knowledge/compliant-trialware-pattern.md`

The pattern that re-listed 3/3 plugins follows these rules:

1. **PHP `apply_filters()` with REAL working defaults** — default must be a value
   that makes free plugin work correctly. Never `null`/`false`/`[]` as a lock.
   Good: `apply_filters('prefix_reward_type', 'percent', $settings)` — 'percent' works.
   Bad: `apply_filters('prefix_feature_enabled', false)` then `if (!$enabled) return;`

2. **Render/output logic has ZERO license checks** — shortcode, block, widget render
   must process any valid value without checking `is_pro`/`is_ultimate`.

3. **Pro hooks in via `add_filter()` only** — Pro plugin registers filters when
   licensed, each callback reads saved option and returns it. All pro code lives
   in pro plugin files.

4. **`wp_localize_script()` for JS display only** — `is_pro` boolean reaches JS
   via `wp_localize_script()`. JS uses it for disabled inputs, lock icons, upgrade
   popups. Zero effect on PHP.

5. **Allowed `is_pro` uses in free PHP**: definition, `wp_localize_script` pass-through,
   admin upgrade menu visibility, resetting settings to working defaults.

When auditing, verify each `is_pro` hit against this pattern. If it matches
an allowed use, mark PASS. If not, mark BLOCKER.

#### 1.2 — Tier-naming in free code (review-optics risk)

**Detection:**
```bash
# Variable/function/constant names that broadcast tier boundaries
grep -rni "\b\(free\|pro\|premium\|lite\|trial\|license\)_" <path> --include="*.php" | grep -v "vendor/" | grep -v "//.*\|/\*"
```

**Fix:** Rename `$free_channel_ids` → `$channel_ids`. The free plugin has no
legitimate reason to know it's "the free one."

#### 1.3 — Disabled UI + active backend (the subtle one)

**Detection:**
```bash
# Find disabled controls
grep -rn "'disabled'\s*=>" <path> --include="*.php"
grep -rn "disabled=\|disabled:" <path> --include="*.js" --include="*.jsx" --include="*.tsx"

# Cross-reference: does register_setting() still register these options?
grep -rn "register_setting" <path> --include="*.php"
```

For each disabled field, verify its option name does NOT appear in
`register_setting()`. If it does → BLOCKER.

#### 1.4 — Stranded features (built then severed)

Look for options that save one value but consumers check for a different value:
```bash
# Options saved with a "disable-" prefix
grep -rn "'disable-\|\"disable-" <path> --include="*.php"
```

---

### CATEGORY 2: EXTERNAL SERVICES & PRIVACY (Guidelines 6, 7, 8)

**Priority: HIGH — flagged in 8/9 real closures.**

Every remote call (PHP AND JS) must be documented in readme.txt
`== External services ==` section with: what it is, what data is sent, when,
ToS link, Privacy Policy link.

#### 2.1 — PHP remote calls

**Detection:**
```bash
grep -rn "wp_remote_get\|wp_remote_post\|wp_remote_head\|wp_remote_request" <path> --include="*.php"
grep -rn "file_get_contents\s*(\s*['\"]http" <path> --include="*.php"
grep -rn "curl_init\|curl_exec" <path> --include="*.php"
```

**WPPOOL common hits (check ALL of these):**
- Appsero SDK → `api.appsero.com` — must be in readme
- Appsero/icanhazip → `icanhazip.com` — IP fetch, must be disclosed separately
- Google Sheets API → `sheets.googleapis.com` — needs Google ToS/Privacy links
- Jitsi Hosted → `jitsihosted.app` — needs disclosure
- FluentCRM/WPPOOL CRM → `fluent.wppool.dev` — needs disclosure
- Twilio → SMS service — needs disclosure
- UltraMsg → WhatsApp API — needs disclosure
- Chat API → WhatsApp API — needs disclosure
- OpenAI API → AI features — needs disclosure
- Google Gemini API → AI features — needs disclosure

#### 2.2 — JS remote calls

**Detection:**
```bash
# In source JS
grep -rn "fetch(\|XMLHttpRequest\|axios\.\|\.ajax(" <path> --include="*.js" --include="*.jsx" --include="*.ts" | grep -v node_modules

# In minified JS (look for URLs)
grep -on "https\?://[^\"' )\]\}]*" <path> --include="*.min.js" | grep -v "wordpress.org\|w3.org\|schema.org\|localhost"

# CDN-loaded scripts
grep -rn "wp_enqueue_script.*https\?://" <path> --include="*.php"
grep -rn "src=['\"]https\?://" <path> --include="*.php"
```

**WPPOOL common hits:**
- Headway widget → `cdn.headwayapp.co` — changelog widget, phones home (5/9 closures!)
- IPify → `api.ipify.org` — visitor IP fetch
- 8x8 JaaS → `8x8.vc/external_api.js` — meeting API
- FFmpeg → `unpkg.com/@ffmpeg` — remote dependency (BANNED, must be local)
- Pinia logo → `pinia.vuejs.org` — in .map files (still flagged!)
- YouTube embeds → `youtu.be` / `youtube.com` — needs disclosure
- Noembed → `noembed.com` — embed thumbnails

#### 2.3 — Tracking opt-in check

**Detection:**
```bash
# Appsero tracking — verify opt-in exists
grep -rn "allow_tracking\|optin\|opt_in\|tracking_skipped" <path> --include="*.php" | grep -v vendor
```

**Violation:** "No thanks" still sends data (flagged in Multi-Store Sync closure).
Choosing "No" must make ZERO external requests.

#### 2.4 — Readme disclosure verification

**Detection:**
```bash
grep -i "external services\|third.party\|3rd party" <path>/readme.txt
```

For every URL found in 2.1-2.2, verify it appears in readme with ToS + Privacy links.
**Verify links are not 404** (Appsero terms page was 404 in 2/9 closures).

**Fix (auto-generate readme section):**

For each undisclosed service found, generate this block for readme.txt:

```
== External services ==

= [Service Name] =
This plugin connects to [service URL] to [purpose].
Data sent: [what data].
This happens when [trigger condition].
[Service Terms of Service URL]
[Service Privacy Policy URL]
```

For Headway widget: wrap loading in opt-in check or remove entirely.
For tracking (Appsero): verify "No thanks" sends zero requests.

---

### CATEGORY 3: SECURITY — INPUT/OUTPUT (Class A blockers)

**Priority: HIGH — instant rejection.**

#### 3.1 — Sanitization

**Detection:**
```bash
# Raw superglobals without sanitization
grep -rn "\$_POST\b\|\$_GET\b\|\$_REQUEST\b\|\$_SERVER\b" <path> --include="*.php" | grep -v "vendor/"

# wp_unslash on entire $_POST (wrong — must sanitize per-key)
grep -rn "wp_unslash\s*(\s*\$_POST\s*)" <path> --include="*.php"

# filter_input without FILTER parameter
grep -rn "filter_input\s*(" <path> --include="*.php" | grep -v "FILTER_"

# json_decode without sanitization of decoded values
grep -rn "json_decode.*file_get_contents.*php://input" <path> --include="*.php"

# register_setting without sanitize_callback
grep -rn "register_setting" <path> --include="*.php"
```

Each `register_setting()` 3rd arg must be array with `sanitize_callback`.

**Fix (per pattern):**

| Pattern | Fix |
|---|---|
| `$_POST['key']` raw | `isset($_POST['key']) ? sanitize_text_field(wp_unslash($_POST['key'])) : ''` |
| `wp_unslash($_POST)` bulk | Split into per-key: `$key = sanitize_text_field(wp_unslash($_POST['key']))` |
| `filter_input(INPUT_GET, 'x')` | `filter_input(INPUT_GET, 'x', FILTER_SANITIZE_FULL_SPECIAL_CHARS)` |
| `json_decode` without sanitize | Sanitize each decoded value before use: `sanitize_text_field()` / `absint()` / `wp_kses_post()` |
| `register_setting` no callback | `register_setting('group', 'option', ['sanitize_callback' => 'sanitize_callback_fn'])` |

#### 3.2 — Output escaping

**Detection:**
```bash
# Bare echo without escaping
grep -rn "echo \$\|echo \"\$" <path> --include="*.php" | grep -v "esc_\|wp_kses\|wp_json_encode\|vendor/"

# json_encode instead of wp_json_encode
grep -rn "\bjson_encode\b" <path> --include="*.php" | grep -v "vendor/"

# Bare __() without esc wrapper
grep -rn "echo\s\+__(" <path> --include="*.php"
grep -rn "echo\s\+_e(" <path> --include="*.php"

# wp_add_inline_style with unescaped option values
grep -rn "wp_add_inline_style\|wp_add_inline_script" <path> --include="*.php"

# Shortcode callbacks — must escape return value
grep -rn "add_shortcode" <path> --include="*.php"
```

**Fix (per pattern):**

| Pattern | Fix |
|---|---|
| `echo $var` | `echo esc_html($var)` (text), `esc_attr($var)` (attribute), `wp_kses_post($var)` (HTML) |
| `json_encode()` | `wp_json_encode()` |
| `echo __('text', $domain)` | `echo esc_html__('text', 'literal-domain')` |
| `_e('text', $domain)` | `esc_html_e('text', 'literal-domain')` |
| Shortcode return unescaped | `return wp_kses_post($output)` or escape each variable |

#### 3.3 — SQL injection

**Detection:**
```bash
# Direct variable in SQL
grep -rn "\$wpdb->query\|\$wpdb->get_results\|\$wpdb->get_var\|\$wpdb->get_row\|\$wpdb->get_col" <path> --include="*.php" | grep -v "prepare\|vendor/"

# esc_sql without prepare (not safe alone)
grep -rn "esc_sql" <path> --include="*.php"
```

#### 3.4 — Nonce verification

**Detection:**
```bash
# AJAX handlers — check each has wp_verify_nonce or check_ajax_referer
grep -rn "wp_ajax_" <path> --include="*.php"

# For each state-changing handler, verify nonce check exists in same function
```

**Fix:** Add at top of every AJAX handler:
```php
check_ajax_referer( 'prefix_nonce', 'nonce' );
```
And in form/JS, pass nonce: `wp_create_nonce( 'prefix_nonce' )`

#### 3.5 — Capability checks

**Detection:**
```bash
# admin_init without current_user_can
grep -rn "add_action.*admin_init" <path> --include="*.php"

# REST routes without permission_callback
grep -rn "register_rest_route" <path> --include="*.php"
```

**Fix:**
- AJAX: `if ( ! current_user_can( 'manage_options' ) ) { wp_send_json_error(); }`
- REST: `'permission_callback' => function() { return current_user_can( 'manage_options' ); }`
- `wp_ajax_nopriv_` for privileged action: change to `wp_ajax_` only

#### 3.6 — ABSPATH guard

**Detection:**
```bash
# PHP files missing ABSPATH check
for f in $(find <path> -name "*.php" -not -path "*/vendor/*" -not -path "*/node_modules/*"); do
  head -20 "$f" | grep -q "defined.*ABSPATH\|defined.*WPINC" || echo "MISSING: $f"
done
```

**Fix:** Add after opening `<?php` tag:
```php
if ( ! defined( 'ABSPATH' ) ) {
	exit;
}
```

#### 3.7 — Dynamic option/transient names from user input

**Detection:**
```bash
# Option names built from user input (CRITICAL — flagged in WP Dark Mode)
grep -rn "update_option\|set_transient\|delete_option" <path> --include="*.php" | grep "\$_\|->get_param\|filter_input"
```

#### 3.8 — Dynamic method dispatch

**Detection:**
```bash
# $this->{$var}() or call_user_func with user input
grep -rn "\$this->{\$\|call_user_func.*\$_\|call_user_func.*get_param" <path> --include="*.php"
```

---

### CATEGORY 4: SECURITY — AUTHENTICATION & ACCESS

#### 4.1 — Unauthenticated plugin installation/activation

**Detection:**
```bash
# Can anyone install/activate plugins?
grep -rn "activate_plugin\|install_plugin\|deactivate_plugins" <path> --include="*.php"
```

Cross-check: does the containing function verify nonce + `current_user_can('install_plugins')`?

**Real closure pattern (FlexOrder):** unauthenticated AJAX endpoint could install
and activate WooCommerce because debug mode enabled + no auth checks.

#### 4.2 — Changing active plugins without consent

**Detection:**
```bash
grep -rn "deactivate_plugins\|activate_plugin" <path> --include="*.php"
```

**Violation:** Auto-deactivating another plugin (even your own Ultimate/Pro)
without explicit user click. Flagged in WP Dark Mode closure.

---

### CATEGORY 5: LIBRARIES & DEPENDENCIES

#### 5.1 — Outdated libraries

**Detection:**
```bash
# Appsero version check
grep -rn "version.*=.*'[0-9]\." <path>/*/appsero/*/Client.php 2>/dev/null || \
grep -rn "version.*=.*'[0-9]\." <path>/*/appsero/Client.php 2>/dev/null

# Check all vendor/lib directories for version strings
find <path> -path "*/vendor/*" -name "*.php" -o -path "*/lib/*" -name "*.php" | \
  xargs grep -l "version" | head -20
```

**WPPOOL pattern:** Appsero Client v2.0.2 was flagged in ALL 9 closures.

#### 5.2 — PHP library conflicts (no namespace prefix)

**Detection:**
```bash
# Manually bundled SDKs outside vendor/
find <path> \( -path "*/includes/*" -o -path "*/inc/*" -o -path "*/lib/*" \) \
  -name "Client.php" -o -name "Insights.php" -o -name "Updater.php" | \
  grep -v vendor

# Check for composer.json existence
test -f <path>/composer.json && echo "HAS composer.json" || echo "MISSING composer.json"

# Check class_exists guards
grep -rn "class\s\+\w\+" <path>/*/appsero/ --include="*.php" | head -5
```

**Fix:** Composer-manage the SDK, or at minimum wrap in `class_exists()` +
apply namespace prefixing tool (Strauss/Mozart/PHP-Scoper).

#### 5.3 — Core libraries bundled

**Detection:**
```bash
# jQuery bundled separately
find <path> -name "jquery*.js" -not -path "*/node_modules/*" | grep -v "\.min\.js\.map"
grep -rn "wp_enqueue_script.*jquery" <path> --include="*.php" | grep -v "array.*jquery"
```

**Violation (Stock Notifier):** jQuery v2 bundled when WP ships its own.

#### 5.4 — Custom update checker

**Detection:**
```bash
grep -rn "pre_set_site_transient_update_plugins\|plugins_api" <path> --include="*.php"
```

**Violation:** Overriding WP.org's updater with Appsero/custom updater. The free
WP.org-hosted plugin must NOT have its own update mechanism.

#### 5.5 — Core file includes

**Detection:**
```bash
# include (not require_once) of core files
grep -rn "include\s\+ABSPATH\|include\s*(\s*ABSPATH" <path> --include="*.php"

# Should be: require_once with function_exists guard
```

**Fix:** `if ( ! function_exists( 'get_plugins' ) ) { require_once ABSPATH . 'wp-admin/includes/plugin.php'; }`

---

### CATEGORY 6: BUILD & SOURCE CODE (Guideline 4)

#### 6.1 — Minified JS without source

**Detection:**
```bash
# Find all .min.js files
find <path> -name "*.min.js" -not -path "*/node_modules/*" -not -path "*/vendor/*"

# For each, check if unminified sibling exists
for f in $(find <path> -name "*.min.js" -not -path "*/node_modules/*"); do
  base="${f%.min.js}.js"
  test -f "$base" || echo "NO SOURCE: $f"
done

# Check for webpack/generated bundles without source
find <path> -name "*.js" -not -name "*.min.js" -not -path "*/node_modules/*" | \
  xargs grep -l "webpackBootstrap\|__webpack_require__" 2>/dev/null
```

**Fix:** Ship unminified source alongside, or add `== Build Instructions ==`
section in readme with public repo link.

#### 6.2 — HEREDOC/NOWDOC syntax (banned)

**Detection:**
```bash
grep -rn "<<<" <path> --include="*.php" | grep -v vendor
```

**Fix:** Replace with string concatenation or `ob_start()`/`ob_get_clean()`.

#### 6.3 — Obfuscation

**Detection:**
```bash
grep -rn "base64_decode\|eval\s*(" <path> --include="*.php" | grep -v vendor
grep -rn "p,a,c,k,e,r\|packer" <path> --include="*.js"
```

#### 6.4 — Binary/forbidden files

**Detection:**
```bash
# Zip files inside plugin
find <path> -name "*.zip" -o -name "*.tar.gz" -o -name "*.phar"

# Executable files
find <path> -name "*.exe" -o -name "*.dll" -o -name "*.so"
```

**Real pattern (WP Dark Mode):** `vendor/appsero.zip` was flagged.

#### 6.5 — Filenames with spaces

**Detection:**
```bash
find <path> -name "* *" -type f
```

**Real pattern:** `twentytwentyone copy.css` flagged in WP Dark Mode.

#### 6.6 — Remote JS/CSS (Guideline 8)

**Detection:**
```bash
# Remote script/style loading (except fonts)
grep -rn "wp_enqueue_script\|wp_register_script" <path> --include="*.php" | grep "http"
grep -rn "wp_enqueue_style\|wp_register_style" <path> --include="*.php" | grep "http" | grep -vi "font"

# Sourcemap references to remote URLs
grep -rn "sourceMappingURL.*http" <path> --include="*.js" --include="*.map"
```

**Real pattern (WP Dark Mode):** Pinia logo referenced in `.map` files from `pinia.vuejs.org`.

---

### CATEGORY 7: NAMING & INTERNATIONALIZATION

#### 7.1 — Generic prefixes

**Detection:**
```bash
# Functions/classes without 4+ char unique prefix
grep -rn "^function [a-z_]\+\s*(" <path> --include="*.php" | grep -v "vendor/"

# AJAX actions without prefix
grep -rn "wp_ajax_\|wp_ajax_nopriv_" <path> --include="*.php" | \
  grep -v "vendor/" | grep -v "wp_ajax_[a-z]\{4,\}_"

# Cache groups without prefix
grep -rn "wp_cache_set\|wp_cache_get" <path> --include="*.php" | grep -v vendor
```

**Real pattern (EchoRewards):** `activate_woocommerce`, `fetch_products_and_categories`,
`custom_cache_group` — all unprefixed AJAX hooks.

**Fix:**
- AJAX: `wp_ajax_activate_woocommerce` → `wp_ajax_ecre_activate_woocommerce`
- Cache: `'custom_cache_group'` → `'ecre_cache_group'`
- Functions: `function get_data()` → `function ecre_get_data()`
- Prefix must be 4+ chars, unique to plugin

#### 7.2 — Text domain mismatch

**Detection:**
```bash
# Get plugin slug
SLUG=$(basename <path>)

# Find all text domains used
grep -rohP "(?:__|_e|esc_html__|esc_html_e|esc_attr__|esc_attr_e|_x|_ex|_n|_nx)\([^)]+,\s*['\"]([^'\"]+)['\"]" <path> --include="*.php" -r | \
  grep -oP "['\"][^'\"]+['\"]$" | sort -u

# Any domain that doesn't match $SLUG is wrong
```

**Real patterns:**
- FlexTable used `wppool-turnstile` (wrong plugin domain!)
- FlexOrder used `wp-dark-mode` for 11 elements (copy-paste from another plugin)
- Multi-Store Sync used `stock-sync-with-google-sheet-for-woocommerce` (old slug)
- Stock Notifier used `stock_notifier` (underscores instead of hyphens)

**Fix:** Find-replace all wrong text domains with correct plugin slug:
```bash
# Replace wrong domain with correct slug
grep -rln "'wrong-domain'" <path> --include="*.php" | xargs sed -i "s/'wrong-domain'/'correct-slug'/g"
```

#### 7.3 — Variables as text domain

**Detection:**
```bash
grep -rn "__\(\$\|_e(\$\|esc_html__(\$\|esc_attr__(\$" <path> --include="*.php"
grep -rn "__(\|_e(\|esc_html__(\|esc_attr__(" <path> --include="*.php" | grep -v ",'[a-z]"
```

**Fix:** Replace `$this->text_domain` or `$variable` with literal string `'plugin-slug'`

#### 7.4 — Trademark in plugin name

**Detection:**
```bash
# Check plugin name header for WP/WordPress prefix
grep -n "Plugin Name:" <path>/*.php | head -1
```

**Real pattern (WP Dark Mode):** "WP" in plugin name — discouraged, repeat = ban.

---

### CATEGORY 8: PLUGIN BEHAVIOR

#### 8.1 — Global hook hijacking

**Detection:**
```bash
grep -rn "add_filter.*clean_url\|add_filter.*the_content\|add_filter.*script_loader_tag\|add_filter.*style_loader_tag" <path> --include="*.php" | grep -v vendor
```

**Real pattern (FlexMeeting):** `add_filter('clean_url', ...)` globally altering
every URL to add `#asyncload`.

#### 8.2 — Defining core constants

**Detection:**
```bash
grep -rn "define.*WP_NETWORK_ADMIN\|define.*WP_USER_ADMIN\|define.*WP_DEBUG\|define.*ABSPATH" <path> --include="*.php" | grep -v vendor
```

**Real pattern (Stock Notifier):** `define('WP_NETWORK_ADMIN', true)` globally
altering request context.

#### 8.3 — Unclosed ob_start

**Detection:**
```bash
OB_START=$(grep -rn "ob_start" <path> --include="*.php" | grep -v vendor | wc -l)
OB_END=$(grep -rn "ob_end_clean\|ob_get_clean\|ob_end_flush\|ob_get_flush" <path> --include="*.php" | grep -v vendor | wc -l)
# If OB_START > OB_END, there's a leak
```

#### 8.4 — Activation output

**Detection:**
```bash
# Check activation hooks for echo/print
grep -rn "register_activation_hook\|activate_" <path> --include="*.php"
# Then check referenced function for echo/print/var_dump/wp_die with message
```

**Real pattern (WP Dark Mode final round):** `Wp_Dark_Install::wp_dark_activate()`
echoed output during activation, causing "unexpected output" warning.

#### 8.5 — Writing to disallowed locations

**Detection:**
```bash
grep -rn "file_put_contents\|fwrite\|fopen.*w" <path> --include="*.php" | grep -v vendor | grep -v "wp_upload_dir"
```

**Violation:** Writing PHP code into plugin/theme directories. Use DB or `wp_upload_dir()`.

#### 8.6 — Hardcoded paths

**Detection:**
```bash
grep -rn "ABSPATH.*wp-content\|wp-content/plugins\|wp-content/themes\|/wp-json" <path> --include="*.php" | grep -v vendor
grep -rn "home_url.*wp-json" <path> --include="*.php"
```

**Fix:** Use `WP_PLUGIN_DIR`, `plugin_dir_path()`, `rest_url()`, `get_theme_root()`.

#### 8.7 — Requires Plugins header

**Detection:**
```bash
# If plugin checks for WooCommerce/other dependency
grep -rn "class_exists.*WooCommerce\|is_plugin_active.*woocommerce" <path> --include="*.php"

# Check if header exists
grep -n "Requires Plugins:" <path>/*.php | head -1
```

#### 8.8 — Rewrite rules flushed on every load

**Detection:**
```bash
grep -rn "flush_rewrite_rules\|add_rewrite_endpoint\|add_rewrite_rule" <path> --include="*.php"
```

Only flush on activation/deactivation, never on every page load.

---

### CATEGORY 9: SOURCEMAP & ASSET HYGIENE

#### 9.1 — Sourcemaps referencing external URLs

**Detection:**
```bash
grep -rn "sourceMappingURL\|sourceURL" <path> --include="*.js" --include="*.map" | grep "http"
```

#### 9.2 — Dead vendor weight

**Detection:**
```bash
# For each library dir, check if plugin code actually uses it
for dir in $(find <path>/vendor <path>/lib <path>/includes -maxdepth 2 -type d 2>/dev/null); do
  NAMESPACE=$(grep -roh "namespace [A-Za-z\\\\]*" "$dir" --include="*.php" | head -1 | sed 's/namespace //')
  if [ -n "$NAMESPACE" ]; then
    USES=$(grep -rn "$NAMESPACE" <path> --include="*.php" | grep -v "^$dir" | wc -l)
    [ "$USES" -eq 0 ] && echo "UNUSED: $dir ($NAMESPACE)"
  fi
done
```

---

### CATEGORY 10: ACCESSIBILITY & UX (Class E/F)

#### 10.1 — Admin notice compliance

**Detection:**
```bash
grep -rn "admin_notices\|all_admin_notices" <path> --include="*.php" | grep -v vendor
```

For each notice: must be dismissible, must not appear on all admin pages
(only on plugin's own pages), must not re-nag.

#### 10.2 — Filtered review links

**Detection:**
```bash
grep -rn "reviews/?filter=5\|filter=5" <path> --include="*.php" --include="*.js"
```

**Violation:** Linking to 5-star-filtered reviews = review manipulation (PCP ERROR blocker).

#### 10.3 — Powered-by links

**Detection:**
```bash
grep -rni "powered by\|powered-by\|credit.*link\|developer.*link" <path> --include="*.php"
```

Must be opt-in, default OFF.

---

### BONUS CHECKS (from wp-standards-checker knowledge base)

These additional checks come from `wp-standards-checker` rules not covered
in the 10 main categories above. Run these as part of `--full` audit.

#### B.1 — Plugin Check (PCP) automated scanner patterns

Full reference: `knowledge/official-guidelines-and-pcp.md`
PCP has 20 Plugin_Repo checks. Any ERROR = instant rejection.

**Detection:**
```bash
# Forbidden file types (compressed, PHAR, application binaries)
find <path> -name "*.zip" -o -name "*.gz" -o -name "*.tgz" -o -name "*.rar" -o -name "*.tar" -o -name "*.7z" -o -name "*.phar" -o -name "*.exe" -o -name "*.sh" -o -name "*.so" -o -name "*.a" -o -name "*.bin" -o -name "*.dmg" -o -name "*.pkg" -o -name "*.obj"

# VCS dirs
find <path> -name ".git" -o -name ".svn" -o -name ".hg" -o -name ".bzr" -type d

# AI instruction dirs (WARNING in PCP)
find <path> -name ".cursor" -o -name ".claude" -o -name ".aider" -o -name ".continue" -o -name ".windsurf" -o -name ".ai" -type d
find <path> -name ".github" -type d

# Unexpected .md files in root
ls <path>/*.md 2>/dev/null | grep -vi "README\|LICENSE\|CHANGELOG\|CONTRIBUTING\|SECURITY"

# Case-duplicate files (BADLY_NAMED)
find <path> -type f | sed 's|.*/||' | sort -f | uniq -id

# Plugin header validation
grep -n "Plugin Name:\|Version:\|License:\|Text Domain:\|Requires at least:\|Requires PHP:\|Tested up to:\|Update URI:\|Requires Plugins:" <path>/*.php | head -15

# Update URI (FORBIDDEN - severity 9)
grep -n "Update URI:" <path>/*.php

# readme.txt validation
grep -n "Stable tag:\|Tested up to:\|License:\|Tags:" <path>/readme.txt | head -5

# Stable tag must NOT be "trunk"
grep -i "Stable tag:\s*trunk" <path>/readme.txt

# Version match check
PLUGIN_VER=$(grep -oP "Version:\s*\K[0-9.]+" <path>/*.php | head -1)
README_VER=$(grep -oP "Stable tag:\s*\K[0-9.]+" <path>/readme.txt | head -1)
[ "$PLUGIN_VER" != "$README_VER" ] && echo "VERSION MISMATCH: plugin=$PLUGIN_VER readme=$README_VER"

# Tag count (max 5)
TAG_COUNT=$(grep -i "^Tags:" <path>/readme.txt | tr ',' '\n' | wc -l)
[ "$TAG_COUNT" -gt 5 ] && echo "TOO MANY TAGS: $TAG_COUNT (max 5)"

# Code obfuscation (severity 7)
grep -rn "Zend;\|ionCube\|sourceguardian\|function_exists.*sg_load\|\$__x=" <path> --include="*.php" | grep -v vendor

# Custom updater patterns (severity 9)
grep -rn "plugin-update-checker\|WP_GitHub_Updater\|WPGitHubUpdater\|PucFactory\|YahnisElsts" <path> --include="*.php"

# ALLOW_UNFILTERED_UPLOADS (severity 7)
grep -rn "ALLOW_UNFILTERED_UPLOADS" <path> --include="*.php"

# Localhost references
grep -rn "localhost\|127\.0\.0\.1" <path> --include="*.php" --include="*.js" | grep -v vendor | grep -v node_modules

# Trademark in plugin name (check against full list in knowledge file)
grep -n "Plugin Name:" <path>/*.php | head -1
```

**Fix:**
- Remove forbidden file types before submission
- Remove AI instruction dirs (`.claude/`, `.cursor/`, etc.)
- Add `.distignore` to exclude VCS/AI/dev dirs from SVN build
- Match stable tag to plugin version header
- Remove `Update URI:` header if present
- Keep tags ≤ 5 in readme.txt
- Remove localhost references
- Remove `ALLOW_UNFILTERED_UPLOADS` constant
- Remove obfuscation tools
- Remove custom updater code/hooks

#### B.2 — Uninstall cleanup

**Detection:**
```bash
# Check uninstall.php exists
test -f <path>/uninstall.php && echo "EXISTS" || echo "MISSING uninstall.php"

# Check guard
grep -n "WP_UNINSTALL_PLUGIN" <path>/uninstall.php 2>/dev/null

# Check it actually deletes plugin data
grep -n "delete_option\|delete_transient\|drop table\|delete_user_meta\|delete_post_meta" <path>/uninstall.php 2>/dev/null
```

**Fix:** Create `uninstall.php` with `WP_UNINSTALL_PLUGIN` guard that deletes
all options, transients, custom tables, and user meta created by plugin.

#### B.3 — Raw script/style tags

**Detection:**
```bash
# Raw <script> or <style> tags (should use wp_enqueue_*)
grep -rn "<script\b\|<style\b" <path> --include="*.php" | grep -v "wp_add_inline\|vendor/"
```

**Fix:** Replace with `wp_enqueue_script()` / `wp_enqueue_style()` or
`wp_add_inline_script()` / `wp_add_inline_style()`.

#### B.4 — PHP environment manipulation

**Detection:**
```bash
# Forbidden PHP calls
grep -rn "date_default_timezone_set\|ini_set\|error_reporting" <path> --include="*.php" | grep -v vendor
```

**Fix:** Remove. Use `wp_date()` / `current_time()` instead of timezone set.
Never modify `error_reporting` or `ini_set` in plugin code.

#### B.5 — Hardcoded secrets/tokens

**Detection:**
```bash
# API keys/tokens hardcoded in source
grep -rn "define.*\(TOKEN\|SECRET\|API_KEY\)" <path> --include="*.php" | grep -v vendor
grep -rn "'Bearer\s\+[a-zA-Z0-9]" <path> --include="*.php"
```

**Fix:** Move to `wp_options` with user input, or use environment-specific
credential mechanism. Rotate any key already shipped in public source.

#### B.6 — SSL verification disabled

**Detection:**
```bash
grep -rn "sslverify.*false" <path> --include="*.php"
```

**Fix:** Remove `'sslverify' => false`. WordPress defaults to `true`.

#### B.7 — Unfiltered uploads

**Detection:**
```bash
grep -rn "upload_mimes\|wp_check_filetype\|wp_handle_upload" <path> --include="*.php"
```

Verify uploads are restricted to safe MIME types. No arbitrary file uploads.

---

### SAFETY-FIRST FIX PROTOCOL (from wp-standards-checker)

When applying fixes (especially `--fix` mode), these rules prevent breaking:

1. **Never rename existing files** — breaks `include`/`require` paths
2. **Never globally change text domain** on shipped plugin — breaks `.po`/`.mo`
3. **Never rewrite complex functions** to satisfy complexity sniff — report only
4. **Prefix renames: search entire plugin** before renaming (hooks, calls, type-hints)
5. **SQL fix: verify query logic identical** before/after `$wpdb->prepare()` wrap
6. **Data structure: never change** option/meta array shape (breaks existing user data)
7. **Addon awareness:** never rename hooks/functions from parent plugin API
8. **Public APIs:** never rename methods used by external themes/plugins
9. **Mental dry-run:** trace data flow before/after every fix to verify identical behavior

**Rule:** If fix risks breaking functionality → flag as "Manual Review Required"
instead of auto-applying.

---

## WPPOOL-SPECIFIC PATTERNS

These patterns were found across multiple WPPOOL plugins and should be
checked first as they're the most likely to recur:

### The Appsero Checklist (appeared in ALL 9 closures)

1. **Version:** Must be latest stable (v2.0.2 was flagged everywhere)
2. **Install method:** Must be via Composer (`composer.json` must exist)
3. **Namespace/prefix:** Must use `class_exists()` guard or namespace prefixing
4. **Core include:** `Insights.php` uses `include ABSPATH` — must be `require_once` with guard
5. **icanhazip.com:** Appsero's `Insights.php` calls icanhazip — must be in readme
6. **Updater hooks:** `Updater.php` hooks `plugins_api` + `pre_set_site_transient_update_plugins` — must be disabled for WP.org build
7. **Tracking opt-in:** "No thanks" must send ZERO requests (Multi-Store Sync failed this)
8. **Appsero ToS URL:** Must be valid (not 404 — was 404 in 2 closures)
9. **sslverify => false:** Check if any `wp_remote_*` in SDK disables SSL

```bash
# Run the full Appsero check
echo "=== APPSERO AUDIT ==="
find <path> -path "*appsero*" -name "*.php" | head -20
grep -rn "version.*=" <path>/*appsero*/Client.php 2>/dev/null
grep -rn "include\s\+ABSPATH\|include(\s*ABSPATH" <path>/*appsero*/ --include="*.php"
grep -rn "pre_set_site_transient_update_plugins\|plugins_api" <path>/*appsero*/ --include="*.php"
grep -rn "icanhazip\|ipify" <path>/*appsero*/ --include="*.php"
grep -rn "sslverify.*false" <path>/*appsero*/ --include="*.php"
test -f <path>/composer.json && echo "composer.json: EXISTS" || echo "composer.json: MISSING"
```

### The Headway Checklist (appeared in 5/9 closures)

```bash
grep -rn "headwayapp\|headway" <path> --include="*.php" --include="*.js" --include="*.min.js"
```

If found: must be in readme `== External services ==` with ToS/Privacy links.
Loads unconditionally on admin pages = phones home without consent (flagged as
separate violation in EchoRewards).

### The IP-Fetch Checklist (appeared in 5/9 closures)

```bash
grep -rn "ipify\|icanhazip\|ipinfo\|ip-api\|whatismyip" <path> --include="*.php" --include="*.js" --include="*.min.js"
```

Must be in readme. IPify in frontend JS is especially problematic (fetches
visitor IP on every page load).

---

## REPORT FORMAT

```markdown
# Plugin Review Report: [Plugin Name] v[Version]

**Reviewed:** [Date]
**Reviewer:** AI (WPPOOL Plugin Reviewer Skill)
**Mode:** [--full/--quick/etc.]

## Summary

| Category | Blockers | Warnings | Info |
|----------|----------|----------|------|
| 1. Trialware (G5) | X | X | X |
| 2. External Services | X | X | X |
| 3. Security — I/O | X | X | X |
| 4. Security — Auth | X | X | X |
| 5. Libraries | X | X | X |
| 6. Build & Source | X | X | X |
| 7. Naming & i18n | X | X | X |
| 8. Plugin Behavior | X | X | X |
| 9. Assets | X | X | X |
| 10. A11y & UX | X | X | X |
| **TOTAL** | **X** | **X** | **X** |

**Verdict:** 🔴 NOT READY / 🟡 NEEDS WORK / 🟢 READY FOR SUBMISSION

## Findings

### 🔴 BLOCKER — [Category] — [Short Title]
**File:** `path/to/file.php:LINE`
**Detection:** `grep pattern that found it`
**Issue:** What's wrong
**Fix:** How to fix it (specific before → after code)
**Auto-fixable:** YES / NO (manual action needed)
**Guideline:** G5 / G6 / G8 / etc.

### 🟡 WARNING — [Category] — [Short Title]
...

### ℹ️ INFO — [Category] — [Short Title]
...

## Checklist for Re-submission

- [ ] Fix: [description]
- [ ] Fix: [description]
- [ ] Run Plugin Check (PCP) and verify zero ERRORs in "Plugin Repo" category
- [ ] Run PHPCS with WordPress standard
- [ ] Test with WP_DEBUG enabled on clean install
- [ ] Verify all external service URLs in readme are not 404
- [ ] Deactivate Pro plugin and test every free feature end-to-end
```

---

## RESPONDING TO WP.ORG CLOSURE EMAILS

When helping draft a response to a closure email:

1. **Address EVERY issue** listed in the email — WP.org reviewers check each one
2. **Don't claim fixes before verifying** — "CHANGESNOTMADE" response is worse than delay
3. **Be specific about what changed** — file names, line numbers, what was removed/added
4. **Request manual review** if automated scanner keeps flagging resolved issues
5. **Expect 2-4 rounds** — WP Dark Mode took 6 rounds; FlexMeeting took 2
6. **WPPOOL reply pattern that worked** (from successful re-listings):
   > We've addressed the reported issues and reviewed the plugin as a whole.
   > We've run Plugin Check, WPCS/PHPCS, security checks, and tested on a
   > clean WordPress installation with WP_DEBUG enabled.
7. **Never fix just the cited examples** — check for same pattern across entire plugin

---

## INTEGRATION WITH OTHER SKILLS

This skill is the **master gate**. It incorporates key rules from:

**From `wp-standards-checker`:**
- Class A-G blocker patterns from `knowledge/01_WP_ORG_BLOCKERS.md`
- PCP automated scanner patterns from `knowledge/02_PCP_LOGIC.md`
- Policy rules from `knowledge/13_POLICY_AND_PRIVACY.md`
- File/structure rules from `knowledge/11_FILE_AND_STRUCTURE_RULES.md`
- Safety-First Fix Protocol (never break logic to satisfy linter)

**From official WP.org sources (fetched live):**
- All 18 official plugin guidelines (developer.wordpress.org)
- 20 PCP Plugin_Repo check classes with exact regex patterns (GitHub source)
- Full trademark list (100+ terms) from Trademarks_Check.php
- File_Type_Check.php: 8 forbidden categories with exact extensions
- Plugin_Updater_Check.php: 8 updater detection patterns
- Stored in: `knowledge/official-guidelines-and-pcp.md`

**From `wp-plugin-security-review`:**
- 21 security audit categories with triage order
- CVSS v3.1 severity scoring adapted for WP context
- Three-tier privilege model (Low/Medium/High)

After this skill runs:
- If security findings need deeper analysis → invoke `wp-plugin-security-review`
- If PHPCS/WPCS auto-fix needed → invoke `wp-standards-checker --fix`
- For trialware edge cases → read `wp-standards-checker/knowledge/01_WP_ORG_BLOCKERS.md` Class G item 10

---

## SELF-UPDATING RULE

Real WP.org reviewer feedback overrides this skill. When a new closure email,
review comment, or confirmed false negative surfaces:

1. Update the relevant category in this file
2. Add the pattern to the WPPOOL-specific section if applicable
3. Update `knowledge/closure-case-studies.md` with the new case
4. Date-stamp the correction with source reference

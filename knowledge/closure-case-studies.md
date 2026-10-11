# Real WP.org Closure Case Studies (Aug-Sep 2026)

9 plugins from same org closed Aug 5-6, 2026. 3 re-listed; 6 still pending.
All identifying details anonymized per skill policy.

---

## Master Violation Frequency

| # | Violation | Count | Severity |
|---|-----------|-------|----------|
| 1 | Trialware (G5) — `is_pro`/license gates | 9/9 | BLOCKER |
| 2 | Outdated bundled analytics SDK (v2.0.2) | 9/9 | BLOCKER |
| 3 | PHP library conflict — SDK without namespace | 9/9 | BLOCKER |
| 4 | Undocumented external services | 9/9 | BLOCKER |
| 5 | Core file `include` instead of `require_once` | 8/9 | BLOCKER |
| 6 | Missing source for minified JS | 6/9 | BLOCKER |
| 7 | Changelog widget CDN load without disclosure | 5/9 | BLOCKER |
| 8 | IP-fetch service undisclosed | 5/9 | BLOCKER |
| 9 | Text domain mismatch (wrong slug) | 4/9 | BLOCKER |
| 10 | Missing ABSPATH guard | 4/9 | BLOCKER |
| 11 | Remote file loading (banned CDN deps) | 4/9 | BLOCKER |
| 12 | Sanitization gaps | 3/9 | BLOCKER |
| 13 | Generic/unprefixed names | 3/9 | BLOCKER |
| 14 | Hardcoded `wp-content` paths | 3/9 | BLOCKER |
| 15 | Variables as text domain params | 3/9 | BLOCKER |

---

## Trialware Patterns Found (THE #1 cause)

Every plugin had Guideline 5 as primary closure reason. Patterns:

### Pattern A: Direct `is_pro` gate
> "WooCommerce order review links and EDD review buttons/email integration
> implemented locally but intentionally gated by the `is_pro` premium-access check."

Found in: 4 plugins. Backend code exists in free, wrapped in `if ($this->is_pro)`.

### Pattern B: Disabled UI + active backend
> "Builder integrations intentionally lock most switch styles behind Ultimate
> even though the shared renderer accepts and outputs any requested style
> without an Ultimate check, with disabled controls and upgrade popups."

Found in: 2 plugins. UI shows disabled control, but backend code fully works.
WP.org checks whether the RENDERER works, not just the settings UI.

### Pattern C: Feature forcibly supplies empty/disabled values
> "Plugin includes custom-trigger, image/video replacement, and per-media
> exclusion functionality but forcibly supplies disabled or empty values for it."

Found in: 1 plugin (rounds 3-4). Subtle: code exists but returns empty arrays/
disabled values when Pro absent.

### Pattern D: Feature rendered only when Pro active
> "A reward-scheduling confirmation popup is implemented but rendered only
> when the premium add-on is active."

Found in: 1 plugin (round 2). Popup code exists in free, only shown if Pro active.

### Pattern E: Settings UI disables field + excludes from saving
> "Self-hosted server support is intentionally restricted: the settings UI
> disables the server-domain field and excludes it from saving, while Gutenberg
> frontend code still supports the API mode."

Found in: 1 plugin. Settings save handler skips the field, but Gutenberg
rendering code fully handles it.

### Pattern F: `isPro`-gated settings controls
> "Built-in order-data sync features are restricted to Pro users through
> `isPro`-gated settings controls."

Found in: 1 plugin. JavaScript/React component checks `isPro` before rendering
controls for features that have full PHP backend in free.

---

## Re-listing Timeline

| Plugin | Rounds | Days | Key to success |
|--------|--------|------|----------------|
| Plugin A | 5 | 15 | Fixed all in 2 rounds; requested manual review |
| Plugin B | 6 | 24 | Fixed trialware; new issues in round 2 fixed promptly |
| Plugin C | 12 | 40 | 3 "CHANGESNOTMADE" responses; trialware found in 3 different modules |

### Lesson: CHANGESNOTMADE kills velocity
Plugin C received this warning:
> "When not making adequate progress in your review, it will be delayed and
> eventually rejected. Once rejected under these circumstances, it will not
> be reviewed again."

### Lesson: Fix ALL instances, not just cited examples
WP.org explicitly says:
> "We are providing examples of code with issues, but it is possible that
> there are more occurrences of these issues. You need to check all your code."

### Lesson: New issues appear in fix submissions
Plugin B had new violations discovered in Round 2 that weren't in Round 1:
sanitization gaps, prefix issues, outdated Select2. Comprehensive review needed
BEFORE submitting fix, not just point-fixes on cited lines.

---

## Common SDK Issues (found in ALL 9)

### Analytics/Licensing SDK checklist
1. ✗ Version outdated (v2.0.2 → needs latest stable)
2. ✗ Manually bundled in `includes/` or `inc/` (no `composer.json`)
3. ✗ No `class_exists()` guard or namespace prefix
4. ✗ `Insights.php` uses `include ABSPATH` (not `require_once`)
5. ✗ IP-fetch service call inside SDK undisclosed in readme
6. ✗ Update-checker hooks (`plugins_api`, `pre_set_site_transient_update_plugins`) must be disabled
7. ✗ "No thanks" opt-out still sends tracking-skipped request
8. ✗ Terms/Conditions URL returns 404

### Changelog widget checklist
1. ✗ Loaded unconditionally from CDN on admin pages
2. ✗ Sends admin browser metadata (IP, user agent) without opt-in
3. ✗ Not in readme `== External services ==`

---

## Cross-Plugin Code Contamination

Evidence of copy-paste without cleanup:
- Plugin X used `"wp-dark-mode"` text domain for 11 elements (wrong plugin!)
- Plugin Y used `"wppool-turnstile"` text domain for 5 elements (from yet another plugin)
- Plugin Z used old slug `"stock-sync-with-google-sheet-for-woocommerce"` (pre-rename slug)

**Lesson:** After forking/cloning plugin code, run a text-domain sweep across entire codebase.

---

## Unique/Rare Violations Worth Remembering

### Unauthenticated plugin installation
> "An unauthenticated AJAX endpoint can install and activate WooCommerce
> because debug mode is enabled and its activation callback omits nonce
> and capability checks."

### Writing PHP to other plugins
> "file_put_contents($pro_plugin_file, $file_content, LOCK_EX) — modifies
> executable PHP source in the Pro plugin directory. Writing code is prohibited."

### Dynamic method dispatch from REST input
> "REST request controls dispatched method without explicit allowlist, allowing
> any existing matching `action_*` method to be invoked."
Pattern: `$this->{'action_' . $action}($request)`

### User-controlled option/transient names
> "Unvalidated REST $notice parameter interpolated into option name"
> "Public AJAX request controls cache key, allowing unbounded transient creation"

### Activation-time output
> "Wp_Dark_Install::wp_dark_activate() directly echoes an Ultimate-version
> incompatibility notice during activation, causing unexpected-output warnings."

### Defining core constants
> "define('WP_NETWORK_ADMIN', true) — forcing WP_NETWORK_ADMIN to true globally"

### Global hook hijacking
> "add_filter('clean_url', ...) — globally filters every URL containing #asyncload"

### Binary zip inside plugin
> "vendor/appsero.zip — binary zip file not allowed in plugins"

### Sourcemap referencing external URL
> "Pinia logo at https://pinia.vuejs.org/logo.svg" referenced in `.map` files — flagged.

---

## Reviewer Detection Language (for matching)

These phrases in a WP.org email indicate specific findings:

| Phrase | Meaning |
|--------|---------|
| "intentionally gated by" | Trialware |
| "implemented locally but" | Feature exists in free, locked |
| "forcibly supplies disabled or empty values" | Subtle trialware |
| "rendered only when the premium add-on is active" | Conditional rendering trialware |
| "despite the renderer accepts and outputs" | Backend works, UI locks |
| "no corresponding human-readable source" | Missing source for minified |
| "readme does not disclose" | Undocumented external service |
| "not documented in readme with Terms or Privacy" | Missing ToS/Privacy links |
| "CHANGESNOTMADE" | Fix attempt insufficient |
| "Once rejected... will not be reviewed again" | Final warning |
| "sends... without an opt-in control" | Phoning home violation |

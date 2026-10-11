# Official WP.org Guidelines + PCP Detection Patterns

Source: wordpress.org/plugins/wordpress-org/detailed-plugin-guidelines (last updated March 2026)
+ WordPress/plugin-check GitHub source (20 Plugin_Repo checks)

---

## The 18 Official Guidelines (Summary)

| # | Title | Key Rule |
|---|---|---|
| 1 | GPL Compatibility | All code/data/images must be GPL-compatible |
| 2 | Developer Responsibility | Verify license of every file before SVN upload |
| 3 | Stable Version on Directory | Directory is only official source; don't leave it outdated |
| 4 | Human-Readable Code | No obfuscation; ship source or link to public repo |
| 5 | No Trialware | No locked features requiring payment; premium code in separate add-on |
| 6 | SaaS Permitted | External services OK if substantial functionality + ToS in readme |
| 7 | No Tracking Without Consent | Explicit opt-in for any external contact; document data collection |
| 8 | No Executable Code from 3rd Parties | No remote JS/CSS (except fonts); no custom updaters; bundle locally |
| 9 | No Illegal/Dishonest Conduct | No SEO manipulation, fake reviews, sockpuppets, exploitation |
| 10 | No Embedded Links/Credits | "Powered by" must be opt-in, default hidden on frontend |
| 11 | Don't Hijack Admin | Notices must be dismissible, contextual, limited; no sitewide nags |
| 12 | No Readme Spam | Max 5 tags; no keyword stuffing; no competitor tags; no affiliate redirect |
| 13 | Use Default Libraries | Don't bundle jQuery/PHPMailer/SimplePie etc. that WP ships |
| 14 | Avoid Frequent Commits | SVN = release repo; only deploy-ready code |
| 15 | Increment Version Numbers | Trunk readme stable tag must match plugin version |
| 16 | Complete Plugin Required | Must submit working zip; no name reservations |
| 17 | Respect Trademarks | Can't start slug with trademarked term without ownership |
| 18 | Directory Maintenance Rights | WP.org can update guidelines, remove plugins, grant exceptions |

---

## PCP Plugin Check: 20 Plugin_Repo Checks (Instant Rejection on ERROR)

### 1. Code_Obfuscation_Check
Error code: `obfuscated_code_detected` (severity 7)

| Tool | Regex |
|---|---|
| Zend Guard | `/(\<\?php \@Zend;)\|(This file was encoded by)/` |
| Source Guardian | `/(sourceguardian\.com)\|(function_exists\('sg_load'\))\|(\$__x=)/` |
| ionCube | `/ionCube/` |

### 2. Direct_File_Access_Check
Every PHP file must have `if ( ! defined( 'ABSPATH' ) ) exit;`
`uninstall.php` must have `if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) exit;`

### 3. External_Admin_Menu_Links_Check
Admin menu links pointing to external sites flagged.

### 4. File_Type_Check (8 categories)

| Category | Forbidden | Severity |
|---|---|---|
| Compressed | `.zip`, `.gz`, `.tgz`, `.rar`, `.tar`, `.7z` | ERROR |
| PHAR | `.phar` | ERROR |
| VCS dirs | `.git`, `.svn`, `.hg`, `.bzr` | ERROR (prod) |
| Hidden files | Files starting with `.` (except `.distignore`, `.gitignore`) | ERROR |
| Application | `.a`, `.bin`, `.bpk`, `.deploy`, `.dist`, `.distz`, `.dmg`, `.dms`, `.dump`, `.elc`, `.exe`, `.iso`, `.lha`, `.lrf`, `.lzh`, `.o`, `.obj`, `.phar`, `.pkg`, `.sh`, `.so` | ERROR |
| Badly named | Spaces, special chars `!@#$%^&*()+=[]{};:"'<>,?/\|~`, case duplicates | ERROR |
| Core libraries | jQuery, jQuery UI, Backbone, Lodash, Moment, Underscore, Clipboard, CodeMirror, Thickbox, Twemoji, Iris, MediaElement, Plupload, getid3, pclzip, PasswordHash, PHPMailer, SimplePie + more | ERROR |
| AI dirs | `.cursor`, `.claude`, `.aider`, `.continue`, `.windsurf`, `.ai` | WARNING |
| GitHub dir | `.github` | WARNING |
| Unexpected MD | Any `.md` not README/LICENSE/CHANGELOG/CONTRIBUTING/SECURITY | WARNING |
| Missing composer.json | `vendor/` exists with `autoload.php` but no `composer.json` | WARNING |

### 5. Localhost_Check
References to `localhost` or `127.0.0.1` flagged.

### 6. Menu_Image_Icon_Check
Admin menu icon usage validation.

### 7. Minified_Files_Check
`.min.js`/`.min.css` without unminified source or public repo link.

### 8. No_Unfiltered_Uploads_Check
Error code: `allow_unfiltered_uploads_detected` (severity 7)
Pattern: searches for literal `ALLOW_UNFILTERED_UPLOADS` in PHP files.

### 9. Offloading_Files_Check
Delegates to PHPCS sniffs:
- `PluginCheck.CodeAnalysis.EnqueuedResourceOffloading`
- `PluginCheck.CodeAnalysis.Offloading`
Catches `wp_enqueue_script`/`wp_register_script` with external URLs.

### 10. Plugin_Content_Check
General plugin content validation.

### 11. Plugin_Header_Fields_Check
Required/validated fields:

| Field | Rule |
|---|---|
| Plugin Name | Must exist, 5+ alphanumeric chars, not placeholder |
| Description | Must exist, not placeholder text |
| Version | Must exist, match `[a-z0-9.-]+`, match Stable Tag |
| License | Must exist, GPL-2.0-or-later compatible, match readme |
| Text Domain | Must be `lowercase-with-hyphens`, match folder slug |
| Domain Path | If present, must start with `/`, point to existing dir |
| Plugin URI | Valid URL, not discouraged domain |
| Author URI | Valid URL, not discouraged domain |
| Network | If present, must be exactly `true` |
| Requires at least | Valid WP version like `6.4` |
| Requires PHP | Valid PHP version like `7.4` |
| Requires Plugins | Comma-separated WP.org slugs |
| Update URI | **FORBIDDEN** - instant rejection |

### 12. Plugin_Readme_Check
Required:
- `=== Plugin Name ===` header at top
- Stable tag: must NOT be `trunk`, must match Version header
- Tested up to: current WP major.minor (not patch like `6.7.1`)
- License: GPL-2.0+ SPDX, must match plugin header
- Contributors: comma-separated WP.org usernames
- Tags: maximum 5, no banned words
- Short Description: must exist, ≤150 chars, not placeholder
- Upgrade Notice: each version ≤300 chars
- No default placeholder text

### 13. Plugin_Review_PHPCS_Check
Runs PHPCS with WordPress standard rules.

### 14. Plugin_Uninstall_Check
`uninstall.php` must contain `WP_UNINSTALL_PLUGIN` guard.

### 15. Plugin_Updater_Check
Error code: `plugin_updater_detected` (severity 9)

| Group | Pattern |
|---|---|
| UpdateURI header | Non-wordpress.org/w.org URL or slug mismatch |
| Updater file | `/plugin-update-checker\.php$/` |
| Updater code (8 patterns) | `'plugin-update-checker'`, `WP_GitHub_Updater`, `WPGitHubUpdater`, `class [A-Z_]+_Plugin_Updater`, `updater\.\w+\.\w{2,5}`, `site_transient_update_plugins`, `YahnisElsts\\PluginUpdateChecker`, `PucFactory::buildUpdateChecker` |
| Update routine modification | `auto_update_plugin`, `pre_set_site_transient_update_\w+`, `_site_transient_update_\w+` |

### 16. Prefixing_Check
All global functions/classes/constants/options/hooks must use unique prefix ≥4 chars.
PHPCS Sniff: `WordPress.NamingConventions.PrefixAllGlobals`

### 17. Setting_Sanitization_Check
All `register_setting()` calls must have `sanitize_callback` in 3rd arg array.

### 18. Trademarks_Check
Error code: `trademarked_term`

**Forbidden prefixes (term ending with `-`):**
google-, googlebot-, googles-, adsense-, adwords-, ganalytics-, gtmetrix-,
facebook, fbook, fb-, instagram, insta-, ig-, whatsapp, wa-,
twitter-, tweet, tiktok-, youtube-, pinterest-, twitch-, skype-,
microsoft-, windows-, bing-, apple-, applenews-, applepay-, macintosh-,
macos-, ios-, firefox-, opera-, amazon-, aws-, azon-, adobe-,
android-, akismet-, advanced-custom-fields-, bbpress-, buddypress-,
chatgpt-, chat-gpt-, cloudflare-, contact-form-7-, cpanel-, disqus-,
divi-, dropbox-, easy-digital-downloads-, elementor-, envato-, fedex-,
feedburner, fontawesome-, font-awesome-, github-, givewp-, gravity-form-,
gravity-forms-, gravityforms-, hubspot-, jetpack-, mailchimp-,
ninja-forms-, onlyfans-, only-fans-, paddle-, paypal-, stripe-,
trustpilot, ups-, usps-, watson, wp-mail-smtp-, yandex-, yahoo-, yoast

**WordPress/WooCommerce variants (substring match):**
wordpress, wordpess, wpress, wp, wc, woocom-, woocommerce, wocommerce,
wocomerce, woo-commerce, woo-, wo-, plugin, gutenberg, guten-, gberg

**WooCommerce for-use exception:**
`-for-woocommerce`, `-with-woocommerce`, `-using-woocommerce`, `-and-woocommerce`

**Portmanteau:** `woo` at start of slug (blocks "woopress" etc.)

### 19. WP_Functions_Compatibility_Check
Checks WordPress function compatibility with declared minimum version.

### 20. Write_File_Check
Detects file writes to plugin/theme/core directories.

---

## Detection Patterns to Add to Skill

### New patterns not in current skill:

```bash
# Localhost references (PCP check #5)
grep -rn "localhost\|127\.0\.0\.1" <path> --include="*.php" --include="*.js" | grep -v vendor | grep -v node_modules

# ALLOW_UNFILTERED_UPLOADS (PCP check #8)
grep -rn "ALLOW_UNFILTERED_UPLOADS" <path> --include="*.php"

# Plugin updater code patterns (PCP check #15)
grep -rn "plugin-update-checker\|WP_GitHub_Updater\|WPGitHubUpdater\|PucFactory\|YahnisElsts" <path> --include="*.php"

# Readme tag count (PCP check #12)
grep -i "^Tags:" <path>/readme.txt | tr ',' '\n' | wc -l

# Short description length
grep -A1 "== Description ==" <path>/readme.txt | head -2

# Stable tag = trunk (forbidden)
grep -i "Stable tag:\s*trunk" <path>/readme.txt

# External admin menu links (PCP check #3)
grep -rn "add_menu_page\|add_submenu_page" <path> --include="*.php" | grep "http"

# Trademark in plugin name (PCP check #18)
grep -n "Plugin Name:" <path>/*.php | head -1

# Case-duplicate files
find <path> -type f | sed 's|.*/||' | sort -f | uniq -id
```

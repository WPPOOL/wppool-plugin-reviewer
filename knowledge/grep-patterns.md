# Quick-Reference Grep Patterns

Copy-paste grep commands for each audit category.
Replace `<PATH>` with plugin root directory.

---

## 1. TRIALWARE (G5) — Run First

```bash
# Pro/license gates in PHP
grep -rni "is_pro\b\|->is_pro\|is_premium\b\|license_status\|license_key\|can_use_premium\|is_ultimate\|isPro\|proActive" <PATH> --include="*.php" | grep -v "vendor/"

# Class/function existence checks as gates
grep -rn "class_exists.*Pro\|defined.*PRO_VERSION\|function_exists.*pro" <PATH> --include="*.php" | grep -v "vendor/"

# Tier-naming (review optics)
grep -rni "\b\(free\|pro\|premium\|lite\|trial\|license\)_" <PATH> --include="*.php" | grep -v "vendor/" | grep -v "//\|/\*"

# Disabled UI controls
grep -rn "'disabled'\s*=>" <PATH> --include="*.php"

# Filter hooks with locked defaults
grep -rn "apply_filters.*\(.*null\|apply_filters.*\(.*false\|apply_filters.*\(.*\[\]" <PATH> --include="*.php" | grep -v vendor

# JS-side pro gates
grep -rn "isPro\|isProActive\|is_pro\|proActive\|premiumActive" <PATH> --include="*.js" --include="*.jsx" --include="*.tsx" | grep -v node_modules
```

## 2. EXTERNAL SERVICES (G6/G7)

```bash
# PHP remote calls
grep -rn "wp_remote_get\|wp_remote_post\|wp_remote_head\|wp_remote_request" <PATH> --include="*.php"
grep -rn "file_get_contents\s*(\s*['\"]http" <PATH> --include="*.php"

# JS remote calls (source)
grep -rn "fetch(\|XMLHttpRequest\|\.ajax(" <PATH> --include="*.js" --include="*.jsx" | grep -v node_modules

# JS remote URLs (minified)
grep -on "https\?://[^\"' )\]\}]*" <PATH> --include="*.min.js" | grep -v "wordpress.org\|w3.org\|schema.org"

# CDN-loaded scripts
grep -rn "wp_enqueue_script.*https\?://\|wp_register_script.*https\?://" <PATH> --include="*.php"

# WPPOOL common: Headway
grep -rn "headwayapp\|headway" <PATH> --include="*.php" --include="*.js" --include="*.min.js"

# WPPOOL common: IP fetch
grep -rn "ipify\|icanhazip\|ipinfo\|ip-api" <PATH> --include="*.php" --include="*.js"

# Readme disclosure check
grep -i "external services\|third.party\|3rd party" <PATH>/readme.txt 2>/dev/null

# Tracking opt-in
grep -rn "allow_tracking\|optin\|opt_in\|tracking_skipped" <PATH> --include="*.php" | grep -v vendor
```

## 3. SECURITY — INPUT/OUTPUT

```bash
# Raw superglobals
grep -rn "\$_POST\b\|\$_GET\b\|\$_REQUEST\b" <PATH> --include="*.php" | grep -v "vendor/"

# Bulk unslash (wrong)
grep -rn "wp_unslash\s*(\s*\$_POST\s*)" <PATH> --include="*.php"

# filter_input without FILTER
grep -rn "filter_input\s*(" <PATH> --include="*.php" | grep -v "FILTER_"

# Bare echo without escaping
grep -rn "echo \$\|echo \"\$" <PATH> --include="*.php" | grep -v "esc_\|wp_kses\|vendor/"

# json_encode (should be wp_json_encode)
grep -rn "\bjson_encode\b" <PATH> --include="*.php" | grep -v "vendor/"

# register_setting missing sanitize_callback
grep -rn "register_setting" <PATH> --include="*.php"

# SQL without prepare
grep -rn "\$wpdb->query\|\$wpdb->get_results\|\$wpdb->get_var\|\$wpdb->get_row" <PATH> --include="*.php" | grep -v "prepare\|vendor/"

# Nonce checks
grep -rn "wp_ajax_" <PATH> --include="*.php" | grep -v vendor

# REST routes
grep -rn "register_rest_route" <PATH> --include="*.php"

# admin_init
grep -rn "add_action.*admin_init" <PATH> --include="*.php"

# Option/transient name from input (CRITICAL)
grep -rn "update_option\|set_transient\|delete_option" <PATH> --include="*.php" | grep "\$_\|->get_param\|filter_input"

# Dynamic method dispatch
grep -rn "\$this->{\$\|call_user_func.*\$_" <PATH> --include="*.php"
```

## 4. ABSPATH GUARD

```bash
# Find PHP files missing guard (bash)
for f in $(find <PATH> -name "*.php" -not -path "*/vendor/*" -not -path "*/node_modules/*"); do
  head -20 "$f" | grep -q "defined.*ABSPATH\|defined.*WPINC" || echo "MISSING: $f"
done
```

## 5. LIBRARIES & SDK

```bash
# Appsero full audit
find <PATH> -path "*appsero*" -name "*.php" | head -20
grep -rn "version.*=" <PATH>/*appsero*/Client.php 2>/dev/null
grep -rn "include\s\+ABSPATH" <PATH>/*appsero*/ --include="*.php" 2>/dev/null
grep -rn "pre_set_site_transient_update_plugins\|plugins_api" <PATH>/*appsero*/ --include="*.php" 2>/dev/null
grep -rn "icanhazip\|ipify" <PATH>/*appsero*/ --include="*.php" 2>/dev/null
grep -rn "sslverify.*false" <PATH>/*appsero*/ --include="*.php" 2>/dev/null
test -f <PATH>/composer.json && echo "composer.json: EXISTS" || echo "composer.json: MISSING"

# Bundled jQuery
find <PATH> -name "jquery*.js" -not -path "*/node_modules/*" | grep -v "\.min\.js\.map"

# Custom updater hooks
grep -rn "pre_set_site_transient_update_plugins\|plugins_api" <PATH> --include="*.php"

# Outdated libraries (check version strings)
find <PATH> -path "*/vendor/*" -o -path "*/lib/*" -o -path "*/includes/*" | xargs grep -l "version" 2>/dev/null | head -20
```

## 6. BUILD & SOURCE

```bash
# Minified without source
for f in $(find <PATH> -name "*.min.js" -not -path "*/node_modules/*" -not -path "*/vendor/*"); do
  base="${f%.min.js}.js"; test -f "$base" || echo "NO SOURCE: $f"
done

# Webpack bundles without source
find <PATH> -name "*.js" -not -name "*.min.js" -not -path "*/node_modules/*" | xargs grep -l "webpackBootstrap\|__webpack_require__" 2>/dev/null

# HEREDOC (banned)
grep -rn "<<<" <PATH> --include="*.php" | grep -v vendor

# Binary/forbidden files
find <PATH> -name "*.zip" -o -name "*.tar.gz" -o -name "*.phar" -o -name "*.exe"

# Filenames with spaces
find <PATH> -name "* *" -type f

# Remote references in sourcemaps
grep -rn "sourceMappingURL.*http\|sourceURL.*http" <PATH> --include="*.js" --include="*.map"

# Obfuscation
grep -rn "base64_decode\|eval\s*(" <PATH> --include="*.php" | grep -v vendor
```

## 7. NAMING & I18N

```bash
# Get plugin slug
SLUG=$(basename <PATH>)

# Find all text domains used
grep -roh "['\"][a-z0-9-]*['\"]" <PATH> --include="*.php" | sort -u | head -30

# Unprefixed AJAX actions
grep -rn "wp_ajax_\|wp_ajax_nopriv_" <PATH> --include="*.php" | grep -v vendor

# Variables as text domain
grep -rn "__(\$\|_e(\$\|esc_html__(\$" <PATH> --include="*.php"

# Trademark in plugin name
grep -n "Plugin Name:" <PATH>/*.php 2>/dev/null | head -1
```

## 8. PLUGIN BEHAVIOR

```bash
# Changing active plugins
grep -rn "deactivate_plugins\|activate_plugin" <PATH> --include="*.php"

# Defining core constants
grep -rn "define.*WP_NETWORK_ADMIN\|define.*WP_USER_ADMIN\|define.*WP_DEBUG" <PATH> --include="*.php" | grep -v vendor

# Global hook hijacking
grep -rn "add_filter.*clean_url\|add_filter.*script_loader_tag" <PATH> --include="*.php" | grep -v vendor

# Hardcoded paths
grep -rn "ABSPATH.*wp-content\|wp-content/plugins\|home_url.*wp-json" <PATH> --include="*.php" | grep -v vendor

# Activation output
grep -rn "register_activation_hook" <PATH> --include="*.php"

# Writing files
grep -rn "file_put_contents\|fwrite" <PATH> --include="*.php" | grep -v vendor | grep -v "wp_upload_dir"

# Unclosed ob_start
echo "ob_start: $(grep -rn "ob_start" <PATH> --include="*.php" | grep -v vendor | wc -l)"
echo "ob_close: $(grep -rn "ob_end_clean\|ob_get_clean\|ob_end_flush" <PATH> --include="*.php" | grep -v vendor | wc -l)"

# 5-star review manipulation
grep -rn "reviews/?filter=5\|filter=5" <PATH> --include="*.php" --include="*.js"

# Powered-by links
grep -rni "powered by\|powered-by" <PATH> --include="*.php"

# Requires Plugins header
grep -n "Requires Plugins:" <PATH>/*.php 2>/dev/null | head -1
grep -rn "class_exists.*WooCommerce\|is_plugin_active.*woocommerce" <PATH> --include="*.php" | head -3
```

## 9. PRIVILEGE ESCALATION

```bash
# Auth cookie / session manipulation
grep -rn "wp_set_auth_cookie\|wp_set_current_user\|wp_signon" <PATH> --include="*.php" | grep -v vendor

# Role/cap manipulation
grep -rn "set_role\|add_role\|add_cap\|wp_insert_user\|wp_update_user" <PATH> --include="*.php" | grep -v vendor

# Open redirects
grep -rn "wp_redirect\s*(" <PATH> --include="*.php" | grep -v "wp_safe_redirect\|vendor"
```

#!/bin/bash
# WP.org Compliance Checker - Grep-based checks that PHPCS doesn't catch
# Used by GitHub Actions workflow for PR review
#
# Usage: ./check-wporg-compliance.sh /path/to/plugin
# Output: JSON findings to stdout, human-readable to stderr

set -euo pipefail

PLUGIN_DIR="${1:-.}"
FINDINGS_FILE=$(mktemp)
EXIT_CODE=0

# Colors for stderr output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# Track counts
BLOCKERS=0
WARNINGS=0
INFO_COUNT=0

# ─── Helper Functions ───

# Escape a value for use inside a JSON string.
json_escape() {
    printf '%s' "$1" | tr -d '\r' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | tr -d '\000-\010\013\014\016-\037' | tr '\n' ' '
}

add_finding() {
    local severity="$1"  # BLOCKER, WARNING, INFO
    local category="$2"
    local file="$3"
    local line="$4"
    local message="$5"
    local fix="${6:-}"

    echo "{\"severity\":\"$severity\",\"category\":\"$category\",\"file\":\"$(json_escape "$file")\",\"line\":${line:-0},\"message\":\"$(json_escape "$message")\",\"fix\":\"$(json_escape "$fix")\"}" >> "$FINDINGS_FILE"

    case "$severity" in
        BLOCKER) ((BLOCKERS++)) || true; echo -e "${RED}[BLOCKER]${NC} $category | $file:$line | $message" >&2 ;;
        WARNING) ((WARNINGS++)) || true; echo -e "${YELLOW}[WARNING]${NC} $category | $file:$line | $message" >&2 ;;
        INFO)    ((INFO_COUNT++)) || true; echo -e "${GREEN}[INFO]${NC} $category | $file:$line | $message" >&2 ;;
    esac
}

# Paths that never ship to WP.org: dependency folders, VCS/CI folders and
# everything listed in the plugin's .distignore (tests/, docs/, build tooling...).
DISTIGNORE_PATTERNS=()
if [ -f "$PLUGIN_DIR/.distignore" ]; then
    while IFS= read -r pattern || [ -n "$pattern" ]; do
        pattern="${pattern%$'\r'}"
        pattern="${pattern#"${pattern%%[![:space:]]*}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"
        [[ -z "$pattern" || "$pattern" == \#* ]] && continue
        DISTIGNORE_PATTERNS+=("$pattern")
    done < "$PLUGIN_DIR/.distignore"
fi

skip_path() {
    local rel="${1#"$PLUGIN_DIR"/}"
    rel="${rel#./}"
    case "/$rel" in
        */vendor/*|*/node_modules/*|*/.git/*|*/.github/*) return 0 ;;
    esac
    distignored "$rel"
}

# True when a path (relative to the plugin root) is excluded by .distignore.
distignored() {
    local rel="$1"
    local pattern glob
    for pattern in "${DISTIGNORE_PATTERNS[@]+"${DISTIGNORE_PATTERNS[@]}"}"; do
        glob="${pattern#/}"
        glob="${glob%/}"
        glob="${glob//\*\*/*}"
        if [[ "$pattern" == /* ]]; then
            # Anchored to the plugin root: the path itself or anything below it.
            [[ "$rel" == $glob || "$rel" == $glob/* ]] && return 0
        else
            # Unanchored: may match at any depth.
            [[ "$rel" == $glob || "$rel" == $glob/* || "$rel" == */$glob || "$rel" == */$glob/* ]] && return 0
        fi
    done
    return 1
}

# ─── CHECK 1: Trialware / Guideline 5 ───

echo -e "\n=== Category 1: Trialware (Guideline 5) ===" >&2

# is_pro / is_premium gates in PHP (not in comments, not in wp_localize_script)
while IFS=: read -r file line content; do
    # Skip vendor/node_modules
    skip_path "$file" && continue
    # Skip comment lines
    trimmed=$(echo "$content" | sed 's/^[ \t]*//')
    [[ "$trimmed" == //* || "$trimmed" == \** || "$trimmed" == \#* ]] && continue
    # Skip wp_localize_script lines (allowed use)
    [[ "$content" == *wp_localize_script* ]] && continue
    # Skip class property definitions
    [[ "$content" == *"private "* || "$content" == *"protected "* || "$content" == *"public "* ]] && [[ "$content" == *'$is_pro'* || "$content" == *'$is_premium'* || "$content" == *'$is_ultimate'* ]] && [[ "$content" != *"if"* && "$content" != *"return"* ]] && continue

    # Flag if used in conditional (if/ternary/return)
    if echo "$content" | grep -qE '(if|return|&&|\|\||[\?:])\s*.*\b(is_pro|is_premium|is_ultimate|license_status|can_use_premium)\b'; then
        add_finding "BLOCKER" "G5-Trialware" "$file" "$line" "License check gates functionality: $(echo "$content" | head -c 120)" "Remove gate; use apply_filters() with real default"
    fi
done < <(grep -rnE '\b(is_pro|is_premium|is_ultimate|license_status|can_use_premium)\b' "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# apply_filters with bad defaults (null, false, [], '' used as lock)
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    if echo "$content" | grep -qE "apply_filters\s*\(\s*['\"][^'\"]+['\"]\s*,\s*(null|false|\[\]|''|\"\")\s*[,)]"; then
        add_finding "WARNING" "G5-Trialware" "$file" "$line" "apply_filters() with potentially locking default (null/false/[]/empty): $(echo "$content" | head -c 120)" "Use real working default value"
    fi
done < <(grep -rnE "apply_filters\s*\(" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)


# ─── CHECK 2: External Services ───

echo -e "\n=== Category 2: External Services (G6/G7/G8) ===" >&2

# Count external HTTP calls
EXT_CALLS=$(grep -rn "wp_remote_get\|wp_remote_post\|wp_remote_request\|wp_remote_head\|file_get_contents\s*(\s*['\"]http" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ | wc -l || echo "0")

# Check if readme has External services section
HAS_EXT_SECTION=false
if [ -f "$PLUGIN_DIR/readme.txt" ]; then
    grep -qi "external services\|third.party services\|external api" "$PLUGIN_DIR/readme.txt" && HAS_EXT_SECTION=true
fi

if [ "$EXT_CALLS" -gt 0 ] && [ "$HAS_EXT_SECTION" = false ]; then
    add_finding "BLOCKER" "G6-External-Services" "readme.txt" "0" "Plugin makes $EXT_CALLS external HTTP calls but readme.txt has no == External services == section" "Add == External services == with URL, purpose, data sent, ToS + privacy links"
fi

# Remote JS/CSS loading
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    if echo "$content" | grep -qE "(wp_enqueue_script|wp_enqueue_style|wp_register_script|wp_register_style).*https?://"; then
        add_finding "BLOCKER" "G8-Remote-Resources" "$file" "$line" "Remote JS/CSS loading detected (must bundle locally): $(echo "$content" | head -c 120)" "Download and bundle file locally"
    fi
done < <(grep -rnE "(wp_enqueue_script|wp_enqueue_style|wp_register_script|wp_register_style)" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep "http" | grep -v vendor/ | grep -v node_modules/ || true)

# Tracking without opt-in check
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    add_finding "WARNING" "G7-Tracking" "$file" "$line" "Telemetry/tracking call found; verify opt-in consent: $(echo "$content" | head -c 120)" "Ensure tracking is opt-in, off by default"
done < <(grep -rnE "(send_tracking|track_usage|telemetry|analytics.*send|usage_data)" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)


# ─── CHECK 3: Security - Input/Output ───

echo -e "\n=== Category 3: Security I/O ===" >&2

# Raw $_POST/$_GET/$_REQUEST without sanitization
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    trimmed=$(echo "$content" | sed 's/^[ \t]*//')
    [[ "$trimmed" == //* || "$trimmed" == \** ]] && continue
    # Skip if already wrapped in sanitize/wp_unslash
    echo "$content" | grep -qE "(sanitize_|wp_unslash|absint|intval|esc_)" && continue
    # Existence checks (isset/empty) and strict comparisons only read the value.
    remaining=$(echo "$content" | sed -E \
        -e 's/(isset|empty)\s*\(\s*\$_(POST|GET|REQUEST|SERVER)\[[^]]*\]\s*\)//g' \
        -e 's/\$_(POST|GET|REQUEST|SERVER)\[[^]]*\]\s*[!=]==//g' \
        -e 's/[!=]==\s*\$_(POST|GET|REQUEST|SERVER)\[[^]]*\]//g')
    echo "$remaining" | grep -qE '\$_(POST|GET|REQUEST|SERVER)\[' || continue
    add_finding "BLOCKER" "Security-Input" "$file" "$line" "Unsanitized superglobal access: $(echo "$content" | head -c 100)" "Use sanitize_text_field(wp_unslash(\$_POST['key']))"
done < <(grep -rnIE '\$_(POST|GET|REQUEST|SERVER)\[' "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# Missing nonce verification on AJAX handlers
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    # Extract function name from add_action
    func_name=$(echo "$content" | grep -oP "(?:array\s*\(\s*\\\$this\s*,\s*['\"])([^'\"]+)" | head -1 || echo "")
    if [ -n "$func_name" ]; then
        # Check if function has nonce verification
        has_nonce=$(grep -c "check_ajax_referer\|wp_verify_nonce\|verify_nonce" "$file" 2>/dev/null || true)
        if [ "${has_nonce:-0}" -eq 0 ]; then
            add_finding "BLOCKER" "Security-Nonce" "$file" "$line" "AJAX handler without nonce verification: $(echo "$content" | head -c 100)" "Add check_ajax_referer('action_name', 'nonce')"
        fi
    fi
done < <(grep -rnE "add_action\s*\(\s*['\"]wp_ajax_(nopriv_)?" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# REST routes without permission_callback
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    # Look at the whole call (up to the next register_rest_route or 40 lines).
    call=$(awk -v s="$line" 'NR > s + 40 { exit } NR > s && /register_rest_route[[:space:]]*\(/ { exit } NR >= s { print }' "$file" 2>/dev/null || true)
    has_perm=$(echo "$call" | grep -c "permission_callback" || true)
    # Route args passed in a variable (e.g. a route table looped over): accept when
    # the same file defines permission_callback for those args.
    if [ "${has_perm:-0}" -eq 0 ] && ! echo "$call" | grep -qE "['\"]callback['\"]"; then
        has_perm=$(grep -c "permission_callback" "$file" 2>/dev/null || true)
    fi
    if [ "${has_perm:-0}" -eq 0 ]; then
        add_finding "BLOCKER" "Security-REST" "$file" "$line" "REST route without permission_callback: $(echo "$content" | head -c 100)" "Add 'permission_callback' => function() { return current_user_can('manage_options'); }"
    fi
done < <(grep -rnIE '(^|[^A-Za-z0-9_$>:])register_rest_route[[:space:]]*\(' "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# Unescaped output
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    trimmed=$(echo "$content" | sed 's/^[ \t]*//')
    [[ "$trimmed" == //* || "$trimmed" == \** ]] && continue
    # Skip if already escaped
    echo "$content" | grep -qE "(esc_html|esc_attr|esc_url|esc_js|wp_kses|sanitize_)" && continue
    add_finding "WARNING" "Security-Escaping" "$file" "$line" "Possible unescaped output: $(echo "$content" | head -c 100)" "Use esc_html(), esc_attr(), esc_url(), or wp_kses()"
done < <(grep -rnE '^\s*echo\s+\$' "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# Direct SQL without prepare
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    # The statement may continue on the next lines.
    statement=$(awk -v s="$line" 'NR >= s && NR <= s + 6 { print; if (/;/) exit } NR > s + 6 { exit }' "$file" 2>/dev/null || true)
    echo "$statement" | grep -qE -- "->prepare\s*\(" && continue
    # Query passed in a variable that was built with prepare() just above.
    query_var=$(echo "$content" | grep -oE -- '->(query|get_results|get_row|get_var|get_col)\s*\(\s*\$[A-Za-z_][A-Za-z0-9_]*' | grep -oE '\$[A-Za-z_][A-Za-z0-9_]*$' | head -1 || true)
    if [ -n "$query_var" ] && sed -n "$(( line > 40 ? line - 40 : 1 )),${line}p" "$file" 2>/dev/null | grep -qF "${query_var} = \$wpdb->prepare("; then
        continue
    fi
    if [ -n "$query_var" ] && sed -n "$(( line > 40 ? line - 40 : 1 )),${line}p" "$file" 2>/dev/null | grep -qF "${query_var} = \$this->wpdb->prepare("; then
        continue
    fi
    # Fully static SQL: the only interpolation is the table prefix.
    dynamic=$(echo "$statement" | sed -E -e 's/^.*->(query|get_results|get_row|get_var|get_col)\s*\(//' -e 's/\{?\$(this->)?wpdb->[A-Za-z_]+\}?//g')
    echo "$dynamic" | grep -qE '\$[A-Za-z_]' || continue
    add_finding "BLOCKER" "Security-SQL" "$file" "$line" "Direct DB query possibly without \$wpdb->prepare(): $(echo "$content" | head -c 100)" "Use \$wpdb->prepare() for all queries with variables"
done < <(grep -rnE '\$wpdb->(query|get_results|get_row|get_var|get_col)\s*\(' "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ | grep '\$' || true)

# register_setting without sanitize_callback
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    has_sanitize=$(sed -n "$((line)),$((line+5))p" "$file" 2>/dev/null | grep -c "sanitize_callback" || true)
    if [ "${has_sanitize:-0}" -eq 0 ]; then
        add_finding "BLOCKER" "Security-Settings" "$file" "$line" "register_setting() without sanitize_callback: $(echo "$content" | head -c 100)" "Add 'sanitize_callback' in third argument array"
    fi
done < <(grep -rn "register_setting" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)


# ─── CHECK 4: ABSPATH Guard ───

echo -e "\n=== Category 4: ABSPATH Guard ===" >&2

while IFS= read -r file; do
    skip_path "$file" && continue
    has_guard=$(head -20 "$file" | grep -cE "defined\s*\(\s*['\"]ABSPATH['\"]" || true)
    if [ "${has_guard:-0}" -eq 0 ]; then
        # Code lines, ignoring the open/close tags, comments and blank lines.
        first_code=$(awk '{ gsub(/<\?php|\?>/, "") } /^[[:space:]]*(\/\/|#|\/?\*)/ || /^[[:space:]]*$/ { next } { print; exit }' "$file" 2>/dev/null || true)
        # Empty / "Silence is golden" files and data files (<?php return [...]) are safe.
        [ -z "$first_code" ] && continue
        echo "$first_code" | grep -qE '^\s*return[[:space:](\[]' && continue
        basename_file=$(basename "$file")
        if [ "$basename_file" = "uninstall.php" ]; then
            has_uninstall_guard=$(head -20 "$file" | grep -cE "defined\s*\(\s*['\"]WP_UNINSTALL_PLUGIN['\"]" || true)
            if [ "${has_uninstall_guard:-0}" -eq 0 ]; then
                add_finding "BLOCKER" "Direct-Access" "$file" "1" "uninstall.php missing WP_UNINSTALL_PLUGIN guard" "Add: if ( ! defined( 'WP_UNINSTALL_PLUGIN' ) ) exit;"
            fi
        else
            add_finding "BLOCKER" "Direct-Access" "$file" "1" "PHP file missing ABSPATH guard" "Add: if ( ! defined( 'ABSPATH' ) ) exit;"
        fi
    fi
done < <(find "$PLUGIN_DIR" -name "*.php" -not -path "*/vendor/*" -not -path "*/node_modules/*" 2>/dev/null || true)


# ─── CHECK 5: Plugin Updater ───

echo -e "\n=== Category 5: Plugin Updater ===" >&2

while IFS=: read -r file line content; do
    skip_path "$file" && continue
    add_finding "BLOCKER" "Plugin-Updater" "$file" "$line" "Custom plugin updater detected (forbidden by G8): $(echo "$content" | head -c 100)" "Remove custom updater; use WP.org update system only"
done < <(grep -rnE "(plugin-update-checker|WP_GitHub_Updater|WPGitHubUpdater|PucFactory|YahnisElsts|pre_set_site_transient_update_plugins|site_transient_update_plugins|add_filter\s*\(\s*['\"]plugins_api['\"])" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)


# ─── CHECK 6: Forbidden Files ───

echo -e "\n=== Category 6: Forbidden Files ===" >&2

# Compressed files
while IFS= read -r file; do
    skip_path "$file" && continue
    add_finding "BLOCKER" "Forbidden-File" "$file" "0" "Compressed/archive file in plugin (remove before submission)" "Delete file; use composer/npm for dependencies"
done < <(find "$PLUGIN_DIR" -type f \( -name "*.zip" -o -name "*.gz" -o -name "*.tgz" -o -name "*.rar" -o -name "*.tar" -o -name "*.7z" -o -name "*.phar" \) -not -path "*/node_modules/*" 2>/dev/null || true)

# Executable files
while IFS= read -r file; do
    skip_path "$file" && continue
    add_finding "BLOCKER" "Forbidden-File" "$file" "0" "Executable/binary file in plugin" "Remove file"
done < <(find "$PLUGIN_DIR" -type f \( -name "*.exe" -o -name "*.sh" -o -name "*.bin" -o -name "*.so" -o -name "*.dll" \) -not -path "*/node_modules/*" -not -path "*/.github/*" 2>/dev/null || true)

# AI/VCS directories
while IFS= read -r dir; do
    skip_path "$dir/" && continue
    add_finding "WARNING" "Forbidden-Dir" "$dir" "0" "AI/IDE config directory should not ship to WP.org" "Add to .distignore"
done < <(find "$PLUGIN_DIR" -maxdepth 2 -type d \( -name ".cursor" -o -name ".claude" -o -name ".aider" -o -name ".continue" -o -name ".windsurf" -o -name ".ai" -o -name ".vscode" -o -name ".idea" \) 2>/dev/null || true)

# Files with spaces in name
while IFS= read -r file; do
    skip_path "$file" && continue
    basename_file=$(basename "$file")
    if echo "$basename_file" | grep -q " "; then
        add_finding "BLOCKER" "Forbidden-File" "$file" "0" "Filename contains spaces: $basename_file" "Rename file; remove spaces"
    fi
done < <(find "$PLUGIN_DIR" -type f -name "* *" -not -path "*/node_modules/*" -not -path "*/vendor/*" 2>/dev/null || true)


# ─── CHECK 7: Readme Validation ───

echo -e "\n=== Category 7: Readme ===" >&2

if [ -f "$PLUGIN_DIR/readme.txt" ]; then
    # Stable tag = trunk
    if grep -qi "Stable tag:\s*trunk" "$PLUGIN_DIR/readme.txt"; then
        add_finding "BLOCKER" "Readme" "readme.txt" "0" "Stable tag set to 'trunk' (must be specific version)" "Set Stable tag to match plugin Version header"
    fi

    # More than 5 tags
    TAG_COUNT=$(grep -i "^Tags:" "$PLUGIN_DIR/readme.txt" | head -1 | tr ',' '\n' | wc -l || echo "0")
    if [ "$TAG_COUNT" -gt 5 ]; then
        add_finding "WARNING" "Readme" "readme.txt" "0" "Too many tags ($TAG_COUNT); maximum 5 allowed" "Reduce to 5 most relevant tags"
    fi

    # Missing tested up to
    if ! grep -qi "Tested up to:" "$PLUGIN_DIR/readme.txt"; then
        add_finding "WARNING" "Readme" "readme.txt" "0" "Missing 'Tested up to' field" "Add: Tested up to: 6.7"
    fi

    # Update URI in plugin header (forbidden)
    MAIN_FILE=$(grep -rl "Plugin Name:" "$PLUGIN_DIR" --include="*.php" | head -1 || echo "")
    if [ -n "$MAIN_FILE" ] && grep -qi "Update URI:" "$MAIN_FILE"; then
        add_finding "BLOCKER" "Plugin-Header" "$MAIN_FILE" "0" "Update URI header detected (instant rejection)" "Remove Update URI from plugin header"
    fi
else
    add_finding "BLOCKER" "Readme" "readme.txt" "0" "No readme.txt found" "Create readme.txt per WP.org format"
fi


# ─── CHECK 8: ALLOW_UNFILTERED_UPLOADS ───

echo -e "\n=== Category 8: Dangerous Constants ===" >&2

while IFS=: read -r file line content; do
    skip_path "$file" && continue
    add_finding "BLOCKER" "Dangerous-Constant" "$file" "$line" "ALLOW_UNFILTERED_UPLOADS defined (instant rejection)" "Remove; never define this constant"
done < <(grep -rn "ALLOW_UNFILTERED_UPLOADS" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# Defining WP core constants
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    add_finding "WARNING" "Dangerous-Constant" "$file" "$line" "Plugin defines WP core constant: $(echo "$content" | head -c 100)" "Remove; do not redefine WP core constants"
done < <(grep -rnIE "define\s*\(\s*['\"]WP_(DEBUG|DEBUG_LOG|DEBUG_DISPLAY|MEMORY_LIMIT|MAX_MEMORY_LIMIT|CONTENT_DIR|CONTENT_URL|PLUGIN_DIR|PLUGIN_URL|LANG_DIR|HOME|SITEURL|CACHE|POST_REVISIONS|AUTO_UPDATE_CORE|ALLOW_REPAIR|ALLOW_MULTISITE|DEFAULT_THEME|TEMP_DIR|ENVIRONMENT_TYPE|CRON_LOCK_TIMEOUT|DISABLE_FATAL_ERROR_HANDLER|HTTP_BLOCK_EXTERNAL|ACCESSIBLE_HOSTS)['\"]" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)


# ─── CHECK 9: Localhost References ───

echo -e "\n=== Category 9: Localhost ===" >&2

while IFS=: read -r file line content; do
    skip_path "$file" && continue
    add_finding "WARNING" "Localhost" "$file" "$line" "Localhost/dev reference found: $(echo "$content" | head -c 80)" "Remove before production release"
done < <(grep -rnIE "(localhost|127\.0\.0\.1)" "$PLUGIN_DIR" --include="*.php" --include="*.js" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ | grep -v "*.min.js" || true)


# ─── CHECK 10: Code Obfuscation ───

echo -e "\n=== Category 10: Code Obfuscation ===" >&2

while IFS=: read -r file line content; do
    skip_path "$file" && continue
    add_finding "BLOCKER" "Obfuscation" "$file" "$line" "Obfuscated/encoded code detected: $(echo "$content" | head -c 80)" "Ship readable source code"
done < <(grep -rnE '(@Zend;|sourceguardian\.com|sg_load|ionCube|\$__x=|eval\s*\(\s*base64_decode|eval\s*\(\s*gzinflate)' "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)


# ─── CHECK 11: Appsero SDK (WPPOOL-specific) ───

echo -e "\n=== Category 11: Appsero SDK ===" >&2

APPSERO_FILE=$(find "$PLUGIN_DIR" -path "*/appsero/src/Client.php" -not -path "*/node_modules/*" 2>/dev/null | head -1 || echo "")
if [ -n "$APPSERO_FILE" ]; then
    # Check for updater method usage
    while IFS=: read -r file line content; do
        skip_path "$file" && continue
        add_finding "BLOCKER" "Appsero-Updater" "$file" "$line" "Appsero updater() call in free plugin (forbidden by G8)" "Remove ->updater() call; free plugins use WP.org updates"
    done < <(grep -rn "->updater()" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

    # Check if Appsero is disclosed in readme
    if [ -f "$PLUGIN_DIR/readme.txt" ]; then
        has_appsero_disclosure=$(grep -ci "appsero" "$PLUGIN_DIR/readme.txt" || true)
        if [ "${has_appsero_disclosure:-0}" -eq 0 ]; then
            add_finding "BLOCKER" "Appsero-Disclosure" "readme.txt" "0" "Appsero SDK bundled but not disclosed in readme External services section" "Add Appsero to == External services == with api.appsero.com URL"
        fi
    fi
fi


# ─── CHECK 12: Headway Changelog Widget ───

echo -e "\n=== Category 12: Headway Widget ===" >&2

while IFS=: read -r file line content; do
    skip_path "$file" && continue
    add_finding "WARNING" "Headway-Widget" "$file" "$line" "Headway changelog widget loads external CDN; needs disclosure" "Add to readme == External services == OR make opt-in"
done < <(grep -rnE "(headway|headwayapp\.co|HW_widget)" "$PLUGIN_DIR" --include="*.php" --include="*.js" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)


# ─── Shared data for the repo-level checks below ───

# Every file WP.org would receive: all files except dependency/VCS folders and .distignore
# entries. Unlike skip_path(), vendor/ is included because bundled libraries ship too.
SHIPPED=()
while IFS= read -r f; do
    rel="${f#"$PLUGIN_DIR"/}"
    rel="${rel#./}"
    distignored "$rel" && continue
    SHIPPED+=("$rel")
done < <(find "$PLUGIN_DIR" -type f -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/.github/*" 2>/dev/null | sort || true)

# True when a shipped file matches the glob (relative to the plugin root).
ships() {
    local want="$1" rel
    for rel in "${SHIPPED[@]+"${SHIPPED[@]}"}"; do
        # shellcheck disable=SC2053
        [[ "$rel" == $want ]] && return 0
    done
    return 1
}

README_TXT=""
[ -f "$PLUGIN_DIR/readme.txt" ] && README_TXT=$(tr -d '\r' < "$PLUGIN_DIR/readme.txt")
readme_has() { grep -qiE -- "$1" <<< "$README_TXT"; }

MAIN_PHP=$(grep -lE '^[[:space:]/*#]*Plugin Name:' "$PLUGIN_DIR"/*.php 2>/dev/null | awk 'NR == 1' || true)
TEXT_DOMAIN="${TEXT_DOMAIN:-}"
if [ -z "$TEXT_DOMAIN" ] && [ -n "$MAIN_PHP" ]; then
    TEXT_DOMAIN=$(awk 'tolower($0) ~ /text domain:/ { sub(/.*[Tt]ext [Dd]omain:/, ""); gsub(/[[:space:]\r]/, ""); print; exit }' "$MAIN_PHP" || true)
fi

is_comment() {
    local trimmed="${1#"${1%%[![:space:]]*}"}"
    [[ "$trimmed" == //* || "$trimmed" == \** || "$trimmed" == /\** || "$trimmed" == \#* ]]
}

PY=""
for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import json' >/dev/null 2>&1; then
        PY="$cand"
        break
    fi
done


# ─── CHECK 13: Source code for compiled assets (Guideline 4) ───

echo -e "\n=== Category 13: Source Code & Build (G4) ===" >&2

BUILT_JS=()
SOURCE_FILES=0
for rel in "${SHIPPED[@]+"${SHIPPED[@]}"}"; do
    case "/$rel" in
        */vendor/*) continue ;;
        *.min.js|*/build/*.js|*/dist/*.js) BUILT_JS+=("$rel"); continue ;;
        *.config.js|*/webpack.*.js|*/gulpfile.js|*/Gruntfile.js) continue ;;
        *.js) grep -qE '__webpack_require__|webpackChunk|webpackJsonp' "$PLUGIN_DIR/$rel" 2>/dev/null && { BUILT_JS+=("$rel"); continue; }
              SOURCE_FILES=$((SOURCE_FILES + 1)) ;;
        *.jsx|*.ts|*.tsx|*.vue|*.scss|*.sass|*.less) SOURCE_FILES=$((SOURCE_FILES + 1)) ;;
    esac
done

if [ "${#BUILT_JS[@]}" -gt 0 ]; then
    if readme_has '(github\.com|gitlab\.com|bitbucket\.org)/'; then
        : # Public source repository linked from readme.txt.
    elif ! ships "package.json" || [ "$SOURCE_FILES" -eq 0 ]; then
        add_finding "BLOCKER" "G4-Source" "${BUILT_JS[0]}" "0" "Compiled/minified JS ships (${#BUILT_JS[@]} file(s)) without its human-readable source (package.json and the source files are not shipped, and readme.txt links no public repository)" "Ship the source (src/, package.json, build config; remove them from .distignore) or link the public source repository in readme.txt == Build Instructions =="
    fi
    if ! readme_has '^==[[:space:]]*(build instructions|source code|development|developers)'; then
        add_finding "WARNING" "G4-Source" "readme.txt" "0" "Compiled JS ships (e.g. ${BUILT_JS[0]}) but readme.txt has no == Build Instructions == section" "Add == Build Instructions == with the commands to rebuild the assets (e.g. npm install && npm run build) and where the source lives"
    fi
fi


# ─── CHECK 14: Bundled libraries ───

echo -e "\n=== Category 14: Bundled Libraries ===" >&2

# Composer-installed code must ship with composer.json.
if ships "vendor/*" && ! ships "composer.json"; then
    add_finding "BLOCKER" "Library-Composer" "vendor/" "0" "vendor/ ships without composer.json, so reviewers cannot see how the bundled libraries are installed or updated" "Install bundled SDKs with Composer and ship composer.json (composer.lock may stay in .distignore)"
fi

APPSERO_CLIENT=""
LC_SAVED="${LC_ALL:-}"
for rel in "${SHIPPED[@]+"${SHIPPED[@]}"}"; do
    base="${rel##*/}"
    lower="${base,,}"
    case "/$rel" in
        */appsero/*Client.php)
            [ -z "$APPSERO_CLIENT" ] && APPSERO_CLIENT="$rel"
            case "/$rel" in
                */vendor/*) ;;
                *) add_finding "WARNING" "Library-Composer" "$rel" "0" "Appsero SDK copied into the plugin by hand instead of installed with Composer" "Require appsero/client with Composer and remove the manual copy" ;;
            esac ;;
    esac
    # Libraries WordPress core already ships.
    case "$lower" in
        jquery.js|jquery.min.js|jquery-[0-9]*.js|jquery-ui.js|jquery-ui.min.js|jquery-ui-[0-9]*.js|jquery-migrate*.js|backbone.js|backbone-min.js|backbone.min.js|underscore.js|underscore-min.js|underscore.min.js|moment.js|moment.min.js|react.development.js|react.production.min.js|react-dom.*.js|lodash.js|lodash.min.js|class-phpmailer.php|phpmailer.php|class-simplepie.php|simplepie.php)
            add_finding "BLOCKER" "Library-Core" "$rel" "0" "Bundles a library WordPress core already ships ($base)" "Remove it and depend on the core script handle (jquery, jquery-ui-*, backbone, underscore, moment, react / wp-element, lodash) or core class instead" ;;
    esac
done

# Appsero SDK version (an outdated Appsero client was flagged in all 9 WPPOOL closures).
# Committed SDK: read Client.php. Composer-installed at release: read composer.lock.
APPSERO_VERSION=""
APPSERO_WHERE=""
if [ -n "$APPSERO_CLIENT" ]; then
    APPSERO_VERSION=$(awk -F"'" '/\$version[[:space:]]*=/ { print $2; exit }' "$PLUGIN_DIR/$APPSERO_CLIENT" 2>/dev/null || true)
    APPSERO_WHERE="$APPSERO_CLIENT"
elif [ -f "$PLUGIN_DIR/composer.lock" ]; then
    APPSERO_VERSION=$(awk '/"name"[[:space:]]*:[[:space:]]*"appsero\/client"/ { found = 1 } found && /"version"/ { gsub(/[^0-9.]/, ""); print; exit }' "$PLUGIN_DIR/composer.lock" 2>/dev/null || true)
    APPSERO_WHERE="composer.lock"
fi
if [ -n "$APPSERO_VERSION" ]; then
    APPSERO_LATEST=$(curl -fsS --max-time 15 "https://repo.packagist.org/p2/appsero/client.json" 2>/dev/null \
        | grep -oE '"version":"v?[0-9]+\.[0-9]+\.[0-9]+"' | sed -E 's/.*"v?([0-9.]+)"/\1/' | sort -V | awk 'END { print }' || true)
    APPSERO_LATEST="${APPSERO_LATEST:-2.0.4}"
    if [ -n "$APPSERO_VERSION" ] && [ "$APPSERO_VERSION" != "$APPSERO_LATEST" ] \
        && [ "$(printf '%s\n%s\n' "$APPSERO_VERSION" "$APPSERO_LATEST" | sort -V | awk 'NR == 1')" = "$APPSERO_VERSION" ]; then
        add_finding "BLOCKER" "Library-Outdated" "$APPSERO_WHERE" "0" "Appsero SDK $APPSERO_VERSION is outdated (latest is $APPSERO_LATEST); an outdated Appsero client was cited in every WPPOOL closure" "composer update appsero/client, then re-test the opt-in screen"
    fi
fi

# Other Composer packages: outdated or abandoned according to Packagist.
if [ -n "$PY" ] && [ -f "$PLUGIN_DIR/composer.lock" ]; then
    while IFS='|' read -r pkg installed latest abandoned; do
        [ -z "$pkg" ] && continue
        if [ -n "$abandoned" ]; then
            add_finding "WARNING" "Library-Abandoned" "vendor/$pkg" "0" "$pkg is marked abandoned on Packagist (replacement: $abandoned)" "Switch to the maintained replacement or remove the dependency"
        fi
        if [ -n "$latest" ] && [ "$installed" != "$latest" ]; then
            add_finding "WARNING" "Library-Outdated" "vendor/$pkg" "0" "$pkg $installed is bundled; the latest stable release is $latest" "Run composer update $pkg and re-test"
        fi
    done < <("$PY" - "$PLUGIN_DIR/composer.lock" 2>/dev/null <<'WPPOOL_PACKAGIST_PY' || true
import json
import re
import sys
import urllib.request


def stable(version):
    return re.fullmatch(r'v?\d+(\.\d+)*', version or '') is not None


def key(version):
    return [int(part) for part in version.lstrip('v').split('.')]


lock = json.load(open(sys.argv[1], encoding='utf-8'))
for pkg in lock.get('packages', []):
    name = pkg.get('name', '')
    installed = str(pkg.get('version', '')).lstrip('v')
    if not name or name == 'appsero/client' or not stable(installed):
        continue
    try:
        with urllib.request.urlopen('https://repo.packagist.org/p2/' + name + '.json', timeout=15) as resp:
            versions = json.load(resp).get('packages', {}).get(name, [])
    except Exception:
        continue
    stables = [v['version'] for v in versions if stable(v.get('version', ''))]
    latest = max(stables, key=key).lstrip('v') if stables else ''
    abandoned = versions[0].get('abandoned') if versions else None
    if abandoned is True:
        abandoned = 'none suggested'
    print('|'.join([name, installed, latest, abandoned or '']))
WPPOOL_PACKAGIST_PY
)
fi


# ─── CHECK 15: WP.org code rules ───

echo -e "\n=== Category 15: WP.org Code Rules ===" >&2

# Loading WordPress core files directly.
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    is_comment "$content" && continue
    add_finding "BLOCKER" "Core-Loading" "$file" "$line" "Loads a WordPress core loading file directly: $(echo "$content" | head -c 120)" "Run inside WordPress instead (admin-ajax.php, the REST API or admin-post.php hooks)"
done < <(grep -rnIE "(require|include)(_once)?[^;]*(wp-(load|config|blog-header|settings)\.php|wp-admin/admin\.php)" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# HEREDOC / NOWDOC.
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    is_comment "$content" && continue
    add_finding "BLOCKER" "HEREDOC" "$file" "$line" "HEREDOC/NOWDOC syntax (WP.org asks for it to be removed): $(echo "$content" | head -c 100)" "Use normal strings, or close PHP and write the HTML with escaped echo statements"
done < <(grep -rnIE "<<<[[:space:]]*['\"]?[A-Za-z_]" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# ob_start() without a matching close.
while IFS= read -r file; do
    skip_path "$file" && continue
    opens=$(grep -cE '(^|[^A-Za-z0-9_])ob_start[[:space:]]*\(' "$file" || true)
    closes=$(grep -cE '(^|[^A-Za-z0-9_])ob_(get_clean|end_clean|end_flush|get_flush)[[:space:]]*\(' "$file" || true)
    if [ "${opens:-0}" -gt "${closes:-0}" ]; then
        first=$(grep -nE '(^|[^A-Za-z0-9_])ob_start[[:space:]]*\(' "$file" | awk -F: 'NR == 1 { print $1 }' || true)
        add_finding "WARNING" "Output-Buffer" "$file" "${first:-0}" "ob_start() is called ${opens} time(s) but buffers are closed only ${closes} time(s) in this file" "Close every buffer with ob_get_clean() / ob_end_clean() on every path, including early returns"
    fi
done < <(grep -rlE '(^|[^A-Za-z0-9_])ob_start[[:space:]]*\(' "$PLUGIN_DIR" --include="*.php" 2>/dev/null || true)

# Changing global PHP settings.
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    is_comment "$content" && continue
    severity="WARNING"
    [[ "$content" == *date_default_timezone_set* ]] && severity="BLOCKER"
    add_finding "$severity" "Server-Config" "$file" "$line" "Changes a global PHP setting for the whole site: $(echo "$content" | head -c 100)" "Remove it; use wp_date()/current_time() for time zones and let the site owner manage PHP limits"
done < <(grep -rnIE '(^|[^A-Za-z0-9_>:$])(ini_set|error_reporting|date_default_timezone_set|set_time_limit)[[:space:]]*\(' "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# Hardcoded wp-content / wp-json paths.
while IFS=: read -r file line content; do
    case "$file" in *.min.js|*/build/*|*/dist/*) continue ;; esac
    skip_path "$file" && continue
    is_comment "$content" && continue
    add_finding "WARNING" "Hardcoded-Path" "$file" "$line" "Hardcoded WordPress path/URL: $(echo "$content" | head -c 100)" "Use plugin_dir_path(), plugins_url(), content_url(), wp_upload_dir() or rest_url() (wp.apiFetch / wpApiSettings.root in JS)"
done < <(grep -rnIE "['\"/]wp-content/(plugins|themes|uploads)|['\"]/?wp-json/" "$PLUGIN_DIR" --include="*.php" --include="*.js" --include="*.jsx" --include="*.ts" --include="*.tsx" --include="*.vue" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# Writing into the plugin/theme/core folders or generating PHP files.
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    is_comment "$content" && continue
    if echo "$content" | grep -qE "index\.php['\"]"; then
        continue  # "Silence is golden" index.php guards in upload folders are fine.
    elif echo "$content" | grep -qE "\.php['\"]"; then
        add_finding "BLOCKER" "File-Write" "$file" "$line" "Writes a PHP file: $(echo "$content" | head -c 100)" "Never generate PHP files; store data in the database or under wp_upload_dir()"
    elif echo "$content" | grep -qE '__DIR__|__FILE__|plugin_dir_path|WP_PLUGIN_DIR|WP_CONTENT_DIR|ABSPATH|get_template_directory|get_stylesheet_directory|_PLUGIN_(DIR|PATH)|_DIR[^A-Za-z]|_PATH[^A-Za-z]'; then
        add_finding "WARNING" "File-Write" "$file" "$line" "Possibly writes into the plugin/theme/core folder: $(echo "$content" | head -c 100)" "Write files under wp_upload_dir() (or keep the data in the database); plugin folders are replaced on update"
    fi
done < <(grep -rnIE '(^|[^A-Za-z0-9_>:$])(file_put_contents|fopen|copy|rename|move_uploaded_file|mkdir|wp_mkdir_p)[[:space:]]*\(' "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ | grep -vE "fopen[[:space:]]*\([[:space:]]*['\"]php://" || true)

# Installing or activating other plugins.
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    is_comment "$content" && continue
    add_finding "WARNING" "Plugin-Install" "$file" "$line" "Installs or activates another plugin: $(echo "$content" | head -c 100)" "Only allowed as a direct user action (button click) with nonce + capability checks; prefer the Requires Plugins header or a link to the core plugin installer"
done < <(grep -rnIE '(^|[^A-Za-z0-9_>:$])(activate_plugins?)[[:space:]]*\(|new[[:space:]]+(\\)?Plugin_Upgrader|(^|[^A-Za-z0-9_>:$])plugins_api[[:space:]]*\(' "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# Free code that detects Pro (class_exists / defined / function_exists / is_plugin_active).
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    is_comment "$content" && continue
    add_finding "WARNING" "G5-Pro-Gate" "$file" "$line" "Free code checks whether Pro is installed: $(echo "$content" | head -c 120). If this changes what the free plugin does, it is trialware (G5)" "Keep free behaviour identical with or without Pro; expose apply_filters()/do_action() hooks that Pro attaches to"
done < <(grep -rnIE "(class_exists|defined|function_exists|is_plugin_active)[[:space:]]*\([[:space:]]*['\"][^'\"]*(PRO(_|['\"])|Pro([A-Z_\\\\]|['\"])|[-_]pro([-_/.]|['\"])|[Pp]remium|PREMIUM)" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)

# Review links filtered to 5 stars.
while IFS=: read -r file line content; do
    skip_path "$file" && continue
    add_finding "BLOCKER" "Review-Manipulation" "$file" "$line" "Review link filtered to 5-star reviews: $(echo "$content" | head -c 100)" "Link to the plain reviews page (wordpress.org/support/plugin/<slug>/reviews/#new-post)"
done < <(grep -rnIE 'reviews/?\?filter=5' "$PLUGIN_DIR" --include="*.php" --include="*.js" --include="*.jsx" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)


# ─── CHECK 16: Internationalization and file names ───

echo -e "\n=== Category 16: i18n & File Names ===" >&2

STR_RE="('([^'\\\\]|\\\\.)*'|\"([^\"\\\\]|\\\\.)*\")"
I18N_SIMPLE="(^|[^A-Za-z0-9_>:$])(__|_e|esc_html__|esc_html_e|esc_attr__|esc_attr_e)[[:space:]]*\\([[:space:]]*${STR_RE}[[:space:]]*(,[[:space:]]*[^),]+)?\\)"
I18N_CONTEXT="(^|[^A-Za-z0-9_>:$])(_x|_ex|esc_html_x|esc_attr_x)[[:space:]]*\\([[:space:]]*${STR_RE}[[:space:]]*,[[:space:]]*${STR_RE}[[:space:]]*(,[[:space:]]*[^),]+)?\\)"
I18N_NONLITERAL="(^|[^A-Za-z0-9_>:$])(__|_e|_x|_ex|_n|esc_html__|esc_html_e|esc_attr__|esc_attr_e|esc_html_x|esc_attr_x)[[:space:]]*\\([[:space:]]*\\$"

if [ -n "$TEXT_DOMAIN" ]; then
    while IFS=: read -r file line content; do
        case "$file" in *.min.js|*/build/*|*/dist/*) continue ;; esac
        skip_path "$file" && continue
        is_comment "$content" && continue
        if [[ "$file" == *.php ]] && grep -qE "$I18N_NONLITERAL" <<< "$content"; then
            add_finding "BLOCKER" "i18n" "$file" "$line" "Translation function called with a variable instead of a literal string: $(echo "$content" | head -c 100)" "Pass the literal text to __()/_e()/esc_html__() so it can be extracted for translation"
        fi
        while IFS= read -r call; do
            [ -z "$call" ] && continue
            # The domain is the argument after the string (two strings for the _x family).
            stripped=$(sed -E "s/${STR_RE}/S/g" <<< "$call")
            commas=$(tr -cd ',' <<< "$stripped" | wc -c)
            needed=1
            [[ "$call" == _x* || "$call" == _ex* || "$call" == esc_html_x* || "$call" == esc_attr_x* ]] && needed=2
            if [ "$((commas))" -lt "$needed" ]; then
                [[ "$file" == *.php ]] && add_finding "BLOCKER" "i18n" "$file" "$line" "Translation call without a text domain: $(echo "$call" | head -c 100)" "Add '$TEXT_DOMAIN' as the text domain argument"
                continue
            fi
            domain=$(sed -E 's/.*,[[:space:]]*([^),]+)[[:space:]]*\)$/\1/; s/[[:space:]]+$//' <<< "$call")
            case "$domain" in
                "'$TEXT_DOMAIN'"|"\"$TEXT_DOMAIN\"") ;;
                \'*\'|\"*\")
                    add_finding "BLOCKER" "i18n" "$file" "$line" "Wrong text domain $domain (plugin slug is '$TEXT_DOMAIN'): $(echo "$call" | head -c 100)" "Use '$TEXT_DOMAIN' as the text domain" ;;
                *)
                    add_finding "BLOCKER" "i18n" "$file" "$line" "Text domain is a variable or constant ($domain), so translation tools cannot read it" "Use the literal string '$TEXT_DOMAIN'" ;;
            esac
        done < <(grep -oE "$I18N_SIMPLE|$I18N_CONTEXT" <<< "$content" | sed -E 's/^[^A-Za-z_]//' || true)
    done < <(grep -rnIE '(^|[^A-Za-z0-9_>:$])(__|_e|_x|_ex|_n|esc_html__|esc_html_e|esc_attr__|esc_attr_e|esc_html_x|esc_attr_x)[[:space:]]*\(' "$PLUGIN_DIR" --include="*.php" --include="*.js" --include="*.jsx" --include="*.ts" --include="*.tsx" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)
fi

# File names that break SVN or case-insensitive / Windows file systems.
LC_ALL=C
UNSAFE_NAME_RE='[^-A-Za-z0-9._/+~]'
for rel in "${SHIPPED[@]+"${SHIPPED[@]}"}"; do
    case "$rel" in *" "*) continue ;; esac  # Spaces are reported in Category 6.
    if [[ "$rel" =~ $UNSAFE_NAME_RE ]]; then
        add_finding "BLOCKER" "File-Name" "$rel" "0" "File name contains characters that break SVN or some file systems (only letters, digits, . _ - + ~ are safe)" "Rename the file"
    fi
done
while IFS= read -r dup; do
    [ -z "$dup" ] && continue
    add_finding "BLOCKER" "File-Name" "$dup" "0" "Two shipped files differ only by letter case ($dup); one overwrites the other on Windows/macOS" "Rename or remove one of them"
done < <(printf '%s\n' "${SHIPPED[@]+"${SHIPPED[@]}"}" | tr 'A-Z' 'a-z' | sort | uniq -d || true)
LC_ALL="$LC_SAVED"
[ -z "$LC_ALL" ] && unset LC_ALL


# ─── CHECK 17: Every external host is documented ───

echo -e "\n=== Category 17: External Services Disclosure (G6/G7) ===" >&2

CALL_RE='wp_remote_|wp_safe_remote_|download_url|fetch[[:space:]]*\(|axios|XMLHttpRequest|\$\.(get|post|ajax|getJSON)|<script|<iframe|wp_enqueue_|wp_register_|sendBeacon|WebSocket|file_get_contents|curl_init|curl_setopt|api_url|API_URL|_endpoint|_ENDPOINT|apiUrl|endpoint:'
IGNORE_HOSTS_RE='(^|\.)(wordpress\.org|w\.org|w3\.org|schema\.org|example\.(com|org|net)|localhost|php\.net|mozilla\.org|github\.com|githubusercontent\.com|reactjs\.org|react\.dev|jquery\.com|opensource\.org|gnu\.org|json-schema\.org)$'
KNOWN_SERVICES_RE='icanhazip\.com|ipify\.org|ipinfo\.io|ip-api\.com|headwayapp\.co|appsero\.com|google-analytics\.com|googletagmanager\.com|hotjar\.com|mixpanel\.com|segment\.(io|com)|sentry\.io|intercom\.io|crisp\.chat|tawk\.to|clarity\.ms'
declare -A HOST_SEEN=()

report_host() {
    local host="$1" file="$2" line="$3" base
    [ -n "${HOST_SEEN[$host]:-}" ] && return 0
    HOST_SEEN[$host]=1
    grep -qE "$IGNORE_HOSTS_RE" <<< "$host" && return 0
    base=$(awk -F. '{ print (NF > 1 ? $(NF-1) "." $NF : $0) }' <<< "$host")
    readme_has "${base//./\\.}" && return 0
    add_finding "BLOCKER" "G6-External-Services" "$file" "$line" "Code contacts $host but readme.txt does not document it" "Add $host to readme.txt == External services ==: what it is used for, what data is sent and when, with links to its terms of service and privacy policy"
}

while IFS=: read -r file line content; do
    rel="${file#"$PLUGIN_DIR"/}"
    rel="${rel#./}"
    distignored "$rel" && continue
    # Well-known trackers and IP lookups: anywhere, including vendor/ and minified files.
    while IFS= read -r host; do
        [ -n "$host" ] && report_host "$host" "$rel" "$line"
    done < <(grep -oiE "https?://[A-Za-z0-9.-]*($KNOWN_SERVICES_RE)" <<< "$content" | sed -E 's#^https?://##' | tr 'A-Z' 'a-z' || true)
    # Other hosts: only on lines that make a remote call, and not in minified code.
    [ "${#content}" -gt 1000 ] && continue
    case "$rel" in *.min.js) continue ;; esac
    grep -qE "$CALL_RE" <<< "$content" || continue
    while IFS= read -r host; do
        [ -n "$host" ] && report_host "$host" "$rel" "$line"
    done < <(grep -oE 'https?://[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+' <<< "$content" | sed -E 's#^https?://##' | tr 'A-Z' 'a-z' || true)
done < <(grep -rnIE 'https?://[A-Za-z0-9-]+\.[A-Za-z]' "$PLUGIN_DIR" --include="*.php" --include="*.js" --include="*.jsx" --include="*.ts" --include="*.tsx" --include="*.vue" 2>/dev/null | grep -v node_modules/ || true)


# ─── REPORT SUMMARY ───

echo -e "\n========================================" >&2
echo -e "=== COMPLIANCE CHECK COMPLETE ===" >&2
echo -e "========================================" >&2
echo -e "${RED}BLOCKERS: $BLOCKERS${NC}" >&2
echo -e "${YELLOW}WARNINGS: $WARNINGS${NC}" >&2
echo -e "${GREEN}INFO: $INFO_COUNT${NC}" >&2
echo -e "========================================" >&2

if [ "$BLOCKERS" -gt 0 ]; then
    echo -e "\n${RED}RESULT: FAIL — $BLOCKERS blocker(s) found. PR should not be merged.${NC}" >&2
    EXIT_CODE=1
elif [ "$WARNINGS" -gt 0 ]; then
    echo -e "\n${YELLOW}RESULT: WARN — No blockers, but $WARNINGS warning(s) found. Review recommended.${NC}" >&2
    EXIT_CODE=0
else
    echo -e "\n${GREEN}RESULT: PASS — No issues found.${NC}" >&2
    EXIT_CODE=0
fi

# Output JSON array to stdout
echo "["
first=true
while IFS= read -r line; do
    if [ "$first" = true ]; then
        first=false
    else
        echo ","
    fi
    echo "  $line"
done < "$FINDINGS_FILE"
echo "]"

rm -f "$FINDINGS_FILE"
exit $EXIT_CODE

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
done < <(grep -rnE "(plugin-update-checker|WP_GitHub_Updater|WPGitHubUpdater|PucFactory|YahnisElsts|pre_set_site_transient_update_plugins|site_transient_update_plugins)" "$PLUGIN_DIR" --include="*.php" 2>/dev/null | grep -v vendor/ | grep -v node_modules/ || true)


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

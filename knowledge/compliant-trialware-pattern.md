# Compliant Trialware Fix Pattern (WP.org Guideline 5)

Documented from EchoRewards and WP Dark Mode codebases that passed WP.org review
and were re-listed after Guideline 5 closure (Aug-Sep 2026).

---

## Architecture Overview

Two-layer separation:

```
FREE PLUGIN (PHP):
  Config/defaults       --> declare all settings with REAL working defaults
  apply_filters()       --> extension point at every decision, passes working default
  wp_localize_script()  --> passes is_pro/is_ultimate boolean to JS (display only)
  Render/output logic   --> NO license check, processes any valid value

PRO/ULTIMATE PLUGIN (PHP):
  connect_license()     --> if valid, register filters
  add_filter()          --> hooks free's extension points, returns saved custom values
  Admin hooks           --> injects is_pro/is_ultimate into localized JS data via filter

FREE PLUGIN (JS/React/Vue):
  Read is_pro from localized global  --> controls UI display ONLY
  Disabled inputs, lock icons, upgrade popups
  Zero effect on PHP saves or functionality
```

---

## Rule 1: `apply_filters()` with REAL Working Defaults

Every filter default must be a value that makes the free plugin work correctly.
Never use `null`, `false`, `[]`, or `''` as a way to disable functionality.

### Good Defaults (from EchoRewards)

```php
// Real working value -- free uses 'percent' discount type
$reward_type = apply_filters( 'ecre_reward_type', 'percent', $settings_type, $settings );

// Real working value -- rewards trigger on 'completed' order status
$reward_status = apply_filters( 'ecre_reward_order_status', 'completed', $settings );

// Real working value -- 5% discount
$reward_discount = apply_filters( 'ecre_reward_discount', 5, $settings );

// Real email subject text
$subject = apply_filters( 'ecre_referral_email_subject', 'Here is a discount for you!', $settings );

// 0 = unlimited referrals (working behavior, not broken)
$monthly_limit = apply_filters( 'ecre_monthly_referral_limit', 0, $settings );
```

### Good Defaults (from WP Dark Mode)

```php
// 10 social share channels available in free
$channel_ids = ['facebook', 'twitter', 'pinterest', 'reddit', 'copy',
                'chatgpt', 'grok', 'perplexity', 'gemini', 'claude'];
return apply_filters('wpdm_social_share_available_channel_ids', $channel_ids);

// Social share options with real values
$defaults = [
    'button_spacing'       => 1,        // normal spacing
    'post_types'           => ['post', 'page'],  // shows on posts/pages
    'show_total_share_count' => 0,      // disabled = valid state
    'minimum_share_count'  => 0,        // no minimum = valid
];
```

### Acceptable: Features Disabled by Default (if that's the real default)

```php
// false = rewards issued immediately (working behavior, not "locked")
$enable_delay = apply_filters( 'ecre_enable_reward_delay', false, $settings );

// false = custom triggers off by default (valid state for free)
$enabled = apply_filters( 'wp_dark_custom_triggers_enabled', false );

// [] = no image replacements (valid state, nothing broken)
$replaces = apply_filters( 'wp_dark_image_replaces', [] );
```

These are OK because `false` and `[]` represent a real working state
(feature disabled, empty list), NOT a lock preventing functionality.

### BAD Defaults (what WP.org catches)

```php
// BAD: null used as lock (free's generator won't run)
$channels = apply_filters('plugin_available_channels', null);

// BAD: false used to prevent feature from working
$can_use = apply_filters('plugin_feature_enabled', false);
if (!$can_use) return; // <-- THIS IS TRIALWARE

// BAD: empty array blocking a list that should have items
$styles = apply_filters('plugin_switch_styles', []);
foreach ($styles as $style) { /* nothing renders */ }
```

---

## Rule 2: Render Logic Has ZERO License Checks

Free plugin's output/render code must process any valid value without
checking license status.

### Good (WP Dark Mode shortcode renderer)

```php
/**
 * All 24 switch styles ship fully in this free plugin as complete,
 * working components. There is no license/Ultimate check on this value.
 */
$style = isset($atts['style']) ? sanitize_text_field(wp_unslash($atts['style'])) : 1;
// Renders style 1-24 with zero license check
```

### Good (WP Dark Mode CSS variable generator)

```php
$img_brightness = $this->get_option('image_enabled_low_brightness')
    ? $this->get_option('image_brightness')
    : '100';
// No license check -- reads saved option, falls back to 100%
```

### BAD (what was closed)

```php
// Renderer works but settings UI disables the field
if (!$this->is_pro) {
    $style = 1; // Force style 1 for free users <-- TRIALWARE
}
```

---

## Rule 3: Pro Hooks In via `add_filter()` Only When Licensed

### EchoRewards Pattern

```php
// Pro plugin: class-base.php
public function register_premium_filters() {
    $this->connect_license();
    if ( ! $this->license_status ) {
        return;  // Only register filters if license valid
    }
    new Hooks\Ecre_Pro_Filters();
}

// Ecre_Pro_Filters constructor -- registers ALL hooks
public function __construct() {
    add_filter( 'ecre_reward_type', array( $this, 'raw_setting_type' ), 10, 2 );
    add_filter( 'ecre_pre_generate_reward', array( $this, 'pre_generate_reward' ), 10, 5 );
    add_filter( 'ecre_enable_reward_delay', array( $this, 'enable_reward_delay' ), 10, 2 );
    add_filter( 'ecre_schedule_actions_enabled', '__return_true' );
    add_filter( 'ecre_load_coupon_tracking', '__return_false' );
    // ... 20+ more filters
}
```

### WP Dark Mode Pattern

```php
// Ultimate plugin: class-boot.php
public function connect_license() {
    global $wp_dark_mode_license;
    $wp_dark_mode_license = (new \WPPOOL\License([...]))->connect();
    if ($wp_dark_mode_license->is_valid()) {
        add_filter('wp_dark_mode_is_ultimate', '__return_true');
    }
}

// Ultimate features class registers all hooks
public function actions() {
    add_filter('wp_dark_switch_available_styles', array($this, 'add_switch_styles'));
    add_filter('wp_dark_image_brightness_level', array($this, 'get_image_brightness_level'));
    add_filter('wp_dark_custom_triggers_enabled', array($this, 'get_custom_triggers_enabled'));
    // ... 15+ more filters
}
```

### Pro Filter Callback Pattern

Each callback reads saved option, returns it (or falls back to default):

```php
// WP Dark Mode Ultimate
public function get_image_brightness_level($default) {
    $value = get_option('wp_dark_mode_image_brightness', $default);
    return is_numeric($value) ? (float)$value : $default;
}

// EchoRewards Pro -- bypasses free's type restriction
public function raw_setting_type($resolved_type, $settings_type = '') {
    return '' !== $settings_type ? $settings_type : $resolved_type;
}
```

---

## Rule 4: `wp_localize_script()` for JS Display Only

Free plugin passes `is_pro` / `is_ultimate` to JS via `wp_localize_script()`.
This boolean controls ONLY UI display (badges, disabled inputs, promo popups).

### EchoRewards

```php
// Ecre_Assets.php
$is_pro = false;
if ( function_exists( 'echo_rewards_pro' ) ) {
    $is_pro = echo_rewards_pro()->license_status;
}
wp_localize_script( 'ecre-admin-build', 'ecreAdmin', array(
    'is_pro'           => $is_pro,
    'is_pro_latest'    => $is_pro_latest,
    'is_pro_activated' => $is_pro_activated,
    // ...
));
```

### WP Dark Mode

```php
// class-assets.php (frontend)
$localize_scripts = array(
    'is_pro' => $this->is_ultimate(),
    // ...
);
wp_localize_script('wp-dark-mode', 'wp_dark_mode_json',
    apply_filters('wp_dark_mode_json', $localize_scripts));

// Ultimate injects via filter
public function wp_dark_mode_json_callback($json) {
    $json['is_ultimate'] = $this->wp_dark_is_ultimate();
    return $json;
}
```

---

## Rule 5: JS/React/Vue UI Locking Patterns (Allowed)

### React Pattern (EchoRewards)

```jsx
// Switcher component -- visual lock only
const Switcher = ({ id, checked, onChange, label, isPro=true }) => (
  <label onClick={ !isPro ? displayProPopup : undefined } >
    <input type="checkbox" disabled={!isPro} />
    {!isPro && (
      <button className='btn-prolock'>
        <span className="icon-wrap">/* crown SVG */</span>
        <span className="text">{translate('upgrade')}</span>
      </button>
    )}
  </label>
);

// Pro popup trigger
export const displayProPopup = () => {
    WPPOOL.Popup('echo_rewards').show();
}
```

### Vue Pattern (WP Dark Mode)

```javascript
// Pinia store
const isPro = ref(wp_dark_mode_admin_json.is_ultimate || false)
const isLocked = ref(!wp_dark_mode_admin_json.is_ultimate)
const showProModal = () => { window.WPDarkModePromo.show() }

// ProBadge component
const isLocked = computed(() => {
    return !(window.wp_dark_mode_admin_json || {})?.is_ultimate
})
```

### What JS Locking Looks Like in Practice

```vue
<!-- Toggle disabled -->
<Toggle :locked="!isPro" />

<!-- Button guarded -->
<button @click.prevent="!isPro ? showProModal() : addNew()">Add</button>

<!-- Input disabled -->
<input :disabled="!isPro" />

<!-- Section conditionally rendered -->
<div v-if="effectiveType === 'reward_point' && isPro">
  <!-- Pro-only UI section -->
</div>
```

### Elementor Widget Pattern (WP Dark Mode)

```php
// Control template (UI only -- locks style picker visually)
<# if ( switchId > 3 && switchId != 23 && !data.is_ultimate ) { #>
    wp-dark-mode-locked
<# } #>

// Render method -- NO license check, renders whatever style selected
echo do_shortcode( wp_sprintf(
    '[wp_dark_mode style="%s" size="%s"]',
    esc_attr($style),
    esc_attr($size)
));
```

---

## Rule 6: `is_ultimate()` / `is_pro` in Free Plugin PHP -- Allowed Uses

Every `is_ultimate()` / `is_pro` reference in free PHP must be one of:

| Allowed Use | Example |
|---|---|
| Pass to JS via `wp_localize_script()` | `'is_pro' => $this->is_ultimate()` |
| Show/hide admin upgrade menu link | `if (!$this->is_ultimate()) add_submenu_page('Upgrade')` |
| Show/hide upgrade popup script | `if (!$is_pro) wp_enqueue_script('promo-popup')` |
| Reset settings to working defaults | `$options->post_types = $defaults['post_types']` |
| Skip enqueuing upgrade-specific admin notices | Hide promo banner if already premium |

### NEVER Allowed

```php
// NEVER gate rendering
if ($this->is_pro) { echo $output; }

// NEVER gate saving
if (!$this->is_pro) { return; } // before update_option

// NEVER gate functionality
if ($this->is_pro) { $this->process_reward(); }

// NEVER gate AJAX/REST handlers
if (!$this->is_pro) { wp_send_json_error('Pro required'); }
```

---

## Verification Checklist (for Skill Auditors)

Run after implementing compliant pattern:

- [ ] Grep `is_pro\|is_ultimate\|is_premium\|license_status` in free PHP
  -- every hit must be: definition, `wp_localize_script` pass-through, admin UI, or default-reset
- [ ] Every `apply_filters()` default is a real working value (not null/false/[] used as lock)
- [ ] Deactivate Pro/Ultimate -- test every free feature end-to-end
- [ ] Settings saved in free are read and applied by free
- [ ] Shortcode/block/widget render has zero license checks
- [ ] Pro plugin's PHP hooks ONLY via `add_filter()` / `add_action()`
- [ ] Zero pro code exists in free plugin files
- [ ] JS `is_pro` flag reaches frontend only via `wp_localize_script()`
- [ ] JS locking is purely visual (disabled inputs, badges, popup triggers)

---

## Common Mistakes That Caused Closure

### Mistake 1: Backend Works but UI Locks (Pattern B from closures)

WP.org reviewer tested: "despite the renderer accepts and outputs any requested
style without an Ultimate check." They check the RENDERER, not the settings UI.

Fix: If renderer works, don't lock the settings UI in PHP. Lock in JS only.

### Mistake 2: Feature Code in Free Returns Empty When Pro Absent (Pattern C)

"Plugin includes custom-trigger functionality but forcibly supplies disabled or
empty values for it." Code exists in free, returns `[]` or `false` to disable.

Fix: Remove the code from free. Or make `[]`/`false` a legitimate default that
doesn't break anything.

### Mistake 3: Popup Rendered Only When Pro Active (Pattern D)

"Reward-scheduling confirmation popup implemented but rendered only when premium
add-on is active." JS component checks `isPro` before rendering entire section.

Fix: If JS component renders pro-only UI, it should show the locked version
(disabled + upgrade badge), not hide entirely. OR remove the feature's code
from free and let Pro add it via hooks.

### Mistake 4: Settings Save Handler Skips Fields Without Pro (Pattern E)

"Settings UI disables the server-domain field and excludes it from saving."
Both UI lock + backend save skip = trialware.

Fix: Free saves all fields. Pro reads them via filters.

---

## Quick Reference: Filter Hook Naming Convention

### EchoRewards

```
ecre_{feature}_{setting}
ecre_reward_type
ecre_referral_coupon_prefix
ecre_enable_reward_delay
ecre_pre_generate_reward
ecre_after_reward_coupon_created (action)
```

### WP Dark Mode

```
wp_dark_{feature}_{setting}
wp_dark_mode_is_ultimate
wp_dark_switch_available_styles
wp_dark_image_brightness_level
wp_dark_custom_triggers_enabled
wpdm_social_share_available_channel_ids
```

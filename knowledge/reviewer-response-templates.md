# Responding to WP.org Closure Emails

Templates based on successful re-listing responses (3/9 plugins re-listed).

---

## What Worked (from successful re-listings)

### Reply Structure
```
Subject: Re: [Original Subject]

Hi WordPress Plugins Team,

Thanks for the [detailed review / follow-up review / continued review].

We've addressed the reported issues and reviewed the plugin as a whole to
make sure we haven't missed any related concerns. We've gone through the
code with Plugin Check, WPCS/PHPCS, security checks, and WordPress
development best practices. We also tested the updated version on a clean
WordPress installation with WP_DEBUG enabled.

The updated version has now been released with the necessary fixes.

Please review it when you get a chance, and let us know if anything else
needs our attention.

Best,
[Name], [Title], [Company]
```

### Key Phrases That Worked
- "reviewed the plugin as a whole" — signals comprehensive check, not point-fixes
- "Plugin Check, WPCS/PHPCS, security checks" — shows tooling was used
- "clean WordPress installation with WP_DEBUG enabled" — shows testing rigor
- "make sure we haven't missed any related concerns" — acknowledges pattern, not just examples

---

## Requesting Manual Review

After automated scanner keeps flagging resolved issues (e.g., trialware detected
in compiled JS where human reviewer would see it's fixed):

```
As we've now gone through multiple rounds of fixes and addressed the reported
concerns, we'd appreciate a manual review of the latest version. Some
implementation details may not always be fully interpreted in context by
automated checks, so a manual review at this stage would be very helpful.
```

This worked for the plugin that had 12 rounds — requested at round 9, re-listed
after round 12.

---

## Handling Cross-Plugin URL Errors

When WP.org sends review with wrong plugin URL:

```
Just a quick note: the subject of this email refers to [Plugin A], but the
plugin URL and some of the references in the report point to [Plugin B].
We've also received a separate review email for [Plugin B], so we'll continue
that discussion in that email thread.

For this plugin ([Plugin A]), we've [describe fixes].
```

---

## Anti-Patterns (What NOT to Do)

1. **Don't reply without actually fixing** — "CHANGESNOTMADE" response kills velocity
2. **Don't fix only cited examples** — WP.org explicitly says "more occurrences may exist"
3. **Don't submit without testing** — new issues in fix submission = extra round
4. **Don't ignore follow-up emails** — leads to permanent closure
5. **Don't argue with the finding** — fix it, even if you disagree
6. **Don't send multiple follow-up nudges** — one nudge after ~1 week is sufficient

---

## Timeline Expectations

| Round | Typical WP.org Response Time |
|-------|------------------------------|
| Closure → First reply | Submit fix ASAP (within 3-5 days) |
| First reply → Re-review | 1-2 weeks |
| Follow-up nudge | Wait ~1 week before nudging |
| CHANGESNOTMADE → Next fix | Submit within 2-3 days |
| 60-day deadline | Hard deadline from closure date |

---

## Checklist Before Submitting Fix

- [ ] Every issue in the closure email addressed (not just examples)
- [ ] Same issue pattern checked across ENTIRE codebase
- [ ] Plugin Check (PCP) run — zero ERRORs in "Plugin Repo" category
- [ ] PHPCS with WordPress standard — reviewed results
- [ ] WP_DEBUG enabled on clean install — no errors/warnings/notices
- [ ] Pro plugin deactivated — every free feature tested end-to-end
- [ ] All external service URLs in readme verified (not 404)
- [ ] Text domain matches plugin slug in ALL files
- [ ] ABSPATH guard in every PHP file
- [ ] No new issues introduced by fixes

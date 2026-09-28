# Week 8 Backlog — Ship

**Dates:** Oct 19 – Oct 25, 2026 · **Theme:** QA, submission, soft launch  
**Roles:** Dev A = iOS · Dev B = Backend · Source: [`../UYGULAMA_SEMASI.md`](../UYGULAMA_SEMASI.md)

**Sprint goal:** NADA MVP is bug-bashed, legally compliant, submitted to the App Store, and soft-launched via TestFlight.

**Demo (DoD):**
> “The full loop — onboarding → profile → discover → like → match → chat + voicemail → report/block — passes QA on real devices; the app is submitted to App Store review and available to soft-launch testers.”

**Depends on:** Weeks 1–7 (feature complete after Week 7).  
**Milestone:** M5 — public soft launch.

---

## Both (shared QA + release)

### W8-01 — Full QA pass (test matrix)
- **P0 · 1.5d** — Walk every flow on multiple devices/iOS versions.
- [ ] Onboarding, profile, discover, likes, match, chat, voicemail, safety
- [ ] Edge cases: offline, permission denials, empty states
- [ ] Log + triage all bugs

### W8-02 — Bug bash + fixes
- **P0 · 2d** — Fix P0/P1 bugs from W8-01 and Week 7 list.
- [ ] All P0 fixed; P1 fixed or explicitly deferred
- [ ] Regression re-test

### W8-03 — Privacy policy + KVKK/GDPR
- **P0 · 0.5d** — Publish privacy policy; data handling for photos, location, voice, gender, moderation.
- [ ] Consent + account/data deletion documented and working
- [ ] Links in app + App Store listing

### W8-04 — App Store assets + listing
- **P0 · 1d** — App icon, screenshots, description (friends-only positioning), age rating, categories.
- [ ] Assets uploaded in App Store Connect
- [ ] “Not a dating app” messaging clear

### W8-05 — Production readiness (backend)
- **P0 · 1d** — Prod environment, monitoring/alerts, backups, secrets, scaling sanity.
- [ ] Prod separate from dev; alerts on errors
- [ ] Moderation queue accessible in prod

### W8-06 — Submit + soft launch
- **P0 · 0.5d** — Submit to App Store review; open TestFlight soft-launch group.
- [ ] Build submitted
- [ ] Soft-launch testers invited
- [ ] Rollback/hotfix plan noted

---

## Day map
| Day | Focus |
|-----|-------|
| Mon | W8-01 QA pass (both) |
| Tue | W8-02 bug fixes + W8-03 privacy |
| Wed | W8-02 bug fixes + W8-04 listing |
| Thu | W8-05 prod readiness + regression |
| Fri | W8-06 submit + soft launch |

## Ship gate (launch checklist)
- [ ] All P0 bugs fixed; core loop rock-solid
- [ ] Privacy policy + data deletion live (KVKK/GDPR)
- [ ] App Store listing complete, “not dating” clear
- [ ] Production backend monitored + backed up
- [ ] Build submitted to App Store review
- [ ] Soft-launch TestFlight group live

## Post-launch (fast-follow / v1.1 candidates)
- [ ] Friend-type intent, pronouns (optional)
- [ ] Selfie verification badge
- [ ] Monetization (extra likes, boost, filters)
- [ ] Poll prompts, profile video
- [ ] Localization: ES / FR / RU / ZH

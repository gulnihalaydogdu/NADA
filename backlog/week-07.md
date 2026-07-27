# Week 7 Backlog — Polish

**Dates:** Sep 7 – Sep 13, 2026 · **Theme:** Design system, onboarding tour, hangout ideas, TR/EN  
**Roles:** Dev A = iOS · Dev B = Backend · Source: [`../UYGULAMA_SEMASI.md`](../UYGULAMA_SEMASI.md)

**Sprint goal:** The app looks and feels finished — consistent minimal design (§12 palette), a first-launch tour, hangout ideas, clean empty/error states, TR + EN, and analytics.

**Demo (DoD):**
> “A brand-new user goes through onboarding with the product tour, builds a profile, discovers, matches, chats — all with consistent styling, no broken empty states, in Turkish, with English switchable.”

**Depends on:** Weeks 1–6.  
**Milestone:** M4 — internal beta (TestFlight internal).

---

## iOS (Dev A) — lead this week

### W7-01 — Design system pass (§12 “NADA Lilac”)
- **P0 · 2d** — Centralize colors/typography/spacing tokens; apply across all screens.
- [ ] Light + dark tokens from §12 (paper `#F7F5FA`, ink `#1A1625`, brand `#B8A4DC`)
- [ ] Brand lilac only on CTAs / like / active tab / soft fills — no heavy purple gradients
- [ ] Buttons, cards, inputs, tab bar consistent; no leftover ember/teal/amber tokens

### W7-02 — First-launch product tour
- **P0 · 1d** — Short blur/highlight tour of Discover, like, match.
- [ ] Skippable; shows once
- [ ] Friendly “not dating” tone

### W7-03 — Hangout ideas
- **P0 · 1d** — Friend version of “date ideas” in match/chat (coffee, bowling, film, walk…).
- [ ] Suggestion chips insert into chat
- [ ] No “date” language

### W7-04 — Empty/error/loading states
- **P0 · 1d** — Every list/screen has calm empty + error states.
- [ ] Discover, Likes, Matches, Chat, Profile
- [ ] Retry affordances

### W7-05 — Accessibility + micro-animations
- **P1 · 0.5d** — Dynamic Type, contrast, VoiceOver labels; gentle like/match animations.

---

## Backend (Dev B)

### W7-06 — Analytics funnel + safety metrics
- **P0 · 1.5d** — Events: signup → profile complete → first like → match → first message; flirting-report rate; flagged-by-women-% count.
- [ ] Events fire reliably
- [ ] Basic dashboard/query

### W7-07 — Localization strings (TR + EN)
- **P0 · 1d** — String catalog for TR (launch) + EN; backend-driven copy where needed (prompts).
- [ ] Prompts available in TR + EN
- [ ] No hardcoded user-facing strings

### W7-08 — Hangout ideas content
- **P1 · 0.5d** — Seed hangout idea suggestions (TR + EN).

### W7-09 — Rate limits + abuse hardening
- **P1 · 1d** — Sensible like/message limits; basic anti-spam.
- [ ] Server-side caps; graceful client handling

---

## Joint

### W7-10 — Internal TestFlight + bug list
- **P0 · 0.5d (Fri)** — Ship internal TestFlight build; whole team runs full flow; log bugs for Week 8.

## Day map
| Day | Backend | iOS |
|-----|---------|-----|
| Mon | W7-06 | W7-01 |
| Tue | W7-06 + W7-07 | W7-01 + W7-02 |
| Wed | W7-07 | W7-03 |
| Thu | W7-08 + W7-09 | W7-04 |
| Fri | W7-10 | W7-05 + W7-10 |

## Ship gate
- [ ] Consistent design across all screens (light + dark)
- [ ] Product tour + hangout ideas working
- [ ] No broken empty/error states
- [ ] TR default, EN switchable
- [ ] Analytics funnel firing
- [ ] Internal TestFlight build live

## Spillover to Week 8
- [ ] …

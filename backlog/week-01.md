# Week 1 Backlog — Foundation

**Kickoff locked:** [decisions-week-01.md](decisions-week-01.md) (27 Jul 2026) — Firebase Auth + Firestore, email MVP, EN UI.  
**Run locally:** [README.md](../README.md) at repo root.

**Dates:** Jul 27 – Aug 2, 2026 · **Theme:** Auth, User, app shell, photo upload path

**Sprint goal:** A new user can sign up / sign in, complete friends-only onboarding, land in the app shell; a `User` row exists on the backend; photo upload path has a smoke test.

**Demo (Definition of Done):**  
> “New user signs in with Apple/email → friends-only onboarding → profile setup shell → backend shows User; iOS tabs are navigable.”

**Out of week 1:** Discover algorithm, likes/matches, chat, voicemail, women-% audit, report UI, App Store polish.

**Assumptions to lock on Day 1 (kickoff):**
- Auth: Apple Sign In + email (fallback: Apple-only if email slips)
- Backend: BaaS (Firebase or Supabase) preferred
- Launch UI language: pick TR or EN for stubs (copy can be placeholder)

---

## Shared / kickoff

### W1-00 — Week 1 kickoff & technical decisions
| | |
|--|--|
| **Owner** | Both |
| **Priority** | P0 |
| **Estimate** | 0.5 day |

**Tasks**
- Lock auth method and BaaS/backend choice
- Agree `User` fields for v1: `id`, `displayName`, `gender`, `city`, `createdAt`, `intent` (= friendsOnly), `locale`
- Repo layout, secrets rule, shared Notion/doc for API notes

**Acceptance criteria**
- [x] Auth + backend choice written in a short `backlog/decisions-week-01.md` note or comment at top of this file after kickoff
- [x] User field list agreed (matches schema §7 essentials)
- [x] Both devs can pull/run their side of the monorepo or linked repos

**Done (29 Jul 2026):** Decisions doc, [`docs/FIRESTORE_USERS.md`](../docs/FIRESTORE_USERS.md), root [`README.md`](../README.md).

---

## Backend (Dev B)

### W1-01 — Dev environment & project bootstrap
| | |
|--|--|
| **Owner** | Backend |
| **Priority** | P0 |
| **Estimate** | 0.5–1 day |

**Acceptance criteria**
- [x] Dev project/app created (Firebase/Supabase/custom)
- [x] Env documented (how to run locally / console URL)
- [x] No production secrets in git

**Done (29 Jul 2026):** Firebase project `nada-app-33`, [`docs/FIREBASE_SETUP.md`](../docs/FIREBASE_SETUP.md), `./scripts/check-firebase-setup.sh`, `.gitignore` for plist.

---

### W1-02 — User model + persistence
| | |
|--|--|
| **Owner** | Backend |
| **Priority** | P0 |
| **Estimate** | 1 day |

**Acceptance criteria**
- [x] User entity stores: `id`, `displayName`, `gender`, `city`, `intent`, `createdAt`, `locale` (nullable OK where needed)
- [x] `intent` defaults to / constrained as friends-only
- [x] Can create and read a user via console or API

**Done (29 Jul 2026):** `NADAUser`, `FirestoreUserService`, `firebase/firestore.rules`, schema doc [`docs/FIRESTORE_USERS.md`](../docs/FIRESTORE_USERS.md). Extra MVP fields: `email`, `friendsIntentCompleted`.

---

### W1-03 — Auth (Apple + email session)
| | |
|--|--|
| **Owner** | Backend |
| **Priority** | P0 |
| **Estimate** | 1.5–2 days |

**Acceptance criteria**
- [ ] Sign up / sign in issues a valid session (BaaS session or JWT)
- [ ] Apple Sign In verified server-side (or via BaaS provider)
- [ ] Email auth works in dev (magic link or password — pick one and document)
- [ ] Authenticated request can resolve current user id
- [ ] **Fallback:** if Apple slips, email/dev auth still unblocks iOS; Apple tracked as W1-03b spillover to Week 2 Mon AM

---

### W1-04 — `GET/PATCH /me` (or BaaS equivalent)
| | |
|--|--|
| **Owner** | Backend |
| **Priority** | P0 |
| **Estimate** | 0.5 day |

**Acceptance criteria**
- [ ] Authenticated client can fetch current profile
- [ ] Authenticated client can update `displayName`, `gender`, `city`, `intent`
- [ ] Unauthenticated requests rejected

---

### W1-05 — Photo storage smoke path
| | |
|--|--|
| **Owner** | Backend |
| **Priority** | P0 |
| **Estimate** | 0.5–1 day |

**Acceptance criteria**
- [ ] Storage bucket/path convention defined (e.g. `users/{userId}/photos/{photoId}`)
- [ ] Upload returns a URL or path stored on user/photo record
- [ ] At least one photo uploadable via API/script/curl; readable URL works
- [ ] Rules: only owner can write their folder (basic security rules)

---

### W1-06 — Prompt catalog seed
| | |
|--|--|
| **Owner** | Backend |
| **Priority** | P1 |
| **Estimate** | 0.5 day |

**Acceptance criteria**
- [x] 3–5 friend/hangout prompts seeded (English or TR — match UI language)
- [x] `GET /prompts` (or equivalent) returns active prompts
- [x] Prompt answers table/collection stub exists (write can be Week 2 if time)

**Ship notes:** Seed via Console (`firebase/prompts.seed.json`). Client: `FirestorePromptService.fetchActivePrompts`. Profile shows Bits catalog preview.

---

## iOS (Dev A)

### W1-07 — Xcode structure & design tokens
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P0 |
| **Estimate** | 0.5–1 day |

**Acceptance criteria**
- [ ] Feature folders in place (`App`, `Features`, `Core` or equivalent)
- [ ] Basic color + typography tokens (enough for welcome + auth)
- [ ] App builds on simulator

---

### W1-08 — App shell: tab bar placeholders
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P0 |
| **Estimate** | 0.5 day |

**Acceptance criteria**
- [ ] Tabs: Discover, Likes, Matches, Profile (placeholder screens OK)
- [ ] Navigation works between tabs
- [ ] Only shown after authenticated + onboarding gate (wire gate in W1-10/11)

---

### W1-09 — Welcome screen (“Not a Dating App”)
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P0 |
| **Estimate** | 0.5 day |

**Acceptance criteria**
- [ ] Friends-only positioning is clear on first launch
- [ ] CTAs: Sign up / Sign in
- [ ] No dating copy

---

### W1-10 — Sign in / Sign up UI + auth wiring
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P0 |
| **Estimate** | 1.5–2 days |

**Acceptance criteria**
- [ ] Sign in / sign up screens exist
- [ ] Wired to backend/BaaS auth from W1-03
- [ ] Session persisted; cold start restores session or returns to welcome
- [ ] Error states for failed auth (basic)
- [ ] Coordinates with Backend if Apple is delayed (dev/email path)

---

### W1-11 — Onboarding: friends intent
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P0 |
| **Estimate** | 0.5 day |

**Acceptance criteria**
- [ ] User confirms they are here for friendship / hangouts (not dating)
- [ ] Intent persisted via `/me` or onboarding endpoint
- [ ] Cannot skip into Discover without completing this step

---

### W1-12 — Profile setup wizard shell
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P1 |
| **Estimate** | 1 day |

**Acceptance criteria**
- [x] Multi-step shell: Photos → Prompts → Preferences
- [x] Steps navigable; can save partial progress where API exists
- [x] Photos step can call upload smoke path (W1-05) for at least one image **or** clearly stubbed with TODO if blocked
- [x] Prompts/Preferences can be UI-only placeholders if W1-06 is late

**Ship notes:** `ProfileSetupWizardView` after basics gate; `profileWizardCompleted` on user doc. Bits/Preferences are preview/skip until Week 2.

---

### W1-13 — API client: auth + `/me`
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P0 |
| **Estimate** | 0.5–1 day |

**Acceptance criteria**
- [ ] Shared networking/auth session helper
- [ ] Fetch and update current user works end-to-end with Backend
- [ ] Token/session attached to authenticated calls

---

## Joint (end of week)

### W1-14 — End-to-end demo & handoff notes
| | |
|--|--|
| **Owner** | Both |
| **Priority** | P0 |
| **Estimate** | 0.5 day (Fri) |

**Acceptance criteria**
- [ ] Live demo of DoD path on one simulator + backend
- [ ] Known issues / Week 2 spillover listed below
- [ ] Week 2 preview agreed: finish profile fields + start Discover feed (fake or real)

---

## Suggested day map

| Day | Backend | iOS |
|-----|---------|-----|
| Mon | W1-00 + W1-01 + start W1-02 | W1-00 + W1-07 + W1-08 |
| Tue | Finish W1-02, start W1-03 | W1-09 + start W1-10 |
| Wed | W1-03 | W1-10 + W1-13 |
| Thu | W1-04 + W1-05 | W1-11 + start W1-12 |
| Fri | W1-06 + W1-14 | Finish W1-12 + W1-14 |

---

## Week 1 checklist (ship gate)

- [ ] Auth works (Apple and/or email)
- [ ] User created on backend after sign-up
- [ ] Friends-only onboarding completed and stored
- [ ] iOS tab shell navigable when logged in
- [ ] Photo upload smoke test green (or explicit Week 2 carry with reason)
- [ ] Prompt seed readable from API
- [ ] Demo recorded or shown to product owner

---

## Spillover / carry to Week 2

_Fill on Friday:_

- [ ] …
- [ ] …

---

## Ticket status legend

| Status | Meaning |
|--------|---------|
| `todo` | Not started |
| `doing` | In progress |
| `blocked` | Waiting on other ticket/decision |
| `done` | Acceptance criteria met |
| `wont-week1` | Deferred with note |

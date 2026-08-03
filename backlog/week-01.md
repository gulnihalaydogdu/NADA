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
- [x] Sign up / sign in issues a valid session (BaaS session or JWT)
- [ ] Apple Sign In verified server-side (or via BaaS provider) — **spillover** (paid Apple Developer required)
- [x] Email auth works in dev (magic link or password — pick one and document) — email/password
- [x] Authenticated request can resolve current user id
- [x] **Fallback:** if Apple slips, email/dev auth still unblocks iOS; Apple tracked as W1-03b spillover to Week 2 Mon AM

**Done:** Firebase Auth email/password + auth state listener. Apple code ready, disabled via `NADAAuthConfig`.

---

### W1-04 — `GET/PATCH /me` (or BaaS equivalent)
| | |
|--|--|
| **Owner** | Backend |
| **Priority** | P0 |
| **Estimate** | 0.5 day |

**Acceptance criteria**
- [x] Authenticated client can fetch current profile
- [x] Authenticated client can update `displayName`, `gender`, `city`, `intent`
- [x] Unauthenticated requests rejected

**Done:** `FirestoreUserService` + owner-only Firestore rules; also `photoURL`, `friendsIntentCompleted`, `profileWizardCompleted`.

---

### W1-05 — Photo storage smoke path
| | |
|--|--|
| **Owner** | Backend |
| **Priority** | P0 |
| **Estimate** | 0.5–1 day |

**Acceptance criteria**
- [x] Storage bucket/path convention defined (e.g. `users/{userId}/photos/{photoId}`)
- [x] Upload returns a URL or path stored on user/photo record
- [x] At least one photo uploadable via API/script/curl; readable URL works
- [x] Rules: only owner can write their folder (basic security rules)

**Done:** Path `users/{uid}/photos/profile.jpg`, `FirebaseStorageService`, crop editor, `firebase/storage.rules`.

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
- [x] Feature folders in place (`App`, `Features`, `Core` or equivalent)
- [x] Basic color + typography tokens (enough for welcome + auth)
- [x] App builds on simulator

**Done:** NADA Coral tokens in `NADATheme`; feature folders under `NADA/`.

---

### W1-08 — App shell: tab bar placeholders
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P0 |
| **Estimate** | 0.5 day |

**Acceptance criteria**
- [x] Tabs: Discover, Likes, Matches, Profile (placeholder screens OK)
- [x] Navigation works between tabs
- [x] Only shown after authenticated + onboarding gate (wire gate in W1-10/11)

**Done:** `MainTabView` after friends intent + basics + profile wizard gates in `RootView`.

---

### W1-09 — Welcome screen (“Not a Dating App”)
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P0 |
| **Estimate** | 0.5 day |

**Acceptance criteria**
- [x] Friends-only positioning is clear on first launch
- [x] CTAs: Sign up / Sign in
- [x] No dating copy

**Done:** Photo hero Welcome + brand marks; English friends-only copy.

---

### W1-10 — Sign in / Sign up UI + auth wiring
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P0 |
| **Estimate** | 1.5–2 days |

**Acceptance criteria**
- [x] Sign in / sign up screens exist
- [x] Wired to backend/BaaS auth from W1-03
- [x] Session persisted; cold start restores session or returns to welcome
- [x] Error states for failed auth (basic)
- [x] Coordinates with Backend if Apple is delayed (dev/email path)

**Done:** Email path only for MVP; splash waits for session resolve.

---

### W1-11 — Onboarding: friends intent
| | |
|--|--|
| **Owner** | iOS |
| **Priority** | P0 |
| **Estimate** | 0.5 day |

**Acceptance criteria**
- [x] User confirms they are here for friendship / hangouts (not dating)
- [x] Intent persisted via `/me` or onboarding endpoint
- [x] Cannot skip into Discover without completing this step

**Done:** `FriendsIntentView` → `friendsIntentCompleted` + `intent: friendsOnly`.

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
- [x] Shared networking/auth session helper
- [x] Fetch and update current user works end-to-end with Backend
- [x] Token/session attached to authenticated calls

**Done:** `AuthManager` + Firebase Auth/Firestore/Storage services (BaaS client, not custom REST).

---

## Joint (end of week)

### W1-14 — End-to-end demo & handoff notes
| | |
|--|--|
| **Owner** | Both |
| **Priority** | P0 |
| **Estimate** | 0.5 day (Fri) |

**Acceptance criteria**
- [x] Live demo of DoD path on one simulator + backend
- [x] Known issues / Week 2 spillover listed below
- [x] Week 2 preview agreed: finish profile fields + start Discover feed (fake or real)

**Demo path (verified on device/simulator + Firebase `nada-app-33`, 2–3 Aug 2026)**

1. Cold launch → Welcome (photo hero, Not a Dating App)
2. Sign up with email/password → Auth session + `users/{uid}` created
3. Friends Intent → Continue → `friendsIntentCompleted: true`
4. Basics gate → name + gender + city required → saved on user doc
5. Profile wizard shell → Photos (crop + Storage upload) → Bits peek → Preferences preview → Finish/Skip → `profileWizardCompleted: true`
6. Main tabs → Discover / Likes / Matches (placeholders) + Profile hub
7. Profile → avatar crop/upload → `photoURL`; Bits sheet loads seeded `prompts`; Edit / Location save work

**Firebase one-time Console checks for demo**
- Firestore Rules published (`users`, `prompts` read, `promptAnswers` stub) — `firebase/firestore.rules`
- Storage Rules published — `firebase/storage.rules`
- Bits seed: collection `prompts` from `firebase/prompts.seed.json` (`isActive` = boolean)

**Week 2 preview (agreed)**
- Finish profile depth: up to 6 photos, answer ≥3 Bits, hangout interests, city + radiusKm
- Then start Discover feed (nearby profiles; ranking can stay simple / fake-first if needed)
- See [`week-02.md`](week-02.md)

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

- [x] Auth works (Apple and/or email) — **email only**; Apple spillover
- [x] User created on backend after sign-up
- [x] Friends-only onboarding completed and stored
- [x] iOS tab shell navigable when logged in
- [x] Photo upload smoke test green (or explicit Week 2 carry with reason)
- [x] Prompt seed readable from API
- [x] Demo recorded or shown to product owner — path exercised live; formal recording optional

---

## Spillover / carry to Week 2

- [ ] **Apple Sign In** — code ready (`NADAAuthConfig`); blocked until paid Apple Developer Program. Enable capability + Firebase Apple provider when enrolled. *(was W1-03b)*
- [ ] **Multi-photo gallery (up to 6)** — Week 1 stores a single `profile.jpg` + `photoURL`. Original uncropped asset not kept (re-edit limited to already-cropped square).
- [ ] **Bit answers (write path)** — catalog + `promptAnswers` rules stub only; pick/answer/save ≥3 in Week 2.
- [ ] **Hangout interests + radiusKm persistence** — UI preview only in wizard / Profile sheets.
- [ ] **My Profile polish** — hide completion meter at 100%; serif/sans type pairing; hangout-first **Preview** layout (photo ↔ Bits ↔ “We could…”), not dating-style beauty ranking.
- [ ] **Discover / Likes / Matches** — still placeholder tabs (Week 3 core loop; Week 2 may start feed).

---

## Ticket status legend

| Status | Meaning |
|--------|---------|
| `todo` | Not started |
| `doing` | In progress |
| `blocked` | Waiting on other ticket/decision |
| `done` | Acceptance criteria met |
| `wont-week1` | Deferred with note |

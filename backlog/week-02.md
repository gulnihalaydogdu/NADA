# Week 2 Backlog — Profile & Prompts

**Dates:** Aug 3 – Aug 9, 2026 · **Theme:** Complete profile setup  
**Roles:** Dev A = iOS · Dev B = Backend · Source: [`../UYGULAMA_SEMASI.md`](../UYGULAMA_SEMASI.md)

**Sprint goal:** A user finishes a full friends-only profile — photos, prompts, gender, location, preferences — and can edit it.

**Demo (DoD):**
> “New user adds up to 6 photos, answers 3 prompts, sets gender + city/radius, saves preferences, and re-opens the app to see a complete, editable profile.”

**Depends on:** Week 1 (auth, User, `/me`, photo upload path).  
**W1 spillover in:** [`week-01.md`](week-01.md) → Spillover / carry to Week 2 (Apple Sign In, multi-photo, Bit answers, interests/radius, Preview polish).

---

## Backend (Dev B)

### W2-01 — Photo API (multi-photo, ordered)
- **P0 · 1d** — CRUD for up to 6 photos, sortOrder, primary flag; owner-only writes.
- [x] Add/remove/reorder photos; primary photo settable
- [x] Signed URLs / readable paths returned
- [x] Max 6 enforced server-side

**Ship notes:** Subcollection `users/{uid}/photos/{photoId}` + Storage `{photoId}.jpg`. Denormalized `photoURL` = primary. Lazy migration from W1 single `photoURL`. Client enforces max 6 (`FirestorePhotoService`). Photos sheet: multi-select, sequential 1:1 crop, drag-to-reorder (slot 0 = primary), ✕ delete with mandatory replacement.

### W2-02 — Prompt catalog (friend-coded)
- **P0 · 1d** — 15–20 hangout/hobby/humour prompts seeded; `GET /prompts`.
- [x] Prompts stored with category (hangout, hobby, games/memes, new-in-town, energy)
- [x] Only active prompts returned
- [x] No dating-style prompts

**Ship notes:** `firebase/prompts.seed.json` has 28 EN friend-coded prompts. Re-seed Console (client cannot write `prompts`).

### W2-03 — Prompt answers API
- **P0 · 1d** — Create/update/delete a user’s prompt answers (min 3).
- [x] Answer text length limit enforced
- [x] Ordered answers per user
- [x] Validation: at least 3 to complete profile

**Ship notes:** `promptAnswers/{userId}_{promptId}`; max 3 answers; text 1…150 chars. `FirestorePromptService` + `AuthManager` helpers. Wizard Continues only at 3 answers; Profile meter uses live count.

### W2-04 — Gender + location on User
- **P0 · 1d** — Persist gender (required), city, radiusKm, coarse coordinates.
- [x] Gender required to complete profile (for women-% audit later)
- [x] City + radius stored; no precise pin
- [x] `PATCH /me` extended

**Ship notes:** Gender/city on basics gate. `radiusKm` + optional coarse `approxLatitude`/`approxLongitude` on `users/{uid}` via `updateLocation`. Separate Preferences entity still W2-05.

### W2-05 — Preferences entity
- **P1 · 0.5d** — Discovery prefs: radiusKm, city, intent=friendsOnly.
- [x] 1–1 with User; sensible defaults
- [x] Readable/updatable

**Ship notes:** Collection `preferences/{uid}` (`UserPreferences` + `FirestorePreferencesService`). Defaults: `radiusKm=25`, `intent=friendsOnly`, `showMe=everyone`. Hydrate on sign-in; location / basics city sync mirrors onto prefs; `AuthManager.updatePreferences` for W2-11. Rules + [`docs/FIRESTORE_PREFERENCES.md`](../docs/FIRESTORE_PREFERENCES.md).

### W2-06 — Profile completeness flag
- **P1 · 0.5d** — Compute `isProfileComplete` (photos≥1, answers≥3, gender, city).
- [x] Exposed on `/me`
- [ ] Used by iOS to gate Discover (Week 3)

**Ship notes:** `users/{uid}.isProfileComplete` + `ProfileCompleteness` + `AuthManager.isProfileComplete`. Synced on sign-in hydrate and after basics / location / photos / bits mutations. Discover tab gate is Week 3; flag is ready to read via `auth.isProfileComplete`.

---

## iOS (Dev A)

### W2-07 — Photo gallery step
- **P0 · 1.5d** — Add/reorder/remove up to 6 photos; pick from library/camera.
- [x] Uses W2-01 + upload path; primary photo selectable
- [x] Empty + loading + error states

**Ship notes:** Profile Photos sheet + setup wizard both use `ProfilePhotosEditor`. Wizard requires all 6 before Continue; first slot = primary (gold frame); drag reorder; ✕ replaces same slot.

### W2-08 — Prompts step
- **P0 · 1.5d** — Browse prompt catalog, pick, and write answers (min 3).
- [x] Category browsing; “view all”
- [x] Enforces min 3 answers to continue
- [x] Edit an existing answer

**Ship notes:** `ProfileBitsSheet` + wizard Bits step share `BitsAnswersWorkspace`. Preview shows answered Bits.

### W2-09 — Gender + basics step
- **P0 · 0.5d** — Gender selection (man / woman / non-binary), name, birth date (18+).
- [x] Friendly copy, “not dating” tone
- [x] 18+ validation

**Ship notes:** Basics gate + Edit Profile collect `dateOfBirth` (Firestore timestamp). Client enforces 18+ (`ProfileAge`); picker max = today−18y. Preview essentials shows derived age. Existing users without DOB are re-gated to basics.

### W2-10 — Location step
- **P0 · 0.5d** — City + radius; request location permission (approximate).
- [x] Manual city entry + optional auto-detect
- [x] Radius slider (km)

**Ship notes:** Profile Location sheet saves city + radius; “Use approximate location” (When-In-Use, reduced accuracy, reverse-geocode). Wizard Preferences Finish also persists radius. Skip does not save radius.

### W2-11 — Preferences screen
- **P1 · 0.5d** — Review/edit discovery prefs.
- [ ] Reads/writes W2-05

### W2-12 — My profile + edit
- **P1 · 1d** — View own complete profile; deep-link into edit steps.
- [ ] Reflects all data; edits persist
- [ ] Reuses setup step screens

---

## Joint

### W2-13 — E2E profile demo + Week 3 prep
- **P0 · 0.5d (Fri)** — Full profile round-trip; confirm `isProfileComplete`; agree Discover data shape.

## Day map
| Day | Backend | iOS |
|-----|---------|-----|
| Mon | W2-01 | W2-07 |
| Tue | W2-02 + W2-03 | W2-08 |
| Wed | W2-04 | W2-09 + W2-10 |
| Thu | W2-05 + W2-06 | W2-11 + start W2-12 |
| Fri | W2-13 | Finish W2-12 + W2-13 |

## Ship gate
- [x] Up to 6 photos upload, reorder, primary works
- [x] ≥3 prompt answers saved and shown
- [x] Gender + city/radius saved
- [ ] Profile editable after relaunch
- [ ] `isProfileComplete` correct

## Spillover to Week 3
- [ ] Profile essentials card on Discover / Preview: age · gender · city + job, university, hangout looking-for (see `UYGULAMA_SEMASI.md` §7)
- [ ] Collect `jobTitle`, `university`, `hangoutLookingFor` in setup/edit (no sexuality field for now)
- [ ] Optional later: `openToGroups` chip
- [ ] …

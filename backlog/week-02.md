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
- [ ] Add/remove/reorder photos; primary photo settable
- [ ] Signed URLs / readable paths returned
- [ ] Max 6 enforced server-side

### W2-02 — Prompt catalog (friend-coded)
- **P0 · 1d** — 15–20 hangout/hobby/humour prompts seeded; `GET /prompts`.
- [ ] Prompts stored with category (hangout, hobby, games/memes, new-in-town, energy)
- [ ] Only active prompts returned
- [ ] No dating-style prompts

### W2-03 — Prompt answers API
- **P0 · 1d** — Create/update/delete a user’s prompt answers (min 3).
- [ ] Answer text length limit enforced
- [ ] Ordered answers per user
- [ ] Validation: at least 3 to complete profile

### W2-04 — Gender + location on User
- **P0 · 1d** — Persist gender (required), city, radiusKm, coarse coordinates.
- [ ] Gender required to complete profile (for women-% audit later)
- [ ] City + radius stored; no precise pin
- [ ] `PATCH /me` extended

### W2-05 — Preferences entity
- **P1 · 0.5d** — Discovery prefs: radiusKm, city, intent=friendsOnly.
- [ ] 1–1 with User; sensible defaults
- [ ] Readable/updatable

### W2-06 — Profile completeness flag
- **P1 · 0.5d** — Compute `isProfileComplete` (photos≥1, answers≥3, gender, city).
- [ ] Exposed on `/me`
- [ ] Used by iOS to gate Discover (Week 3)

---

## iOS (Dev A)

### W2-07 — Photo gallery step
- **P0 · 1.5d** — Add/reorder/remove up to 6 photos; pick from library/camera.
- [ ] Uses W2-01 + upload path; primary photo selectable
- [ ] Empty + loading + error states

### W2-08 — Prompts step
- **P0 · 1.5d** — Browse prompt catalog, pick, and write answers (min 3).
- [ ] Category browsing; “view all”
- [ ] Enforces min 3 answers to continue
- [ ] Edit an existing answer

### W2-09 — Gender + basics step
- **P0 · 0.5d** — Gender selection (man / woman / non-binary), name, birth date (18+).
- [ ] Friendly copy, “not dating” tone
- [ ] 18+ validation

### W2-10 — Location step
- **P0 · 0.5d** — City + radius; request location permission (approximate).
- [ ] Manual city entry + optional auto-detect
- [ ] Radius slider (km)

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
- [ ] Up to 6 photos upload, reorder, primary works
- [ ] ≥3 prompt answers saved and shown
- [ ] Gender + city/radius saved
- [ ] Profile editable after relaunch
- [ ] `isProfileComplete` correct

## Spillover to Week 3
- [ ] …

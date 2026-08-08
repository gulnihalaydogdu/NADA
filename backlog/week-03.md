# Week 3 Backlog — Discover

**Dates:** Aug 10 – Aug 16, 2026 · **Theme:** Discovery + like/skip  
**Roles:** Dev A = iOS · Dev B = Backend · Source: [`../UYGULAMA_SEMASI.md`](../UYGULAMA_SEMASI.md)

**Sprint goal:** A user browses nearby profiles one at a time, likes a profile or a specific prompt/photo (with comment), skips, and can undo a skip.

**Demo (DoD):**
> “User opens Discover, sees a nearby profile, likes a prompt with a comment, skips the next, taps undo to bring it back, and keeps browsing without duplicates.”

**Depends on:** Week 2 (complete profiles), APNs setup started this week for Week 4.

---

## Backend (Dev B)

### W3-01 — Discovery feed API
- **P0 · 2d** — Return candidate profiles by city/radius, excluding self, blocked, already-seen.
- [x] Filter by location + `isProfileComplete`
- [ ] Exclude already-liked/skipped and blocked users
- [x] Simple ranking: distance + recent activity
- [x] Pagination / batching

**Ship notes (in progress):** `DiscoverCandidate` + `DiscoverFeedPage`; `FirestoreDiscoverService.fetchCandidates`
filters complete profiles by viewer prefs (gender / age / city or Haversine radius), hydrates photos +
Bits + buddyTypes, ranks by distance. `excludedUserIds` stub for likes/skips/blocks (W3-02–04).
Rules: signed-in read of complete `users`, photos, `promptAnswers`, `preferences` — **publish**
`firebase/firestore.rules`. Doc: [`docs/FIRESTORE_DISCOVER.md`](../docs/FIRESTORE_DISCOVER.md).

### W3-02 — Like API (profile + prompt/photo, with comment)
- **P0 · 1.5d** — Create like with targetType (profile/prompt/photo), targetId, optional comment.
- [ ] Comment length validated
- [ ] Prevent duplicate likes
- [ ] Records for match check (Week 4)

### W3-03 — Skip + Undo API
- **P0 · 1d** — Record skip; undo removes last skip so profile can resurface.
- [ ] Skips excluded from feed
- [ ] Undo restores previous candidate

### W3-04 — Seen/interaction tracking
- **P1 · 0.5d** — Track shown profiles to avoid repeats; feed dedupe.
- [ ] Consistent ordering across sessions

### W3-05 — APNs setup (prep for Week 4)
- **P1 · 0.5d** — Push certificates/keys + device token registration endpoint.
- [ ] Token stored per user; test push delivered

---

## iOS (Dev A)

### W3-06 — Discover feed UI
- **P0 · 2d** — One profile at a time: photos + prompt answers, minimal layout (§12 design).
- [x] Smooth scroll through a profile
- [x] Loads next from W3-01; empty state (“no one nearby yet”)

**Ship notes (in progress):** `DiscoverFeedView` — Preview-aligned stack (name → photo → Bit →
essentials → interleaved). Temporary “Next profile” until W3-08 skip. Empty + loading + error
states. Incomplete profiles see a finish-profile gate (W3-10 lite).

### W3-07 — Like interactions
- **P0 · 1.5d** — Like whole profile; like a prompt/photo with optional comment.
- [ ] Like glow animation (coral brand `#C17B6F`)
- [ ] Comment sheet; sends via W3-02

### W3-08 — Skip + undo
- **P0 · 1d** — Skip (X) with animation; undo returns to previous profile.
- [ ] Undo button; unlimited/generous cap
- [ ] Matches W3-03

### W3-09 — Device token registration
- **P1 · 0.5d** — Register APNs token after permission (already asked in onboarding).
- [ ] Sends token to W3-05

### W3-10 — Discover gating
- **P1 · 0.5d** — Only enter Discover if `isProfileComplete`; else nudge to finish profile.
- [x] Gate + nudge in `DiscoverFeedView` (Profile tab to finish; deep-link later)

---

## Joint

### W3-11 — E2E discover demo + Week 4 prep
- **P0 · 0.5d (Fri)** — Two test users browse each other; confirm like records ready for match logic.

## Day map
| Day | Backend | iOS |
|-----|---------|-----|
| Mon | W3-01 | W3-06 |
| Tue | W3-01 + W3-02 | W3-06 + W3-07 |
| Wed | W3-02 + W3-03 | W3-07 + W3-08 |
| Thu | W3-04 + W3-05 | W3-08 + W3-09 |
| Fri | W3-11 | W3-10 + W3-11 |

## Ship gate
- [ ] Nearby profiles load without repeats
- [ ] Like (profile + prompt/photo + comment) works
- [ ] Skip + undo works
- [ ] Blocked/seen users excluded
- [ ] APNs test push received

## Spillover to Week 4
- [ ] …

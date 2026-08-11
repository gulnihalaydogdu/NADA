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
- **P0 · 2d** — Return candidate profiles by city/radius, excluding self + already liked/skipped.
- [x] Filter by location + `isProfileComplete`
- [x] Exclude already-liked / skipped users *(blocked → Week 5; already-seen → W3-04)*
- [x] Simple ranking: nearer first (name tie-break)
- [x] Pagination / batching

**Ship notes:** **Done.** `DiscoverCandidate` + `DiscoverFeedPage`; `FirestoreDiscoverService.fetchCandidates`
filters complete profiles by viewer prefs (gender / age / city or Haversine radius), hydrates photos +
Bits + buddyTypes, ranks by distance. `fetchDiscoverPage` unions liked + skipped ids into
`excludedUserIds` (`extraExcludedUserIds` ready for blocks later). Rules: signed-in read of complete
`users`, photos, `promptAnswers`, `preferences` — **publish** `firebase/firestore.rules`. Doc:
[`docs/FIRESTORE_DISCOVER.md`](../docs/FIRESTORE_DISCOVER.md).

### W3-02 — Like API (profile + prompt/photo, with comment)
- **P0 · 1.5d** — Create like with targetType (profile/prompt/photo), targetId, optional comment.
- [x] Comment length validated
- [x] Prevent duplicate likes
- [x] Records for match check (Week 4)

**Ship notes:** Collection `likes/{from_to_type_target}`; max comment 200; duplicate doc id = no-op.
`FirestoreLikeService` + `AuthManager.likeDiscoverTarget`. Doc: [`docs/FIRESTORE_LIKES.md`](../docs/FIRESTORE_LIKES.md).

### W3-03 — Skip + Undo API
- **P0 · 1d** — Record skip; undo removes last skip so profile can resurface.
- [x] Skips excluded from feed
- [x] Undo restores previous candidate

**Ship notes:** Collection `skips/{from_to}`; `FirestoreSkipService` + undo by `toUserId`.
Doc: [`docs/FIRESTORE_SKIPS.md`](../docs/FIRESTORE_SKIPS.md). May need composite index
`fromUserId` + `createdAt` for “undo latest” helper.

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

**Ship notes:** `DiscoverFeedView` — Preview-aligned stack (name → photo → Bit →
essentials → interleaved). Temporary “Next profile” until W3-08 skip. Empty + loading + error
states. Incomplete profiles see a finish-profile gate (W3-10 lite).

**Verification (8 Aug):** Two complete accounts — candidates appear on Discover for each other.

**Polish backlog (later):** Discover photo-load transition — short branded loading animation while
primary photo warms (today: plain ProgressView + wait-for-primary so name/Bits don’t flash first).
Also tighten like/skip card transitions when W3-07/08 land.

### W3-07 — Like interactions
- **P0 · 1.5d** — Like whole profile; like a prompt/photo with optional comment.
- [x] Like glow animation (coral brand `#C17B6F`)
- [x] Comment sheet; sends via W3-02

**Ship notes:** Discover action bar heart + Bit heart overlay → comment sheet → advances feed.
Photo-target like UI can land with richer photo chrome later (API already supports `.photo`).

### W3-08 — Skip + undo
- **P0 · 1d** — Skip (X) with animation; undo returns to previous profile.
- [x] Undo button; unlimited/generous cap
- [x] Matches W3-03

**Ship notes:** Skip / Undo buttons on Discover; last skipped card restored from memory after
Firestore delete.

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
- [x] Nearby profiles load without repeats *(liked + skipped excluded; block later)*
- [x] Like (profile + prompt/photo + comment) works *(photo UI optional; API ready)*
- [x] Skip + undo works
- [ ] Blocked/seen users excluded
- [ ] APNs test push received

## Spillover to Week 4
- [ ] …

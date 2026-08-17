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
- [x] Exclude already-liked/skipped and blocked users
- [x] Simple ranking: distance + recent activity
- [x] Pagination / batching

### W3-02 — Like API (profile + prompt/photo, with comment)
- **P0 · 1.5d** — Create like with targetType (profile/prompt/photo), targetId, optional comment.
- [x] Comment length validated
- [x] Prevent duplicate likes
- [x] Records for match check (Week 4)

**Ship notes:** `likes/{from}_{to}_{type}_{target}`; comment max 200; existing doc is returned (no duplicate). Collection is ready for incoming/sent queries in W4-01.

### W3-03 — Skip + Undo API
- **P0 · 1d** — Record skip; undo removes last skip so profile can resurface.
- [x] Skips excluded from feed
- [x] Undo restores previous candidate

**Ship notes:** `skips/{from}_{to}`; feed excludes outgoing skips; undo deletes the skip doc. UI undo stack cap 10 (W3-08).

### W3-04 — Seen/interaction tracking
- **P1 · 0.5d** — Track shown profiles to avoid repeats; feed dedupe.
- [x] Consistent ordering across sessions

**Ship notes:** `discoverSeen/{from}_{to}` on card show. Rank: nearer, then `lastActiveAt`. Empty-pool recycle of seen cards is intentional for two-account testing; likes/skips/blocks stay hidden.

### W3-05 — APNs setup (prep for Week 4)
- **P1 · 0.5d** — Push certificates/keys + device token registration endpoint.
- [x] Token stored per user
- [ ] Test push delivered — **spillover** (paid Apple Developer APNs `.p8` + Firebase Cloud Messaging key)

**Ship notes:** Owner-only `users/{uid}/deviceTokens/{sha256}`. Docs: [`docs/FIRESTORE_DEVICE_TOKENS.md`](../docs/FIRESTORE_DEVICE_TOKENS.md). Live banner waits on the same paid-account gate as Sign in with Apple.

---

## iOS (Dev A)

### W3-06 — Discover feed UI
- **P0 · 2d** — One profile at a time: photos + prompt answers, minimal layout (§12 design).
- [x] Smooth scroll through a profile
- [x] Loads next from W3-01; empty state (“no one nearby yet”)

### W3-07 — Like interactions
- **P0 · 1.5d** — Like whole profile; like a prompt/photo with optional comment.
- [x] Like glow animation (coral brand `#C17B6F`)
- [x] Comment sheet; sends via W3-02

**Ship notes:** Profile / Bit / photo hearts; optional comment sheet; coral glow ~0.42s then next card.

### W3-08 — Skip + undo
- **P0 · 1d** — Skip (X) with animation; undo returns to previous profile.
- [x] Undo button; unlimited/generous cap
- [x] Matches W3-03

**Ship notes:** Skip X burst + card slide; undo stack of last **10** skips; each undo deletes the W3-03 skip doc.

### W3-09 — Device token registration
- **P1 · 0.5d** — Register APNs token after permission (already asked in onboarding).
- [x] Sends token to W3-05

**Ship notes:** Not asked in onboarding. After splash, Enable / Skip card at most **twice per install**; iOS alert only on Turn on. Skip does not nag. Already-authorized devices register silently.

### W3-10 — Discover gating
- **P1 · 0.5d** — Only enter Discover if `isProfileComplete`; else nudge to finish profile.
- [x] Incomplete profiles see a finish-profile gate instead of the feed

---

## Joint

### W3-11 — E2E discover demo + Week 4 prep
- **P0 · 0.5d (Fri)** — Two test users browse each other; confirm like records ready for match logic.
- [x] Two complete profiles in the same city see each other on Discover
- [x] Like (profile / Bit / photo + comment), skip, undo exercised
- [x] `likes` / `skips` docs exist for Week 4 match + inbox

**Verification (17 Aug):** Feed, like glow, photo like, skip animation, undo stack, interest overlap, and FCM token registration path exercised on device/simulator. Live APNs banner still blocked on paid Apple key.

## Day map
| Day | Backend | iOS |
|-----|---------|-----|
| Mon | W3-01 | W3-06 |
| Tue | W3-01 + W3-02 | W3-06 + W3-07 |
| Wed | W3-02 + W3-03 | W3-07 + W3-08 |
| Thu | W3-04 + W3-05 | W3-08 + W3-09 |
| Fri | W3-11 | W3-10 + W3-11 |

## Ship gate
- [x] Nearby profiles load without repeats
- [x] Like (profile + prompt/photo + comment) works
- [x] Skip + undo works
- [x] Blocked/seen users excluded
- [ ] APNs test push received — spillover (paid Apple APNs key)

## Spillover to Week 4
- [ ] **Live APNs send** — token registration is in; need paid Developer + `.p8` in Firebase Cloud Messaging before W4-03/W4-08 can deliver
- [ ] **Apple Sign In** — still blocked on paid Developer (W1-03b)
- [ ] **Likes inbox + Matches tab** — placeholders; this is Week 4 core
- [ ] Optional later: `openToGroups` chip


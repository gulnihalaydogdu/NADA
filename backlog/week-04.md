# Week 4 Backlog — Likes & Match

**Dates:** Aug 17 – Aug 23, 2026 · **Theme:** Likes inbox + mutual match  
**Roles:** Dev A = iOS · Dev B = Backend · Source: [`../UYGULAMA_SEMASI.md`](../UYGULAMA_SEMASI.md)

**Sprint goal:** Users see who liked them, form mutual matches, and get push notifications for likes and matches.

**Demo (DoD):**
> “User A likes User B. B sees A in their Likes inbox and gets a push. B likes back → both see a Match and get a match notification.”

**Depends on:** Week 3 (likes, feed, APNs token path).  
**Carry-in from Week 3:** live APNs send still needs paid Apple `.p8`; Apple Sign In still blocked; Likes/Matches UI is this week.

**Milestone:** M2 — core loop (Discover → like → match) complete.

---

## Backend (Dev B)

### W4-01 — Incoming/sent likes API
- **P0 · 1d** — List likes received and sent, with the liked target + comment.
- [x] Incoming likes for current user (paginated)
- [x] Sent likes list
- [x] Excludes blocked users

**Ship notes:** `AuthManager.fetchIncomingLikes` / `fetchSentLikes` → `LikeInboxPage`. Hydrates other user + Bit/photo target. Composite indexes in `firebase/firestore.indexes.json`. UI is W4-05.

### W4-02 — Match creation on mutual like
- **P0 · 1.5d** — When both like, create a Match; idempotent.
- [ ] Detect mutual like reliably
- [ ] One Match per pair; store createdAt
- [ ] Expose match list

### W4-03 — Match + likes notifications
- **P0 · 1d** — Push on new match and (optionally) new like via APNs.
- [ ] Match push to both users
- [ ] New-like push (respect quiet settings)

### W4-04 — Unmatch endpoint (prep for Week 5)
- **P1 · 0.5d** — Unmatch hides match + chat.
- [ ] Sets unmatchedAt; hidden from both

---

## iOS (Dev A)

### W4-05 — Likes inbox UI
- **P0 · 1.5d** — Browse incoming likes (who liked you + on what), like back or skip.
- [x] Shows liked prompt/photo + comment
- [x] Like back triggers match flow
- [x] Empty state

**Ship notes:** `LikesInboxView` replaces the Likes placeholder tab. Rows show avatar, "liked your photo/Bit/profile", relative time, the liked Bit or photo thumbnail, and the comment. Tapping a row opens that person's full Discover-style profile; **All** (top right) returns to the list. Like back opens the same optional-note sheet as Discover, then writes a profile like (Match object lands in W4-02); Pass writes a skip. Both remove the row and return to the list. Tab bar badge = unique pending likers (live listener). Pull to refresh + cursor paging; thumbnails prefetched at 120pt.

### W4-06 — Sent likes view
- **P1 · 0.5d** — See outgoing likes and their status.
- [x] Sent tab in the Likes segment with "Waiting to hear back" status

### W4-07 — Match screen + Matches list
- **P0 · 1.5d** — Celebratory match screen; Matches tab list.
- [ ] Match animation (success color)
- [ ] Matches list sorted by recent
- [ ] Entry point to chat (chat itself in Week 5)

### W4-08 — Push handling
- **P0 · 1d** — Handle match/like pushes; deep-link to Likes/Matches.
- [ ] Foreground + background handling
- [ ] Tapping opens right screen

---

## Joint

### W4-09 — E2E match demo + Week 5 prep
- **P0 · 0.5d (Fri)** — Two devices go like → match → push; confirm chat unlock contract.

## Day map
| Day | Backend | iOS |
|-----|---------|-----|
| Mon | W4-01 | W4-05 |
| Tue | W4-02 | W4-05 + W4-06 |
| Wed | W4-02 + W4-03 | W4-07 |
| Thu | W4-03 + W4-04 | W4-07 + W4-08 |
| Fri | W4-09 | W4-08 + W4-09 |

## Ship gate
- [x] Incoming likes visible with context
- [ ] Mutual like creates exactly one Match
- [ ] Match + like pushes delivered and deep-link correctly
- [ ] Matches list populated

## Spillover to Week 5
- [ ] …

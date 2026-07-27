# Week 5 Backlog — Chat & Safety

**Dates:** Aug 24 – Aug 30, 2026 · **Theme:** Text chat + report/block  
**Roles:** Dev A = iOS · Dev B = Backend · Source: [`../UYGULAMA_SEMASI.md`](../UYGULAMA_SEMASI.md)

**Sprint goal:** Matched users can chat (text) with push notifications, and anyone can report/block/unmatch — with **Flirting** as a report reason.

**Demo (DoD):**
> “Matched users exchange messages with delivery + push. One reports the other for Flirting and blocks them; the blocked user disappears from Discover and the chat closes.”

**Depends on:** Week 4 (matches, push, unmatch).

---

## Backend (Dev B)

### W5-01 — Messaging API
- **P0 · 2d** — Send/list messages within a match; ordering, read receipts.
- [ ] Only match participants can post/read
- [ ] Pagination; createdAt ordering
- [ ] readAt updates

### W5-02 — New-message push
- **P0 · 0.5d** — Push on new message (respect mute).
- [ ] Delivered; deep-links to thread

### W5-03 — Report API (reasons incl. Flirting)
- **P0 · 1d** — Report a user with reason + details; stored with status.
- [ ] Reasons: Flirting, harassment, fake profile, spam, other
- [ ] Feeds moderation (Week 6)

### W5-04 — Block API
- **P0 · 1d** — Block implies unmatch + mutual hide from Discover.
- [ ] Removes from each other’s feed/likes/matches
- [ ] Chat closed

### W5-05 — “Your turn” state (anti double-text)
- **P1 · 0.5d** — Track whose turn / who opened; expose to iOS.
- [ ] Flag when it’s the user’s turn to open

---

## iOS (Dev A)

### W5-06 — Chat thread UI
- **P0 · 2d** — Message list + composer; delivery/read indicators; verification/active badges.
- [ ] Reference liked prompt as icebreaker context
- [ ] Empty state; scroll + send

### W5-07 — Chat push handling
- **P0 · 0.5d** — Open thread from push.

### W5-08 — Report flow
- **P0 · 1d** — Report sheet with reasons incl. **Flirting** + optional details.
- [ ] Confirmation; calls W5-03

### W5-09 — Block + unmatch flow
- **P0 · 1d** — Block/unmatch from profile or chat; confirmations.
- [ ] Updates lists; calls W5-04

### W5-10 — “Your turn” nudge
- **P1 · 0.5d** — Gentle prompt so users aren’t pressured to double-text.

---

## Joint

### W5-11 — E2E chat + safety demo
- **P0 · 0.5d (Fri)** — Chat between two users; report + block verified end to end.

## Day map
| Day | Backend | iOS |
|-----|---------|-----|
| Mon | W5-01 | W5-06 |
| Tue | W5-01 + W5-02 | W5-06 + W5-07 |
| Wed | W5-03 | W5-08 |
| Thu | W5-04 + W5-05 | W5-09 |
| Fri | W5-11 | W5-10 + W5-11 |

## Ship gate
- [ ] Text chat works with push
- [ ] Report (incl. Flirting) stored
- [ ] Block → unmatch + mutual hide works
- [ ] Only match participants access a thread

## Spillover to Week 6
- [ ] …

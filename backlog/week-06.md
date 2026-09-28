# Week 6 Backlog — Voice & Audit

**Dates:** Oct 5 – Oct 11, 2026 · **Theme:** Voicemail + women-% safety audit  
**Roles:** Dev A = iOS · Dev B = Backend · Source: [`../UYGULAMA_SEMASI.md`](../UYGULAMA_SEMASI.md)

**Sprint goal:** Matched users can send async voicemail (no video call), and the backend computes men’s women-% among connections and flags skewed accounts for an ops moderation queue.

**Demo (DoD):**
> “User records and sends a 30s voicemail in a match; recipient plays it. Backend computes women-% for a test man and, above threshold, flags him in the moderation queue where an admin can warn/limit/ban.”

**Depends on:** Week 5 (chat, reports).  
**Milestone:** M3 — talk & stay safe.

---

## Backend (Dev B)

### W6-01 — Voice message API + storage
- **P0 · 1.5d** — Upload/store audio; return playable URL; store durationSec.
- [ ] Only match participants; max duration enforced (e.g. 60s)
- [ ] listenedAt tracking
- [ ] No video/live-call surface

### W6-02 — Voicemail push
- **P0 · 0.5d** — Push on new voicemail (like new message).

### W6-03 — ConnectionStats job (women-%)
- **P0 · 1.5d** — Compute womenShareAmongLikes/Matches per user with sample size.
- [ ] Scheduled/triggered recompute
- [ ] Handle non-binary / prefer-not-to-say sensibly (documented rule)
- [ ] Store computedAt + sampleSize

### W6-04 — Flagging + thresholds
- **P0 · 0.5d** — Flag accounts above threshold with min sample size.
- [ ] Configurable threshold
- [ ] flaggedForReview set; combined with report signals

### W6-05 — Ops moderation queue (minimal)
- **P0 · 1.5d** — Internal list of reports + flagged users; actions warn/limit/ban.
- [ ] Auth-gated admin view (simple)
- [ ] Actions update moderationStatus (limit likes / restrict Discover / ban)

---

## iOS (Dev A)

### W6-06 — Voicemail recorder
- **P0 · 1.5d** — Record/preview/send voice; mic permission flow.
- [ ] Permission request + “enable mic” fallback
- [ ] Duration cap; re-record; cancel

### W6-07 — Voicemail playback in chat
- **P0 · 1d** — Inline player; played/unplayed state.
- [ ] Waveform or simple play button
- [ ] Marks listenedAt

### W6-08 — Voicemail on profile (optional prompt)
- **P1 · 0.5d** — Optional skippable voice prompt on profile (from setup).
- [ ] Skippable; consistent with Week 2 profile

### W6-09 — Restricted-account UX
- **P1 · 0.5d** — Handle limited/banned states gracefully (messaging, gates).
- [ ] Clear, non-hostile copy

---

## Joint

### W6-10 — E2E voice + audit demo
- **P0 · 0.5d (Fri)** — Voicemail round-trip; trigger a flag; action it in the ops queue.

## Day map
| Day | Backend | iOS |
|-----|---------|-----|
| Mon | W6-01 | W6-06 |
| Tue | W6-01 + W6-02 | W6-06 + W6-07 |
| Wed | W6-03 | W6-07 + W6-08 |
| Thu | W6-04 + W6-05 | W6-09 |
| Fri | W6-05 + W6-10 | W6-10 |

## Ship gate
- [ ] Voicemail send + playback works; no video call anywhere
- [ ] Mic permission handled
- [ ] women-% computed with sample size + threshold flag
- [ ] Ops queue shows reports + flags; warn/limit/ban works

## Spillover to Week 7
- [ ] …

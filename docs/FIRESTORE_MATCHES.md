# Firestore — matches (W4-02)

Create **one** Match when two people have liked each other (any target: profile / Bit / photo). List is for W4-07; chat unlock is Week 5.

**Code:** `NADA/Core/Models/NADAMatch.swift`, `FirestoreMatchService`  
**Auth:** `AuthManager.likeDiscoverTarget` (creates the match) / `fetchMatches` / `unmatch`  
**Rules:** `firebase/firestore.rules` — **Publish** the `matches` block  
**Indexes:** `firebase/firestore.indexes.json`

---

## When a match is created

After every like, the client (and the `onLikeCreated` function) check for a reverse like. If one exists and the pair is not blocked, they write `matches/{minUid_maxUid}`.

- A liking B’s photo and B liking A’s Bit still counts.
- Creating the same pair again returns the existing doc (id is sorted uids).
- `likeDiscoverTarget` returns `DiscoverLikeOutcome` so W4-07 can open a match screen when `match != nil`.
- Sign-in runs `repairMutualMatches()` so pairs that liked each other *before* this shipped still get a doc.
- Blocked pairs are not written; `fetchMatches` also drops them.
- Unmatch (W4-04) stamps `unmatchedAt`. The same pair is not rewritten; rematch is Week 5.

---

## `matches/{matchId}`

| Field | Type | Notes |
|-------|------|--------|
| *(document id)* | string | `min(uidA, uidB)_max(uidA, uidB)` |
| `userAId` | string | Lexicographically smaller uid |
| `userBId` | string | The other uid |
| `userIds` | `[string]` | `[userAId, userBId]` — query with `array-contains` |
| `createdAt` | timestamp | Server timestamp |
| `unmatchedAt` | timestamp? | Set once by a participant (W4-04). Omitting it means active. |

---

## List

`AuthManager.fetchMatches()` → `MatchListPage`

- Filter: `userIds array-contains me`
- Order: `createdAt` desc
- Rules: `request.auth.uid in resource.data.userIds` (must match that query; `userAId` / `userBId` OR is not enough for `list`)
- Drops rows with `unmatchedAt`
- Hydrates the other person as `LikePartySummary` (name + photos, no email)

---

## Unmatch (W4-04)

`AuthManager.unmatch(matchId:)`

- Participant-only `update` that sets `unmatchedAt` to the server time
- Other match fields stay frozen (`create` still cannot overwrite an existing doc)
- Both people stop seeing the row in `fetchMatches`
- Idempotent if already unmatched
- Chat hide uses the same stamp in Week 5

From Mutuals: long-press a row → **Remove from Mutuals**.

---

## Indexes

1. `likes`: `fromUserId` Asc + `toUserId` Asc (reverse-like check)
2. `matches`: `userIds` Arrays + `createdAt` Desc

Also keep the W4-01 inbox indexes (`toUserId`/`fromUserId` + `createdAt`).

---

## Verify

1. Publish rules + create the new indexes.
2. User A likes B (any target). No `matches` doc yet.
3. User B likes A. One `matches/{sortedA_sortedB}` doc with both uids and `createdAt`.
4. B likes A again on another photo → still **one** match.
5. As A or B: `fetchMatches()` returns that row with the other person’s name.
6. A long-presses B in Mutuals → Remove. Doc has `unmatchedAt`. Both lists hide B/A.

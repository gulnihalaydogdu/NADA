# Firestore — `skips/{skipId}` (W3-03)

Discover skips. Document id = `{fromUserId}_{toUserId}`.

**Code:** `NADA/Core/Models/DiscoverInteraction.swift`,
`NADA/Core/Firestore/FirestoreSkipService.swift`  
**Rules:** owner (fromUserId) read/write/delete only.

---

## Fields

| Field | Type | Required | Notes |
|-------|------|----------|--------|
| *(document id)* | string | yes | `{from}_{to}` |
| `fromUserId` | string | yes | Auth uid |
| `toUserId` | string | yes | Skipped profile |
| `createdAt` | timestamp | yes | Server timestamp (refreshed on re-skip) |

---

## Lifecycle

1. Discover → Skip → `createSkip`.
2. Feed exclusion: skipped `toUserId`s in `excludedUserIds`.
3. Undo → delete latest skip by `createdAt` desc (or delete by known `toUserId`).
4. Composite index may be required: `fromUserId` ASC + `createdAt` DESC (Console link on first query).

---

## Verify

1. Publish rules (skips block).
2. Skip someone → gone from feed after reload.
3. Undo → profile can return; skip doc deleted.

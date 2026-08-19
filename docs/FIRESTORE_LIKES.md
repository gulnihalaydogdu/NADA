# Firestore — likes inbox (W4-01)

List likes **received** and **sent**, with the liked target + comment. Match creation is [`FIRESTORE_MATCHES.md`](FIRESTORE_MATCHES.md) (W4-02).

**Code:** `NADA/Core/Models/LikeInbox.swift`, `FirestoreLikeService.fetchInbox`  
**Auth:** `AuthManager.fetchIncomingLikes` / `fetchSentLikes`  
**UI:** `NADA/Features/Likes/LikesInboxView.swift` (incoming only — sent likes are not shown)  
**Indexes:** `firebase/firestore.indexes.json` — create in Console (or follow the error link on first query)

---

## Query

| Direction | Filter | Order |
|-----------|--------|--------|
| Incoming | `toUserId == me` | `createdAt` desc |
| Sent | `fromUserId == me` | `createdAt` desc |

Page size **20**. Cursor = last examined like document id. Up to 3 batches to fill a page after block filtering.

Blocked users (either direction in `blocks`) are dropped. Missing / nameless other-user docs are dropped.

**Incoming also drops people the viewer already answered** — anyone in the viewer's `likes` (mutual → Matches) or `skips` (passed).

**Sent list is not shown in the app.** Outgoing likes stay private (no waiting / rejected / name). A like-back opens Matches. `fetchSentLikes` still exists for the API.

---

## `InboxLike`

| Field | Notes |
|-------|--------|
| `like` | `fromUserId`, `toUserId`, `targetType`, `targetId`, `comment?`, `createdAt` |
| `otherUser` | Incoming: sender. Sent: recipient. `displayName` + primary photo URLs. No email. |
| `target` | `profile` / `prompt` / `photo` plus Bit text+answer or photo URLs when still present |

Content always belongs to **`toUserId`** (the person who was liked).

---

## Indexes (required)

Composite, collection `likes`:

1. `toUserId` Asc + `createdAt` Desc  
2. `fromUserId` Asc + `createdAt` Desc  
3. `fromUserId` Asc + `toUserId` Asc (reverse-like / match check) 

Firebase Console → Firestore → **Indexes**. First failed query also prints a create-index URL in Xcode.

---

## Verify

1. User A likes B (profile / Bit / photo, optional comment).
2. As B: `fetchIncomingLikes()` includes A, the target, and the comment.
3. As A: `fetchSentLikes()` includes the same row.
4. A blocked pair does not appear on either side.
5. Likes tab as B: row shows A, the liked Bit/photo, the comment. Tap the row → A's full profile; **All** returns to the list. **Pass** or **Like back** removes it and it stays gone after pull-to-refresh.
6. B’s Likes tab icon shows a badge with unique pending likers (A liking three things still counts as 1). Badge drops after Pass / Like back; a new like from C raises it without opening the tab.

# Firestore — chat messages (W5-01)

Text chat for an **active** mutual. Voicemail is Week 6. Push on new message is W5-02 (`onMessageCreated`).

**Code:** `NADA/Core/Models/ChatMessage.swift`, `FirestoreChatService`  
**Auth:** `AuthManager.sendChatMessage` / `fetchChatMessages` / `listenChatMessages` / `markChatRead`  
**UI:** `ChatThreadView` from Mutuals (W5-06)  
**Rules:** `firebase/firestore.rules` — **Publish** the `matches/{id}/messages` block

---

## Path

`matches/{matchId}/messages/{messageId}`

| Field | Type | Notes |
|-------|------|--------|
| `senderId` | string | Must be the signed-in participant |
| `body` | string | 1…1000 characters |
| `createdAt` | timestamp | Server timestamp |
| `readAt` | timestamp? | Set once by the other person |

List: `createdAt` desc, page size 40. Single-field `createdAt` is enough (query is scoped to one match).

**Opening messages:** the optional note on **Say hi** (and a Discover click comment) is copied into this collection as `opening_{likeId}` when the pair becomes mutuals, so it shows as the first bubble in Mutuals chat.

---

## Rules

- Get/list: match participant
- Create: participant, match has no `unmatchedAt`, `senderId == auth.uid`
- Update: only `readAt`, only on someone else’s unread message
- Delete: denied

---

## Verify

1. Publish rules.
2. A and B are mutuals. A taps B in Mutuals.
3. A sends a line → B’s open thread (or refresh) shows it.
4. B opening the thread stamps `readAt` on A’s messages. A sees **Seen** on their last bubble.
5. After unmatch, new sends fail; Mutuals no longer lists the pair.

# Firestore — `likes/{likeId}` (W3-02)

Outgoing Discover likes. Document id =
`{fromUserId}_{toUserId}_{targetType}_{targetId}` (duplicate-safe).

**Code:** `NADA/Core/Models/DiscoverInteraction.swift`,
`NADA/Core/Firestore/FirestoreLikeService.swift`  
**Rules:** sender can create/read own likes; recipient can read likes where `toUserId == auth.uid`
(for Likes inbox in a later ticket). `get` on a missing doc is allowed when signed in
(so duplicate-check before create does not permission-fail).

---

## Fields

| Field | Type | Required | Notes |
|-------|------|----------|--------|
| *(document id)* | string | yes | Composite key above |
| `fromUserId` | string | yes | Auth uid of liker |
| `toUserId` | string | yes | Profile owner |
| `targetType` | string | yes | `profile` / `prompt` / `photo` |
| `targetId` | string | yes | For profile: `toUserId`; else promptId / photoId |
| `comment` | string | no | Trimmed; max **200** chars |
| `createdAt` | timestamp | yes | Server timestamp |

---

## Lifecycle

1. Discover → like profile / Bit / photo → `createLike` (existing doc = no-op).
2. Feed exclusion: all `toUserId` values for `fromUserId == me` are passed as `excludedUserIds`.
3. Week 4: mutual like → Match (not in this ticket).

---

## Verify

1. Publish `firebase/firestore.rules` (likes block).
2. Like a profile from Discover → Console `likes` doc appears.
3. Reload Discover → liked user no longer in the feed.
4. Duplicate like does not create a second doc.

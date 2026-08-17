# Firestore — Discover feed (W3-01)

Client-side discovery: `FirestoreDiscoverService` queries complete users and
assembles `DiscoverCandidate` cards.

**Code:** `NADA/Core/Models/DiscoverCandidate.swift`,
`NADA/Core/Firestore/FirestoreDiscoverService.swift`  
**Auth:** `AuthManager.fetchDiscoverFeed` / `recordDiscoverSeen`  
**Rules:** `firebase/firestore.rules` — **Publish** so signed-in users can read
other **complete** profiles, their photos, Bits, and so the feed can list likes /
skips / seen / blocks.

---

## Feed shape

| Type | Role |
|------|------|
| `DiscoverCandidate` | id, displayName, age, gender, city, job/uni/looking-for, interestIds, photos, bits, distanceKm, lastActiveAt |
| `DiscoverBit` | promptId + promptText + answerText + sortOrder |
| `DiscoverFeedPage` | `candidates` + opaque `cursor` |

Never included: email, full `dateOfBirth` (age only), precise GPS.

---

## Query + filters

1. Firestore: `users` where `isProfileComplete == true`, ordered by document id, **batch 40**.
   Scan up to **12 batches** until `pageSize` (default **10**) is filled.
2. Skip **self**.
3. Skip ids from:
   - `likes` (outgoing `toUserId` — people you liked)
   - `likes` (incoming `fromUserId` — people who liked you; they live in the Likes inbox)
   - `skips` (outgoing `toUserId`)
   - `discoverSeen` (already shown)
   - `blocks` (either direction)
4. Match viewer `preferences`:
   - `lookingForGenders` ↔ candidate `gender`
   - `minAge`…`maxAge` ↔ derived age
   - Location: **same normalized city** always matches; else Haversine ≤ `radiusKm`
5. Hydrate photos (subcollection, else legacy `photoURL`) + Bits (`promptAnswers` + catalog).
6. Rank: **nearer first**, then **more recently active** (`lastActiveAt` / `createdAt`).
7. Cursor = last examined user doc id.

Viewer `lastActiveAt` is touched on each feed fetch.

---

## Exclusion collections

| Collection | Doc id | Used for |
|------------|--------|----------|
| `likes/{from}_{to}_{type}_{target}` | W3-02 writes; feed hides outgoing *and* incoming (inbox) |
| `skips/{from}_{to}` | W3-03 writes; feed reads outgoing targets |
| `discoverSeen/{from}_{to}` | `recordSeen` when a card is shown |
| `blocks/{blocker}_{blocked}` | Week 5 writes; feed excludes both directions |

Empty collections / unpublished rules fail open (no extra exclusions) so the feed still loads.

---

## Rules (Discover)

| Path | Read | Write |
|------|------|-------|
| `users/{uid}` | Owner, or any auth if `isProfileComplete` | Owner |
| `users/{uid}/photos/{id}` | Any auth | Owner |
| `preferences/{uid}` | Any auth | Owner |
| `promptAnswers/{id}` | Any auth | Owner |
| `likes` / `skips` / `discoverSeen` / `blocks` | Parties as in rules file | Owner create |

**Note:** Complete user docs still contain `email`. The app must not surface it on Discover.

---

## Verify

1. Publish `firebase/firestore.rules`.
2. Two complete test users in the same city (or within radius with approx coords).
3. Call `fetchDiscoverFeed()` as user A → see B, not A, not incomplete users.
4. Change A’s looking-for gender / age range → B drops in or out.
5. If Firestore asks for a composite index, create it from the error link.
6. Already-seen cards recycle when nobody else is left (likes/skips/blocks still stay hidden).
7. If A likes B, B’s Discover must not show A — A belongs on B’s Likes tab.

Discover **UI** is W3-06 — this drop is the API + rules only.

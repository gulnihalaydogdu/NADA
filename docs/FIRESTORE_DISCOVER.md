# Firestore — Discover feed (W3-01)

Client-side discovery: `FirestoreDiscoverService` queries complete users and
assembles `DiscoverCandidate` cards for the Discover tab.

**Code:** `NADA/Core/Models/DiscoverCandidate.swift`,
`NADA/Core/Firestore/FirestoreDiscoverService.swift`  
**Rules:** `firebase/firestore.rules` — publish after pull so signed-in users can
read other **complete** profiles, their photos, Bits, and preferences (buddyTypes).

---

## Feed shape

| Type | Role |
|------|------|
| `DiscoverCandidate` | One card: id, displayName, age, gender, city, photos, bits, buddyTypes, distanceKm |
| `DiscoverBit` | promptId + promptText + answerText + sortOrder |
| `DiscoverFeedPage` | `candidates` + opaque `cursor` for the next page |

Never included: email, full `dateOfBirth` (age only), precise GPS.

---

## Query + filters

1. Firestore: `users` where `isProfileComplete == true`, ordered by document id, batch 40 —
   **keep scanning batches** (up to 12) until `pageSize` matches or the collection is exhausted.
2. Skip self + `excludedUserIds` (likes / skips / blocks — empty until W3-02–04).
3. Match viewer `preferences`:
   - `lookingForGenders` ↔ candidate `gender`
   - `minAge`…`maxAge` ↔ derived age
   - Location: **same normalized city always matches** (İstanbul/Istanbul folded); else Haversine ≤ `radiusKm`
4. Hydrate photos (subcollection, else legacy `photoURL`), Bits (`promptAnswers` + catalog),
   buddyTypes from `preferences` (**display only** — never used to filter the feed).
5. Rank: nearer first, then display name.
6. Return up to `pageSize` (default 10) + cursor = last examined doc id.

---

## Rules (Discover)

| Path | Read | Write |
|------|------|-------|
| `users/{uid}` | Owner, or any auth if `isProfileComplete` | Owner |
| `users/{uid}/photos/{id}` | Any auth | Owner |
| `preferences/{uid}` | Any auth | Owner |
| `promptAnswers/{id}` | Any auth | Owner |

**Note:** Complete user docs still contain `email`. The app must not surface it on Discover.
A public-profile split is a later hardening step.

---

## Verify

1. Publish updated `firebase/firestore.rules`.
2. Two complete test users in the same city (or within radius with approx coords).
3. Call `fetchCandidates(viewer:prefs:)` as user A → see B, not A, not incomplete users.
4. Change A’s `lookingForGenders` / age range → B drops in or out as expected.
5. Console → Firestore may prompt for a composite index if the query fails; create it from the error link.

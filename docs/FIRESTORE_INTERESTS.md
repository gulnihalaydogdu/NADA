# Firestore — Interest badges (`interests`) — Week 2 spillover

User-facing name: **Interests**. Catalog collection: `interests/{id}`.  
Selections live on **`users/{uid}.interestIds`** (string array, max 8) so Week 3 Discover can query overlap with `array-contains-any`.

**Code:** `NADA/Core/Models/Interest.swift`, `NADA/Core/Firestore/FirestoreInterestService.swift`  
**Seed:** `firebase/interests.seed.json`  
**Rules:** `firebase/firestore.rules` (authenticated read; client writes forbidden)

---

## `interests/{interestId}` fields

| Field | Type | Notes |
|-------|------|--------|
| *(document id)* | string | Stable slug, e.g. `coffee-runs` |
| `label` | string | English chip text (no emoji) |
| `category` | string | `lifestyle` / `tvMovies` / `music` / `games` / `foodDrink` / `sportsOutdoors` / `creative` / `goingOut` |
| `isActive` | boolean | Only `true` returned by fetch |
| `sortOrder` | number | Ascending display order |
| `locale` | string | MVP: `"en"` |

## `users/{uid}.interestIds`

| Field | Type | Notes |
|-------|------|--------|
| `interestIds` | array&lt;string&gt; | Catalog ids; **max 8**; order = pick order |

Not required for `isProfileComplete` / Discover. They add a small slice of the Profile completeness meter (together with job / university / hangout looking-for, the last 10%). Empty array is allowed.

---

## Seed

From the repo root:

```bash
npm install
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/serviceAccount.json"
npm run seed:interests
```

Or with gcloud ADC:

```bash
gcloud auth application-default login
export GCLOUD_PROJECT=nada-app-33
npm run seed:interests
```

This **merges** docs from `firebase/interests.seed.json` into `interests/{id}`.

Also **Publish** `firebase/firestore.rules` so the `interests` read rule is live.

---

## Client

`FirestoreInterestService.fetchActiveInterests(locale: "en")`  
→ active + `locale == en`, sorted by `sortOrder`.

`AuthManager.updateInterestIds` writes `users/{uid}.interestIds`.

Surfaces: wizard step between Bits and Preferences · Profile → Interests · Preview block under essentials.

Week 3 Discover “you both like…” is not in this drop.

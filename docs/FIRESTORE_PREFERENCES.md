# Firestore — `preferences/{userId}` (W2-05 / W2-11)

Discovery preferences entity, **1–1 with User**. Document ID **must** equal Auth `uid`.

**Code:** `NADA/Core/Models/UserPreferences.swift`, `NADA/Core/Firestore/FirestorePreferencesService.swift`  
**Rules:** `firebase/firestore.rules` (owner read/write only) — **Publish in Console** or the app shows `Missing or insufficient permissions`.

City + `radiusKm` are also mirrored on `users/{uid}`. Preferences is the discovery source of truth after hydrate.

---

## Fields

| Field | Type | Required | Notes |
|-------|------|----------|--------|
| *(document id)* | string | yes | Same as Auth uid |
| `userId` | string | yes | Same as document id |
| `city` | string | no† | Seeded from basics / preferences save |
| `radiusKm` | number | yes | 5…80 step 5; default **25** |
| `intent` | string | yes | Always `"friendsOnly"` (not edited in UI) |
| `lookingForGenders` | string | yes | `women` / `men` / `nonBinary` / `everyone` |
| `minAge` | number | yes | 18…99; default **18** |
| `maxAge` | number | yes | 18…99; default **45** |
| `buddyTypes` | array&lt;string&gt; | yes | Display-only on Discover cards (not a feed filter). `travelBuddy`, `hangoutBuddy`, `bestFriend`, `gameBuddy`, `openToAll` |
| `updatedAt` | timestamp | yes | Server timestamp on write |

† Required when calling `updatePreferences`.

Legacy `showMe` is removed on write (migrated to `lookingForGenders`).

---

## Lifecycle

1. **Sign-in hydrate** → `ensurePreferences(for:)` creates the doc from user city/radius (or defaults) if missing. Prefs failure must **not** wipe the user profile (Friends Intent gate).
2. **Basics save** → `syncCity` updates `preferences.city` (keeps filters).
3. **Wizard Finish / Preferences sheet** → full `updatePreferences` + user city/radius mirror.
4. **Approximate location** → optional coarse lat/lng on `users/{uid}` only.

---

## Verify

1. Publish updated `firebase/firestore.rules` (preferences match block).
2. Run app → sign in → Console → `preferences` → `{uid}` exists.
3. Profile → Discover preferences → save filters → doc updates; red permissions error gone.
4. Relaunch → Friends Intent poster must **not** reappear.

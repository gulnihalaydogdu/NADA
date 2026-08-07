# Firestore — `preferences/{userId}` (W2-05)

Discovery preferences entity, **1–1 with User**. Document ID **must** equal Auth `uid`.

**Code:** `NADA/Core/Models/UserPreferences.swift`, `NADA/Core/Firestore/FirestorePreferencesService.swift`  
**Rules:** `firebase/firestore.rules` (owner read/write only)

City + `radiusKm` are also mirrored on `users/{uid}` (basics gate, legacy readers, Discover queries later). Preferences is the discovery source of truth after hydrate.

---

## Fields

| Field | Type | Required | Notes |
|-------|------|----------|--------|
| *(document id)* | string | yes | Same as Auth uid |
| `userId` | string | yes | Same as document id |
| `city` | string | no† | Seeded from basics / location save |
| `radiusKm` | number | yes | 5…80 step 5; default **25** |
| `intent` | string | yes | Always `"friendsOnly"` for MVP |
| `showMe` | string | yes | `"everyone"` for MVP (Week 3 Discover) |
| `updatedAt` | timestamp | yes | Server timestamp on write |

† Created empty on first ensure if user has no city yet; required when calling `updatePreferences` / location save.

---

## Lifecycle

1. **Sign-in hydrate** → `ensurePreferences(for:)` creates the doc from user city/radius (or defaults) if missing.
2. **Basics save** → `syncCity` updates `preferences.city` (keeps existing radius).
3. **Location / Preferences Finish** → `updatePreferences` + `users/{uid}` location mirror.
4. **W2-11 Preferences screen** → `AuthManager.updatePreferences` / `currentPreferences`.

---

## Example

```json
{
  "userId": "abc123",
  "city": "Istanbul",
  "radiusKm": 25,
  "intent": "friendsOnly",
  "showMe": "everyone",
  "updatedAt": "<timestamp>"
}
```

---

## Verify

1. Publish updated `firebase/firestore.rules` (preferences match block).
2. Run app → sign in → Console → `preferences` → `{uid}` exists with defaults.
3. Profile → Location → save city + radius → prefs doc updates; `users/{uid}.radiusKm` matches.
4. Basics city change → `preferences.city` matches.

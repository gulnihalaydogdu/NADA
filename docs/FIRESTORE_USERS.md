# Firestore — `users/{uid}` (W1-02)

MVP user profile document. Document ID **must** equal Firebase Auth `uid`.

**Code:** `NADA/Core/Models/NADAUser.swift`, `NADA/Core/Firestore/FirestoreUserService.swift`  
**Rules:** `firebase/firestore.rules` (owner read/write only)

---

## Fields

| Field | Type | Required on create | Notes |
|-------|------|-------------------|--------|
| *(document id)* | string | yes | Same as Auth uid |
| `intent` | string | yes | Always `"friendsOnly"` for MVP |
| `friendsIntentCompleted` | boolean | yes | `false` until Friends intent screen |
| `locale` | string | yes | e.g. `"en_TR"` from device |
| `createdAt` | timestamp | yes | `FieldValue.serverTimestamp()` |
| `email` | string | no | From Auth on sign-up if available |
| `displayName` | string | no | From Auth / Apple profile if available |
| `gender` | string | no | Set in profile wizard (Week 2) |
| `city` | string | no | Set in profile wizard (Week 2) |

---

## Lifecycle

1. **Sign up / sign in** → `FirestoreUserService.ensureUserDocument` creates doc if missing.
2. **Friends intent** → `setFriendsIntentCompleted` sets `friendsIntentCompleted: true`, reaffirms `intent`.
3. **Profile edit** → `updateProfile` patches `displayName`, `gender`, `city`, `locale` (W1-04 wire in UI pending).

---

## Example document (after onboarding)

```json
{
  "intent": "friendsOnly",
  "friendsIntentCompleted": true,
  "locale": "en_TR",
  "createdAt": "<timestamp>",
  "email": "user@example.com",
  "displayName": null,
  "gender": null,
  "city": null
}
```

---

## Verify

1. `./scripts/check-firebase-setup.sh`
2. Run app → sign up with email/password
3. Firebase Console → Firestore → `users` → `{uid}` matches table above
4. Complete friends intent → `friendsIntentCompleted` becomes `true`

---

## Out of scope (later weeks)

Full product `User` entity in `UYGULAMA_SEMASI.md` §7 adds `birthYear`, `bio`, `moderationStatus`, etc. Those are **not** in Firestore until profile/discover work lands.

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
| `displayName` | string | no† | Required before tabs (basic profile gate) |
| `gender` | string | no† | `woman` / `man` / `nonBinary` / `preferNotToSay` |
| `city` | string | no† | Required before tabs |
| `photoURL` | string | no | Download URL from Storage after profile photo upload (W1-05) |
| `profileWizardCompleted` | boolean | yes | `false` until Photos → Bits → Preferences shell finishes or is skipped (W1-12) |

† Created empty on sign-up; **Basic Profile** gate requires them before the profile wizard / tabs.

---

## Lifecycle

1. **Sign up / sign in** → `FirestoreUserService.ensureUserDocument` creates doc if missing.
2. **Friends intent** → `setFriendsIntentCompleted` sets `friendsIntentCompleted: true`, reaffirms `intent`.
3. **Profile basics (required)** → `updateProfile` sets `displayName`, `gender`, `city`.
4. **Profile wizard shell (skippable)** → Photos (Storage) → Bits (catalog peek) → Preferences (preview) → `profileWizardCompleted: true`.
5. **Profile photo** → also available anytime from Profile tab.
6. **Profile edit** → basics updated later from Profile → Edit profile.

---

## Storage — profile photos (W1-05)

**Bucket:** `gs://nada-app-33.firebasestorage.app` (or plist project bucket)  
**Path:** `users/{uid}/photos/profile.jpg`  
**Rules:** repo `firebase/storage.rules` — paste in Console → Storage → Rules → **Publish**

| Rule | Meaning |
|------|---------|
| `read` | Any signed-in user |
| `write` | Owner only (`auth.uid == userId`), image/*, &lt; 5MB |

**Code:** `NADA/Core/Storage/FirebaseStorageService.swift` → `AuthManager.uploadProfilePhoto` → Profile tab PhotosPicker.

---

## Example document (after onboarding)

```json
{
  "intent": "friendsOnly",
  "friendsIntentCompleted": true,
  "locale": "en_TR",
  "createdAt": "<timestamp>",
  "email": "user@example.com",
  "displayName": "Gül",
  "gender": "woman",
  "city": "Istanbul",
  "photoURL": "https://firebasestorage.googleapis.com/..."
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

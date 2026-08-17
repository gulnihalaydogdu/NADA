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
| `dateOfBirth` | timestamp | no† | Required before tabs; enforces 18+; UI shows derived age only |
| `radiusKm` | number | no | Discover radius 5…80 (step 5); mirrored from `preferences/{uid}` (W2-05) |
| `approxLatitude` | number | no | Coarse (~2 decimals); set via “Use approximate location” |
| `approxLongitude` | number | no | Coarse (~2 decimals); never a precise pin |
| `photoURL` | string | no | Denormalized primary photo download URL (W1-05 / W2-01) |
| `photoThumbnailURL` | string | no | Denormalized primary thumbnail for avatars (Week 3 image pipeline) |
| `profileWizardCompleted` | boolean | yes | `false` until Photos → Bits → Preferences shell finishes or is skipped (W1-12) |
| `isProfileComplete` | boolean | yes | Discover gate (W2-06): photos≥1, bits≥3, gender, city. Recomputed client-side on hydrate / profile edits |

† Created empty on sign-up; **Basic Profile** gate requires them before the profile wizard / tabs.

### Planned profile essentials (not in Firestore yet)

Discover/profile card fields — implement later (do not treat as shipped):

| Field | Type | UI |
|-------|------|-----|
| `jobTitle` | string | e.g. Student |
| `university` | string | Last / current school |
| `hangoutLookingFor` | string | Short hangout intent line |
| `openToGroups` | boolean | Optional later |

**Shipped with W2-09:** `dateOfBirth` (age on Preview essentials card).

**Out of MVP for now:** sexuality / orientation (dating-coded; revisit only with clear friends framing).

---

## Lifecycle

1. **Sign up / sign in** → `FirestoreUserService.ensureUserDocument` creates doc if missing.
2. **Friends intent** → `setFriendsIntentCompleted` sets `friendsIntentCompleted: true`, reaffirms `intent`.
3. **Profile basics (required)** → `updateProfile` sets `displayName`, `gender`, `city`, `dateOfBirth` (18+).
4. **Profile wizard shell (skippable)** → Photos → Bits → Preferences (`radiusKm` saved on Finish) → `profileWizardCompleted: true`.
5. **Location sheet** → `updateLocation` sets `city`, `radiusKm`, optional coarse lat/lng; mirrors discovery fields onto [`preferences/{uid}`](FIRESTORE_PREFERENCES.md) (W2-05).
6. **Profile photos (W2-01)** → up to 6 ordered docs under `photos`; primary mirrored on `photoURL`.
7. **Profile edit** → basics updated later from Profile → Edit profile.

---

## Storage — profile photos (W1-05 → W2-01)

**Bucket:** `gs://nada-app-33.firebasestorage.app` (or plist project bucket)  
**Path:** `users/{uid}/photos/{photoId}.jpg`  
**Legacy W1 path:** `users/{uid}/photos/profile.jpg` (still readable; lazy-migrated into the subcollection)  
**Rules:** repo `firebase/storage.rules` — paste in Console → Storage → Rules → **Publish**

| Rule | Meaning |
|------|---------|
| `read` | Any signed-in user |
| `write` | Owner only (`auth.uid == userId`), image/*, &lt; 5MB |

**Code:** `FirebaseStorageService` + `FirestorePhotoService` → Profile Photos sheet / avatar.

---

## `users/{uid}/photos/{photoId}` (W2-01)

| Field | Type | Notes |
|-------|------|--------|
| *(document id)* | string | UUID (or `legacy-primary` after migration) |
| `url` | string | Storage download URL (display, max 1200px, WebP or JPEG) |
| `thumbnailURL` | string | no | Small derivative (max 360px) for avatars / grids. Missing on legacy photos |
| `sortOrder` | number | `0…5`, packed after deletes |
| `isPrimary` | boolean | Exactly one should be true when count ≥ 1 |
| `createdAt` | timestamp | Server timestamp on create |

Storage objects: `users/{uid}/photos/{photoId}.{jpg\|webp}` and `{photoId}_thumb.{jpg\|webp}` with `Cache-Control: public, max-age=31536000, immutable`.  
Client decodes at display size (ImageIO thumbnail) off the main thread, max 3 decodes at once, and keeps a bounded memory + disk cache (`NADA/Core/Images`).  
Full-size tiles paint the thumbnail first, then swap in the display file — no spinner, no blank space.

**Max 6** enforced in `FirestorePhotoService` before upload.  
**Lazy migration:** if the subcollection is empty but `users/{uid}.photoURL` is set, the first `fetchPhotos` creates `legacy-primary` without re-uploading.

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
  "photoURL": "https://firebasestorage.googleapis.com/...",
  "profileWizardCompleted": true,
  "isProfileComplete": true
}
```

---

## Verify

1. `./scripts/check-firebase-setup.sh`
2. Run app → sign up with email/password
3. Firebase Console → Firestore → `users` → `{uid}` matches table above
4. Complete friends intent → `friendsIntentCompleted` becomes `true`
5. Profile → Photos → add up to 6; set primary; delete → `photos` subcollection + `photoURL` stay in sync

---

## Out of scope (later weeks)

Full product `User` entity in `UYGULAMA_SEMASI.md` §7 adds `birthYear`, `bio`, `moderationStatus`, etc. Those are **not** in Firestore until profile/discover work lands.

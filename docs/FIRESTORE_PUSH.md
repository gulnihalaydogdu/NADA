# Firestore — like & match push (W4-03)

FCM to stored device tokens when someone likes you, or when a Match is created.

**Code:** `firebase/functions/index.js`  
**Tokens:** [`FIRESTORE_DEVICE_TOKENS.md`](FIRESTORE_DEVICE_TOKENS.md)  
**Match docs:** [`FIRESTORE_MATCHES.md`](FIRESTORE_MATCHES.md)  
**iOS handling / deep links:** W4-08

Live banners still need a paid Apple APNs `.p8` in Firebase Cloud Messaging (same gate as Sign in with Apple). Functions can be deployed before that; sends will fail until the key is uploaded.

---

## Triggers

| Event | Recipients | Skip |
|-------|------------|------|
| `likes/{id}` created | `toUserId` | Reverse like already exists (function writes the match; match push covers it). `preferences.notifyOnLikes == false`. No device tokens. |
| `matches/{id}` created | both `userAId` and `userBId` | No device tokens |

Like payload: title **New click**, body `{name} clicked you`, data `{ type: like, fromUserId }`.  
Match payload: title **You're mutuals**, body `You and {name} clicked`, data `{ type: match, matchId }`.

---

## Quiet settings

`preferences/{uid}.notifyOnLikes` (bool, default **true** if missing). Turns off **like** pushes only. Match pushes still send if the device has a token. Skipping the iOS permission prompt means no token → no push.

---

## Deploy

From the repo root (Firebase CLI, project `nada-app-33`):

```bash
cd firebase/functions && npm install
firebase deploy --only functions,firestore:rules,firestore:indexes
```

Blaze (pay-as-you-go) is required for Cloud Functions.

---

## Verify

1. Deploy functions. Tokens exist on both test accounts (`users/{uid}/deviceTokens`).
2. A likes B (B has not liked A) → B gets **New click** (after APNs key).
3. B sets `notifyOnLikes: false` → A's next like does not notify B.
4. B likes A → both get **You're mutuals**; no extra click banner for the click-back.
5. Until the APNs `.p8` is in Firebase, Functions logs show send attempts but the phone stays quiet.

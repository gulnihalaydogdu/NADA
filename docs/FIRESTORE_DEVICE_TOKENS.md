# Firestore — device tokens (W3-05 / W3-09)

FCM registration tokens for APNs. Week 4 sends like / match pushes to these docs.

**Code:** `FirestoreDeviceTokenService`, `DevicePushRegistrar`, `NADAAppDelegate`  
**Rules:** `firebase/firestore.rules` — **Publish** the `deviceTokens` block.

Do **not** store tokens on `users/{uid}`. Complete profiles are readable for Discover.

---

## `users/{uid}/deviceTokens/{tokenId}`

| Field | Type | Notes |
|-------|------|--------|
| *(document id)* | string | SHA-256 hex of the FCM token |
| `fcmToken` | string | Firebase Cloud Messaging token |
| `platform` | string | MVP: `"ios"` |
| `updatedAt` | timestamp | Server timestamp on upsert |

One doc per device. Token refresh replaces the previous doc for that device.

---

## Client flow

1. User lands on the main tabs → system notification permission.
2. If allowed, register for remote notifications (APNs).
3. FCM maps the APNs token → `fcmToken`.
4. Upsert this subcollection. Sign-out deletes the current device doc first.

---

## Console — APNs key (actual delivery)

Token **registration** works in the app once rules are published. A real banner still needs:

1. **Paid Apple Developer Program** (same gate as Sign in with Apple). Personal Team cannot enable Push Notifications.
2. Xcode → **Signing & Capabilities** → **+ Push Notifications** (adds `aps-environment`).
3. [Apple Developer](https://developer.apple.com/account/resources/authkeys/list) → Keys → **+** → Apple Push Notifications service (APNs) → download `.p8`.
4. Firebase Console → **Project settings** → **Cloud Messaging** → Apple app configuration → upload the `.p8` (Key ID + Team ID).
5. Physical device (or iOS 16+ Simulator with a supported APNs setup).

Until that key is uploaded, Firestore still stores tokens; sends from Console / Cloud Functions will not reach the phone.

### Test send (after the key is live)

Firebase Console → **Engage → Messaging** → Campaign → Firebase Notification messages → target the iOS app / this FCM token.

---

## Verify registration (no APNs key yet)

1. Publish `firebase/firestore.rules`.
2. Sign in → allow notifications on the main tabs.
3. Firestore → `users/{uid}/deviceTokens` → one doc with `fcmToken` + `platform: ios`.
4. Sign out → that doc is deleted.

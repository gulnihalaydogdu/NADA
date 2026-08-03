# NADA — Not a Dating App!

iOS app (SwiftUI) + Firebase backend. Week 1 MVP: auth, friends-only onboarding, tab shell.

**Product schema:** [`UYGULAMA_SEMASI.md`](UYGULAMA_SEMASI.md)  
**Sprint backlog:** [`backlog/week-01.md`](backlog/week-01.md)  
**Locked decisions:** [`backlog/decisions-week-01.md`](backlog/decisions-week-01.md)

---

## Prerequisites

- Xcode 16+ (iOS 18+ target)
- Apple ID (Personal Team OK for email auth; Apple Sign In needs paid Developer Program)
- Firebase project with iOS app registered (`com.gulnihal.NADA`)

---

## Clone & run (iOS)

```bash
git clone https://github.com/gulnihalaydogdu/NADA.git
cd NADA
```

1. **Firebase plist** — download `GoogleService-Info.plist` from [Firebase Console](https://console.firebase.google.com/) → place in `NADA/GoogleService-Info.plist`  
   (Template: `NADA/GoogleService-Info.example.plist` — never commit the real file.)

2. **Verify setup**
   ```bash
   ./scripts/check-firebase-setup.sh
   ```

3. **Firestore** — create database + publish rules from [`firebase/firestore.rules`](firebase/firestore.rules)  
   Full steps: [`docs/FIREBASE_SETUP.md`](docs/FIREBASE_SETUP.md)

4. **Open & run**
   ```bash
   open NADA.xcodeproj
   ```
   Select a simulator or device → **⌘R**.

Expected flow: Welcome → Sign up (email) → Friends intent → Tab shell. Firestore `users/{uid}` appears after sign-up.

---

## Backend / Firebase (Dev B)

| Resource | Location |
|----------|----------|
| User schema | [`docs/FIRESTORE_USERS.md`](docs/FIRESTORE_USERS.md) |
| Setup guide | [`docs/FIREBASE_SETUP.md`](docs/FIREBASE_SETUP.md) |
| Security rules | [`firebase/firestore.rules`](firebase/firestore.rules) |
| Console | `https://console.firebase.google.com/project/<PROJECT_ID>` |

Auth: **Email/Password** enabled. Apple Sign In optional until paid developer account.

---

## Secrets

- `NADA/GoogleService-Info.plist` is **gitignored**
- Do not commit API keys or production credentials

---

## Repo layout

```
NADA/           SwiftUI app source
firebase/       Firestore rules
docs/           Firebase + schema docs
backlog/        Weekly sprint tickets
scripts/        Setup verification
```

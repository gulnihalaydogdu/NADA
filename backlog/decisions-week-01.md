# Week 1 — Technical decisions (locked 27 Jul 2026)

## Auth
- **Methods:** Apple Sign In + email/password
- **Fallback:** If email slips, ship Apple-only first; email follows in Week 2 Mon AM
- **Provider:** Firebase Auth (BaaS)
- **Session:** Firebase auth state listener; token attached to future API calls

## Backend
- **BaaS:** Firebase (Auth + Firestore + Storage in later weeks)
- **User fields (v1):** `id`, `displayName`, `gender`, `city`, `createdAt`, `intent` (= friendsOnly), `locale`
- **Secrets:** `GoogleService-Info.plist` is gitignored; use `GoogleService-Info.example.plist` as template

## iOS
- **UI language (stubs):** Turkish first
- **Design tokens:** NADA Lilac — brand `#B8A4DC`, paper `#F7F5FA`, ink `#1A1625`
- **Bundle ID:** `com.example.NADA` (update before App Store)

## Setup required (one-time)
1. Create Firebase project → add iOS app with bundle ID
2. Download `GoogleService-Info.plist` → place in `NADA/` folder
3. Enable **Authentication → Apple** and **Email/Password** in Firebase Console
4. Xcode: Sign in with Apple capability (entitlements file included)

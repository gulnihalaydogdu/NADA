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
- **UI language (MVP):** English first; Turkish in v1.1+
- **Design tokens:** NADA Lilac — brand `#B8A4DC`, paper `#F7F5FA`, ink `#1A1625`
- **Bundle ID:** `com.gulnihal.NADA` (must match Firebase iOS app + `GoogleService-Info.plist`)

## Copy / terminology
- **Bits** — user-facing name for profile Q&A cards (Hinge “prompts” equivalent). Examples: “Add 3 bits”, “Like a bit”.
- **Internal/API:** keep `Prompt`, `PromptAnswer`, `GET /prompts` unchanged.
- **TR (v1.1):** TBD — “bits” may stay as loanword or localize later.

## Illustrations (sketches)
- Hand-drawn editorial style (Hinge-like *line quality*, not Hinge colors).
- **No lilac/purple in art** — Hinge territory.
- **Match app icon:** dusty coral fill `#C17B6F`, pale blush wash `#F3DFDB`, ink `#1A1625`.
- UI lilac (`#B8A4DC`) stays for buttons/tabs only.
- Asset naming: `SketchWelcomeHangout`, `SketchWelcomeBits`, etc.

## Setup required (one-time)

**Full guide:** [`docs/FIREBASE_SETUP.md`](../docs/FIREBASE_SETUP.md)

1. Create Firebase project → add iOS app with bundle ID **`com.gulnihal.NADA`**
2. Download `GoogleService-Info.plist` → place in `NADA/` folder
3. Enable **Authentication → Apple** and **Email/Password** in Firebase Console
4. Run `./scripts/check-firebase-setup.sh` to verify
5. Xcode: Sign in with Apple capability (entitlements file included)

# Week 1 — Technical decisions (locked 27 Jul 2026)

## Auth
- **Methods:** Email/password for MVP (Personal Team dev account).
- **Apple Sign In:** Code ready; **disabled until paid Apple Developer Program** ($99/yr). Personal teams cannot use Sign in with Apple capability.
- **Provider:** Firebase Auth (BaaS)
- **Session:** Firebase auth state listener; token attached to future API calls

## Backend
- **BaaS:** Firebase (Auth + Firestore + Storage in later weeks)
- **User fields (v1, Firestore `users/{uid}`):**
  - **Core (W1-02):** `id` (doc id = Auth uid), `displayName`, `gender`, `city`, `intent`, `createdAt`, `locale`
  - **MVP extras:** `email` (from Auth), `friendsIntentCompleted` (onboarding gate)
  - **Schema reference:** [`docs/FIRESTORE_USERS.md`](../docs/FIRESTORE_USERS.md)
- **Secrets:** `GoogleService-Info.plist` is gitignored; use `GoogleService-Info.example.plist` as template

## iOS
- **UI language (MVP):** English first; Turkish in v1.1+
- **Design tokens:** NADA Coral — brand `#C17B6F`, paper `#FAF8F6`, ink `#1A1625`, blush wash `#F5E8E3`
- **Bundle ID:** `com.gulnihal.NADA` (must match Firebase iOS app + `GoogleService-Info.plist`)

## Profile tab structure (target layout)
Profile screen follows one fixed skeleton; new features slot into it instead of stacking new sections.

1. **Top bar** — preview (left) · “My Profile” · settings (right)
2. **Header** — avatar with camera badge, name, city
3. **Completion meter** — `% complete` averaged over the five sections below
4. **Actions** — `Preview profile` (blush) + `Edit` (ink)
5. **Nudges** — “Make your profile feel more like you”, max 3 rows from `ProfileCompletion.suggestions`
6. **Your profile rows** — Photos · Bits · About you · Hangout energy · Location & distance
7. **Mission card** — “NADA is for real connections.”
8. **Log out**

**Section state (Week 1):** Photos `1 / 6` (single Storage upload), Bits `0 / 3` (catalog read-only), About you (name + gender), Hangout energy (preview chips), Location (city saves, radius preview).  
**Rule:** each new capability updates its existing row + `ProfileCompletion`, no new top-level section without a design decision.

## Copy / terminology
- **Bits** — user-facing name for profile Q&A cards (Hinge “prompts” equivalent). Examples: “Add 3 bits”, “Like a bit”.
- **Internal/API:** keep `Prompt`, `PromptAnswer`, `GET /prompts` unchanged.
- **TR (v1.1):** TBD — “bits” may stay as loanword or localize later.

## Illustrations (sketches)
- Hand-drawn editorial style (Hinge-like *line quality*, not Hinge colors).
- **No lilac/purple in art** — Hinge territory.
- **Match app icon:** dusty coral fill `#C17B6F`, pale blush wash `#F3DFDB`, ink `#1A1625`.
- UI coral (`#C17B6F`) for buttons, tabs, links — matches sketch accent
- Asset naming: `SketchWelcomeHangout`, `SketchWelcomeBits`, etc.

## Setup required (one-time)

**Full guide:** [`docs/FIREBASE_SETUP.md`](../docs/FIREBASE_SETUP.md)

1. Create Firebase project → add iOS app with bundle ID **`com.gulnihal.NADA`**
2. Download `GoogleService-Info.plist` → place in `NADA/` folder
3. Enable **Authentication → Apple** and **Email/Password** in Firebase Console
4. Run `./scripts/check-firebase-setup.sh` to verify
5. **Apple Sign In (optional):** Requires **paid** Apple Developer Program — not available on Personal Team. When enrolled: add Sign in with Apple capability, restore entitlement in `NADA.entitlements`, set `NADAAuthConfig.isAppleSignInEnabled = true`.

# AGENTS.md

## Cursor Cloud specific instructions

**This repository cannot be built, linted, tested, or run inside a Cursor Cloud Agent VM.**

NADA is a native **iOS / SwiftUI** application (`NADA.xcodeproj`, Swift 5.0, iOS deployment
target 26.5) backed entirely by managed Firebase cloud services. It requires a **macOS host
with Xcode 16+ and an iOS Simulator/device** — none of which exist on the Linux Cloud Agent VM.

Why there is no workaround on the Linux VM (do not waste time re-attempting these):

- **Xcode is macOS-only and closed-source** — it cannot be installed on Linux, so `xcodebuild`
  (build, lint, and the only SPM dependency-resolution step) is unavailable.
- **Open-source Swift for Linux does not help** — every source file imports Apple-only
  frameworks (`SwiftUI`, `UIKit`, `PhotosUI`, `AuthenticationServices`) and/or the Firebase
  **iOS** SDK (`FirebaseCore/Auth/Firestore/Storage`). None of these exist on Linux Swift, so
  not even a single view compiles. There is also no `Package.swift` (Xcode project only).
- **No local backend / emulator** — there is no server code and no Firebase Emulator config
  (no `firebase.json`). The app talks directly to a live Firebase project.
- **The iOS Simulator only runs on macOS** — Docker/containers cannot provide it.

Consequences for agents:

- Do not add an install/update script that runs `xcodebuild`, `swift build`, or similar — they
  will fail on Linux. There are no Linux-installable dependencies for this repo.
- Code changes to Swift files cannot be compiled or run here; verify them by careful reading and
  (where possible) on a macOS machine with Xcode.
- Providing the `GoogleService-Info.plist` secret does **not** unblock building on Linux; the
  blocker is the OS/toolchain, not credentials.

### How this project is actually developed (on macOS, for reference)

- Setup, run, and Firebase steps are documented in `README.md` and `docs/FIREBASE_SETUP.md`
  (parts of the docs and helper-script output are in Turkish).
- Place the gitignored `NADA/GoogleService-Info.plist` (template: `NADA/GoogleService-Info.example.plist`),
  then verify with `scripts/check-firebase-setup.sh` (uses macOS `PlistBuddy`).
- Reset caches / re-resolve SPM packages / build with `scripts/fix-xcode-packages.sh`
  (uses `osascript` + `xcodebuild`, macOS-only).
- Open `NADA.xcodeproj` in Xcode, select a simulator, ⌘R. Expected first-run flow:
  Welcome → Sign up (email) → Friends intent → Tab shell, creating `users/{uid}` in Firestore.

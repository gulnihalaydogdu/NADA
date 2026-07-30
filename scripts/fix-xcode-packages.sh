#!/usr/bin/env bash
# Reset NADA Xcode caches and re-download Firebase Swift packages.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "→ Quitting Xcode..."
osascript -e 'tell application "Xcode" to quit' 2>/dev/null || true
pkill -x Xcode 2>/dev/null || true
sleep 2

echo "→ Removing NADA DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/NADA-*

echo "→ Removing local SPM workspace cache..."
rm -rf "$ROOT/NADA.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/configuration"
rm -rf "$ROOT/NADA.xcodeproj/project.xcworkspace/xcuserdata"

echo "→ Resolving Swift packages..."
cd "$ROOT"
xcodebuild -resolvePackageDependencies -scheme NADA

echo "→ Building for simulator..."
xcodebuild -scheme NADA -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

echo ""
echo "✅ Done. Open NADA.xcodeproj in Xcode and wait for indexing to finish."

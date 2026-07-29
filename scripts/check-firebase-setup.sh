#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/NADA/GoogleService-Info.plist"
EXPECTED_BUNDLE="com.gulnihal.NADA"

echo "NADA Firebase setup check"
echo "========================="

if [[ ! -f "$PLIST" ]]; then
  echo "❌ GoogleService-Info.plist bulunamadı."
  echo "   Beklenen konum: NADA/GoogleService-Info.plist"
  echo "   Rehber: docs/FIREBASE_SETUP.md"
  exit 1
fi

echo "✅ GoogleService-Info.plist mevcut"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" "$PLIST" 2>/dev/null || echo "")
PROJECT_ID=$(/usr/libexec/PlistBuddy -c "Print :PROJECT_ID" "$PLIST" 2>/dev/null || echo "")

if [[ "$BUNDLE_ID" != "$EXPECTED_BUNDLE" ]]; then
  echo "⚠️  BUNDLE_ID plist'te: $BUNDLE_ID"
  echo "   Xcode bundle ID:     $EXPECTED_BUNDLE"
  echo "   Firebase Console'da iOS app bundle ID'yi güncelle veya plist'i yeniden indir."
else
  echo "✅ BUNDLE_ID eşleşiyor: $BUNDLE_ID"
fi

if [[ -n "$PROJECT_ID" && "$PROJECT_ID" != *"YOUR_"* ]]; then
  echo "✅ PROJECT_ID: $PROJECT_ID"
else
  echo "❌ PROJECT_ID geçersiz veya placeholder."
  exit 1
fi

echo ""
echo "Firestore (W1-02) — users/{uid} schema:"
echo "  docs/FIRESTORE_USERS.md"
echo ""
echo "Expected fields on first sign-up:"
echo "  intent, friendsIntentCompleted, locale, createdAt"
echo "  optional: email, displayName"
echo "  null until profile wizard: gender, city"
echo ""
echo "Firestore (W1-02) — Console'da elle yapılır:"
echo "  1. Build → Firestore Database → Create database (yoksa)"
echo "  2. Rules → firebase/firestore.rules içeriğini yapıştır → Publish"
echo "  3. Rehber: docs/FIREBASE_SETUP.md §4"
echo ""
echo "  Firestore Data:"
echo "  https://console.firebase.google.com/project/${PROJECT_ID}/firestore/data"
echo ""
echo "  Firestore Rules:"
echo "  https://console.firebase.google.com/project/${PROJECT_ID}/firestore/rules"
echo ""
echo "Sonraki: Rules publish → Xcode Run → Kayıt ol → users/{uid} dokümanını kontrol et."

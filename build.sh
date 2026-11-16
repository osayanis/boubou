#!/bin/bash
# Fabrique « Petite Boule.app » (build + icône + Info.plist + messages.json + signature).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
VERSION="$(cat VERSION)"
echo "▶︎ swift build ($CONFIG)…"
swift build -c "$CONFIG"
BIN=".build/$CONFIG/PetiteBoule"

if [ ! -f AppIcon.icns ]; then
  rm -rf AppIcon.iconset
  "$BIN" icon AppIcon.iconset
  iconutil -c icns AppIcon.iconset -o AppIcon.icns
  rm -rf AppIcon.iconset
fi

APP="Petite Boule.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PetiteBoule"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp messages.json "$APP/Contents/Resources/messages.json"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Petite Boule</string>
  <key>CFBundleDisplayName</key><string>Petite Boule</string>
  <key>CFBundleIdentifier</key><string>com.osalabs.petiteboule</string>
  <key>CFBundleExecutable</key><string>PetiteBoule</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>fr</string>
  <key>CFBundleLocalizations</key><array><string>fr</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
  <key>NSHumanReadableCopyright</key><string>OsaLabs</string>
</dict>
</plist>
PLIST

# Certificat « Apple Development » du trousseau s'il existe, sinon signature ad-hoc.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')}"
codesign --force --deep --options runtime --sign "${SIGN_ID:--}" "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP"
codesign --verify --strict --deep "$APP"
echo "✅ $APP $VERSION prêt."

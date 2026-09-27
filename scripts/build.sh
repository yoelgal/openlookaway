#!/bin/bash
# Builds a universal, ad-hoc signed "dist/OpenLookAway.app" and dist/OpenLookAway.zip.
# Usage: VERSION=1.2.3 scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.0.0-dev}"
APP="dist/OpenLookAway.app"

swift build -c release --package-path app --arch arm64 --arch x86_64

rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp app/.build/apple/Products/Release/OpenLookAway "$APP/Contents/MacOS/"
cp app/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>OpenLookAway</string>
  <key>CFBundleDisplayName</key><string>OpenLookAway</string>
  <key>CFBundleIdentifier</key><string>com.yoelgal.openlookaway</string>
  <key>CFBundleExecutable</key><string>OpenLookAway</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

# Ad-hoc signature: required to run on Apple Silicon. No Apple Developer account needed.
codesign --force --sign - "$APP"
(cd dist && ditto -c -k --keepParent "OpenLookAway.app" OpenLookAway.zip)
echo "Built $APP ($VERSION)"

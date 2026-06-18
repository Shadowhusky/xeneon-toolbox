#!/bin/bash
# Build XeneonToolbox.app — a self-contained .app bundle you can launch from
# Finder and grant Input Monitoring + Accessibility once.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="XeneonToolbox.app"
BIN_NAME="XeneonToolbox"
BUILD_DIR=".build/release"

echo "Building release…"
swift build -c release

echo "Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Xeneon Toolbox</string>
    <key>CFBundleDisplayName</key><string>Xeneon Toolbox</string>
    <key>CFBundleIdentifier</key><string>com.shadowhusky.xeneon-toolbox</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# Stable ad-hoc signature so TCC (Input Monitoring / Accessibility) grants stick.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
echo "Move it to /Applications, then grant Input Monitoring + Accessibility in"
echo "System Settings → Privacy & Security so the embedded touch driver can run."

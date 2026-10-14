#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
# Build in an anonymous path so no local account or clone path ends up in the binary.
BUILD_ROOT="$(mktemp -d /tmp/glowdesk-build.XXXXXX)"
trap 'rm -rf "$BUILD_ROOT"' EXIT
cp "$PROJECT_ROOT/Package.swift" "$BUILD_ROOT/Package.swift"
cp -R "$PROJECT_ROOT/Sources" "$BUILD_ROOT/Sources"
swift build --package-path "$BUILD_ROOT" --scratch-path "$BUILD_ROOT/.build" -c release
APP="$PROJECT_ROOT/dist/Glowdesk.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_ROOT/.build/release/Glowdesk" "$APP/Contents/MacOS/Glowdesk"
strip -S "$APP/Contents/MacOS/Glowdesk"
cp "$PROJECT_ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Glowdesk</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>com.tahiryildiz.glowdesk</string>
<key>CFBundleName</key><string>Glowdesk</string>
<key>CFBundleDisplayName</key><string>Glowdesk</string>
<key>CFBundleVersion</key><string>${VERSION:-1.0.0}</string>
<key>CFBundleShortVersionString</key><string>${VERSION:-1.0.0}</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>tr</string></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Glowdesk finds your Hue Bridge and controls your lights over the local network.</string>
<key>NSBonjourServices</key><array><string>_hue._tcp</string></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
# The permission prompt follows the system language; in-app text can be switched in Settings.
mkdir -p "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/tr.lproj"
printf '"NSLocalNetworkUsageDescription" = "Glowdesk finds your Hue Bridge and controls your lights over the local network.";\n' > "$APP/Contents/Resources/en.lproj/InfoPlist.strings"
printf '"NSLocalNetworkUsageDescription" = "Glowdesk, Hue Bridge'"'"'i bulmak ve ışıklarını yerel ağ üzerinden kontrol etmek için erişim ister.";\n' > "$APP/Contents/Resources/tr.lproj/InfoPlist.strings"
codesign --force --deep --sign - --identifier com.tahiryildiz.glowdesk "$APP"
printf 'App created at %s\n' "$APP"

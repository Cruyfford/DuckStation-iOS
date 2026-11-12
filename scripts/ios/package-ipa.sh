#!/usr/bin/env bash
# Assembles DuckStation.app and an unsigned DuckStation.ipa (sign/install with SideStore, AltStore or Sideloadly).
# Usage: package-ipa.sh <cmake build dir> <deps install dir> <output .ipa>

set -euo pipefail

BUILD_DIR="$(cd "$1" && pwd)"
DEPS_DIR="$(cd "$2" && pwd)"
OUT_IPA="$3"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

STAGE="$(mktemp -d)"
APP="$STAGE/Payload/DuckStation.app"
mkdir -p "$APP/Frameworks"

# Executable
cp "$BUILD_DIR/bin/DuckStation" "$APP/DuckStation"
chmod +x "$APP/DuckStation"

# Metal shader library
METALLIB="$(find "$BUILD_DIR" -name 'Metal23.metallib' | head -n 1)"
if [ -z "$METALLIB" ]; then
  echo "Metal23.metallib not found in build directory" >&2
  exit 1
fi
cp "$METALLIB" "$APP/Metal23.metallib"

# Core resources (fonts, shaders, game database, ...)
cp -R "$ROOT_DIR/data/resources" "$APP/resources"
find "$APP/resources" -name '.DS_Store' -delete

# Runtime dylibs (shaderc, spirv-cross, soundtouch). Copy real files under every name they may be loaded by.
for lib in "$DEPS_DIR"/lib/*.dylib; do
  cp -L "$lib" "$APP/Frameworks/$(basename "$lib")"
done

# Make sure the executable finds them.
if ! otool -l "$APP/DuckStation" | grep -q "@executable_path/Frameworks"; then
  install_name_tool -add_rpath "@executable_path/Frameworks" "$APP/DuckStation"
fi

VERSION="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

cat > "$APP/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>DuckStation</string>
  <key>CFBundleExecutable</key><string>DuckStation</string>
  <key>CFBundleIdentifier</key><string>com.cruyfford.duckstation</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>DuckStation</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ar</string></array>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>MinimumOSVersion</key><string>15.0</string>
  <key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
  <key>UILaunchScreen</key><dict/>
  <key>UIRequiresFullScreen</key><true/>
  <key>UIStatusBarHidden</key><true/>
  <key>UIFileSharingEnabled</key><true/>
  <key>LSSupportsOpeningDocumentsInPlace</key><true/>
  <key>UIApplicationSupportsIndirectInputEvents</key><true/>
  <key>GCSupportsControllerUserInteraction</key><true/>
  <key>GCSupportedGameControllers</key>
  <array>
    <dict><key>ProfileName</key><string>ExtendedGamepad</string></dict>
  </array>
  <key>UISupportedInterfaceOrientations</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>UISupportedInterfaceOrientations~ipad</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Used to connect Bluetooth game controllers.</string>
</dict>
</plist>
EOF
plutil -lint "$APP/Info.plist"

# Ad-hoc sign so the bundle is well-formed; the sideloading tool re-signs it with your Apple ID.
codesign --force --sign - --timestamp=none "$APP/Frameworks/"*.dylib
codesign --force --sign - --timestamp=none "$APP/Metal23.metallib"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "== Bundle contents =="
ls -la "$APP" "$APP/Frameworks"
echo "== Linked libraries =="
otool -L "$APP/DuckStation"
otool -l "$APP/DuckStation" | grep -A2 LC_RPATH || true

mkdir -p "$(dirname "$OUT_IPA")"
OUT_ABS="$(cd "$(dirname "$OUT_IPA")" && pwd)/$(basename "$OUT_IPA")"
rm -f "$OUT_ABS"
(cd "$STAGE" && zip -qry "$OUT_ABS" Payload)
rm -rf "$STAGE"

echo "Created $OUT_ABS"
ls -la "$OUT_ABS"

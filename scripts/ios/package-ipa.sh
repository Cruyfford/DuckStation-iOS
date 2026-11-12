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

# Runtime dylibs: exactly one copy of each, under the name it is loaded by, with a matching install name.
#  - libshaderc_shared.dylib / libspirv-cross-c-shared.0.dylib are dlopen()ed by the Metal backend
#  - libsoundtouch.2.dylib is linked by the executable (@rpath/libsoundtouch.2.dylib)
for name in libshaderc_shared.dylib libspirv-cross-c-shared.0.dylib libsoundtouch.2.dylib; do
  cp -L "$DEPS_DIR/lib/$name" "$APP/Frameworks/$name"
  chmod 755 "$APP/Frameworks/$name"
  install_name_tool -id "@rpath/$name" "$APP/Frameworks/$name" 2>/dev/null
  codesign --force --sign - --timestamp=none "$APP/Frameworks/$name" # restore a valid ad-hoc signature
done

# App icons
cp "$ROOT_DIR"/scripts/ios/icons/AppIcon*.png "$APP/"
rm -f "$APP/AppIcon1024.png"

# Strip extended attributes (quarantine etc.) so the archive is clean.
xattr -cr "$APP" || true

# Make sure the executable finds them.
if ! otool -l "$APP/DuckStation" | grep -q "@executable_path/Frameworks"; then
  install_name_tool -add_rpath "@executable_path/Frameworks" "$APP/DuckStation"
fi

VERSION="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
SDK_BUILD="$(xcrun --sdk iphoneos --show-sdk-build-version)"
XCODE_VERSION="$(xcodebuild -version | awk '/Xcode/{print $2}' | awk -F. '{printf "%d%d%d0", $1, $2, ($3==""?0:$3)}')"
XCODE_BUILD="$(xcodebuild -version | awk '/Build version/{print $3}')"
MAC_BUILD="$(sw_vers -buildVersion)"

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
  <key>CFBundleIcons</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFiles</key><array><string>AppIcon60x60</string></array>
      <key>CFBundleIconName</key><string>AppIcon</string>
    </dict>
  </dict>
  <key>CFBundleIcons~ipad</key>
  <dict>
    <key>CFBundlePrimaryIcon</key>
    <dict>
      <key>CFBundleIconFiles</key><array><string>AppIcon60x60</string><string>AppIcon76x76</string><string>AppIcon83.5x83.5</string></array>
      <key>CFBundleIconName</key><string>AppIcon</string>
    </dict>
  </dict>
  <key>BuildMachineOSBuild</key><string>$MAC_BUILD</string>
  <key>DTCompiler</key><string>com.apple.compilers.llvm.clang.1_0</string>
  <key>DTPlatformBuild</key><string>$SDK_BUILD</string>
  <key>DTPlatformName</key><string>iphoneos</string>
  <key>DTPlatformVersion</key><string>$SDK_VERSION</string>
  <key>DTSDKBuild</key><string>$SDK_BUILD</string>
  <key>DTSDKName</key><string>iphoneos$SDK_VERSION</string>
  <key>DTXcode</key><string>$XCODE_VERSION</string>
  <key>DTXcodeBuild</key><string>$XCODE_BUILD</string>
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

# Like an Xcode build with CODE_SIGNING_ALLOWED=NO: no bundle signature (signers add their own).
# Mach-O files keep the linker's ad-hoc signature, which every signer replaces.
rm -rf "$APP/_CodeSignature"
plutil -convert binary1 "$APP/Info.plist"

echo "== Bundle contents =="
ls -la "$APP" "$APP/Frameworks"
echo "== Linked libraries =="
otool -L "$APP/DuckStation"
otool -l "$APP/DuckStation" | grep -A2 LC_RPATH || true

mkdir -p "$(dirname "$OUT_IPA")"
OUT_ABS="$(cd "$(dirname "$OUT_IPA")" && pwd)/$(basename "$OUT_IPA")"
rm -f "$OUT_ABS"
(cd "$STAGE" && zip -qrX "$OUT_ABS" Payload)
rm -rf "$STAGE"

echo "Created $OUT_ABS"
ls -la "$OUT_ABS"

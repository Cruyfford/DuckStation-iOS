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
# Must NOT be named "resources" (case-insensitively): a top-level Resources dir makes iOS treat the app as an
# old-style bundle and fail to read Info.plist (unknown name/icon, failed installs).
cp -R "$ROOT_DIR/data/resources" "$APP/dsdata"
find "$APP/dsdata" -name '.DS_Store' -delete

# Runtime libraries, packaged as .framework bundles like an Xcode app (no loose .dylib files).
#  - shaderc_shared / spirv_cross_c_shared are dlopen()ed by the Metal backend (see DynamicLibrary on iOS)
#  - soundtouch is linked by the executable; its load command is pointed at the framework
make_framework() {
  local dylib="$1" name="$2"
  local fw="$APP/Frameworks/$name.framework"
  mkdir -p "$fw"
  cp -L "$DEPS_DIR/lib/$dylib" "$fw/$name"
  chmod 755 "$fw/$name"
  install_name_tool -id "@rpath/$name.framework/$name" "$fw/$name" 2>/dev/null
  cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>com.cruyfford.duckstation.$(echo "$name" | tr '_' '-')</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
PLIST
  plutil -convert binary1 "$fw/Info.plist"
  codesign --force --sign - --timestamp=none "$fw/$name"
}

make_framework libshaderc_shared.dylib shaderc_shared
make_framework libspirv-cross-c-shared.0.dylib spirv_cross_c_shared
make_framework libsoundtouch.2.dylib soundtouch
# Patch + re-sign the executable outside the bundle (codesign would otherwise treat it as the whole app).
EXE_TMP="$STAGE/DuckStation.exe"
mv "$APP/DuckStation" "$EXE_TMP"
install_name_tool -change "@rpath/libsoundtouch.2.dylib" "@rpath/soundtouch.framework/soundtouch" "$EXE_TMP" 2>/dev/null
if ! otool -l "$EXE_TMP" | grep -q "@executable_path/Frameworks"; then
  install_name_tool -add_rpath "@executable_path/Frameworks" "$EXE_TMP"
fi
codesign --force --sign - --timestamp=none "$EXE_TMP"
mv "$EXE_TMP" "$APP/DuckStation"

# ARMSX2 SwiftUI frontend assets (laid out the way ARMSX2's bundle has them).
UI_ASSETS="$ROOT_DIR/src/duckstation-ios/ui/assets"
xcrun actool "$UI_ASSETS/Assets.xcassets" --compile "$APP" --platform iphoneos \
  --minimum-deployment-target 17.4 --target-device iphone --target-device ipad \
  --output-partial-info-plist "$STAGE/assets-partial.plist" --errors --warnings >/dev/null
xcrun xcstringstool compile "$UI_ASSETS/resources/Localizable.xcstrings" --output-directory "$APP"
cp "$UI_ASSETS"/controller_icons/*.png "$APP/"
cp -R "$UI_ASSETS/controller_skins" "$APP/controller_skins"
cp -R "$UI_ASSETS/shaders" "$APP/shaders"
# No ARMSX2 boot video: the splash skips straight to the library.
find "$UI_ASSETS/app_icons" -name '*.png' -exec cp {} "$APP/" \;
mkdir -p "$APP/ui_audio/default"
cp "$UI_ASSETS"/ui_audio/* "$APP/ui_audio/default/"
# The menu audio pack also needs the notification sounds; without them no UI audio loads at all.
mkdir -p "$APP/sounds"
cp -R "$ROOT_DIR"/data/resources/sounds/achievements "$APP/sounds/"
find "$UI_ASSETS/resources" -maxdepth 1 -type f ! -name '*.xcstrings' -exec cp {} "$APP/" \;
ls -d "$APP"/*.lproj

# App icons
cp "$ROOT_DIR"/scripts/ios/icons/AppIcon*.png "$APP/"
rm -f "$APP/AppIcon1024.png"

# Strip extended attributes (quarantine etc.) so the archive is clean.
xattr -cr "$APP" || true


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
  <key>CFBundleLocalizations</key><array><string>en</string><string>ar</string><string>de</string><string>es</string><string>fr</string><string>it</string><string>ja</string><string>ko</string><string>pt</string><string>zh-Hans</string></array>
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
  <key>MinimumOSVersion</key><string>17.4</string>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
    <key>UISceneConfigurations</key>
    <dict>
      <key>UIWindowSceneSessionRoleApplication</key>
      <array>
        <dict>
          <key>UISceneConfigurationName</key><string>Default Configuration</string>
          <key>UISceneDelegateClassName</key><string>DSSceneDelegate</string>
        </dict>
      </array>
    </dict>
  </dict>
  <key>NSPhotoLibraryUsageDescription</key><string>Used to pick custom backgrounds and skins.</string>
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
ls -laR "$APP/Frameworks"
ls -la "$APP"
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

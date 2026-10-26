#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=version.env
source "$ROOT_DIR/version.env"

APP_NAME="SkillsProof"
BUNDLE_ID="${SKILLSBAR_BUNDLE_ID:-local.jscraik.skillsbar}"
BUILD_ROOT="${2:-${SKILLSBAR_BUILD_ROOT:-$HOME/.codex/usage-data/skillsbar}}"
CONFIGURATION="${1:-debug}"
ARCHES_VALUE="${ARCHES:-$(uname -m)}"
SIGNING_MODE="${SKILLSBAR_SIGNING:-adhoc}"
APP_DIR="$BUILD_ROOT/$APP_NAME.app"
STAGE_DIR="$BUILD_ROOT/package/$APP_NAME.app"
CONTENTS_DIR="$STAGE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

case "$CONFIGURATION" in
  debug|release) ;;
  *) fail "Unsupported configuration: $CONFIGURATION (expected debug or release)" ;;
esac

case "$SIGNING_MODE" in
  adhoc|identity) ;;
  *) fail "Unsupported SKILLSBAR_SIGNING: $SIGNING_MODE (expected adhoc or identity)" ;;
esac

if [[ "$SIGNING_MODE" == "identity" && -z "${APP_IDENTITY:-}" ]]; then
  fail "APP_IDENTITY is required when SKILLSBAR_SIGNING=identity"
fi

read -r -a ARCH_LIST <<<"$ARCHES_VALUE"
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  fail "ARCHES must contain at least one architecture"
fi

rm -rf "$STAGE_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>SkillsSDKIcon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright 2026 Jamie Craik</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

BUILT_BINARIES=()
for arch in "${ARCH_LIST[@]}"; do
  arch_build="$BUILD_ROOT/swiftpm-$CONFIGURATION-$arch"
  module_cache="$BUILD_ROOT/clang-module-cache-$arch"
  mkdir -p "$module_cache"

  HOME="$BUILD_ROOT/home" \
  XDG_CACHE_HOME="$BUILD_ROOT/xdg-cache" \
  XDG_STATE_HOME="$BUILD_ROOT/xdg-state" \
  MISE_CACHE_DIR="$BUILD_ROOT/mise-cache" \
  MISE_STATE_DIR="$BUILD_ROOT/mise-state" \
  CLANG_MODULE_CACHE_PATH="$module_cache" \
  swift build --build-system native --disable-sandbox \
    --build-path "$arch_build" -c "$CONFIGURATION" --arch "$arch" -Xswiftc -gnone

  binary="$arch_build/$arch-apple-macosx/$CONFIGURATION/$APP_NAME"
  if [[ ! -x "$binary" ]]; then
    binary="$(find "$arch_build" -path "*/$CONFIGURATION/$APP_NAME" -type f -perm -111 -print -quit)"
  fi
  [[ -n "$binary" && -x "$binary" ]] || fail "Built $APP_NAME executable not found for $arch"
  /usr/bin/lipo -archs "$binary" | tr ' ' '\n' | grep -Fx "$arch" >/dev/null \
    || fail "$binary does not contain required architecture $arch"
  BUILT_BINARIES+=("$binary")
done

if [[ ${#BUILT_BINARIES[@]} -gt 1 ]]; then
  /usr/bin/lipo -create "${BUILT_BINARIES[@]}" -output "$MACOS_DIR/$APP_NAME"
else
  cp "${BUILT_BINARIES[0]}" "$MACOS_DIR/$APP_NAME"
fi
chmod +x "$MACOS_DIR/$APP_NAME"
if [[ "$CONFIGURATION" == "release" ]]; then
  /usr/bin/strip -S -x "$MACOS_DIR/$APP_NAME"
fi

actual_arches="$(/usr/bin/lipo -archs "$MACOS_DIR/$APP_NAME")"
for arch in "${ARCH_LIST[@]}"; do
  tr ' ' '\n' <<<"$actual_arches" | grep -Fx "$arch" >/dev/null \
    || fail "Packaged executable is missing $arch (contains: $actual_arches)"
done

cp "$ROOT_DIR/Sources/SkillsBar/Resources/TesslLogo.png" "$RESOURCES_DIR/TesslLogo.png"
ICON_SOURCE="$ROOT_DIR/Sources/SkillsBar/Resources/SkillsSDKIcon.png"
cp "$ICON_SOURCE" "$RESOURCES_DIR/SkillsSDKIcon.png"
# Build a complete standard iconset from the approved artwork.
ICONSET_DIR="$BUILD_ROOT/package/SkillsProof.iconset"
mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  retina_size=$((size * 2))
  sips -z "$retina_size" "$retina_size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/SkillsSDKIcon.icns"

PREFERRED_BUILD_DIR="$(dirname "${BUILT_BINARIES[0]}")"
shopt -s nullglob
SWIFTPM_BUNDLES=("$PREFERRED_BUILD_DIR/"*.bundle)
shopt -u nullglob
if [[ ${#SWIFTPM_BUNDLES[@]} -eq 0 ]]; then
  fail "SwiftPM resource bundle was not found next to $APP_NAME"
fi
for bundle in "${SWIFTPM_BUNDLES[@]}"; do
  bundle_name="$(basename "$bundle")"
  cp -R "$bundle" "$RESOURCES_DIR/$bundle_name"
  [[ -d "$RESOURCES_DIR/$bundle_name" ]] \
    || fail "SwiftPM resource bundle was not staged in Contents/Resources: $bundle_name"
done

/usr/bin/xattr -cr "$STAGE_DIR"
find "$STAGE_DIR" -name '._*' -delete

if [[ "$SIGNING_MODE" == "identity" ]]; then
  /usr/bin/codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" "$STAGE_DIR"
else
  /usr/bin/codesign --force --sign - "$STAGE_DIR"
fi
/usr/bin/codesign --verify --deep --strict "$STAGE_DIR"
if [[ "$CONFIGURATION" == "release" ]]; then
  python3 "$ROOT_DIR/script/check_release.py" "$STAGE_DIR"
fi

rm -rf "$APP_DIR"
mv "$STAGE_DIR" "$APP_DIR"
printf 'Created %s (%s; %s)\n' "$APP_DIR" "$CONFIGURATION" "$actual_arches"

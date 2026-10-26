#!/usr/bin/env bash
#
# Builds MultiVolume as a hardened-runtime .app bundle and a release zip.
#
#   ./build.sh                      # hardened runtime; see SIGN_ID below
#   SIGN_ID="Apple Development: Name (TEAMID)" ./build.sh
#   BUNDLE_ID=com.example.multivolume ./build.sh
#   UNIVERSAL=0 ./build.sh          # native architecture only
#
# SIGN_ID defaults to the certificate from ./make-signing-cert.sh when it is in
# the keychain, and to ad-hoc ("-") otherwise, as on CI.
#
# Output:
#   build/MultiVolume.app
#   build/MultiVolume-<version>.zip
#
set -euo pipefail

APP_NAME="MultiVolume"
BUNDLE_ID="${BUNDLE_ID:-io.github.ecossaiah.multivolume}"
DEFAULT_CERT="EcossAIah Self-Signed"
if [ -z "${SIGN_ID:-}" ]; then
  if security find-certificate -c "$DEFAULT_CERT" >/dev/null 2>&1; then
    SIGN_ID="$DEFAULT_CERT"
  else
    SIGN_ID="-"
  fi
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"

# ---------------------------------------------------------------- toolchain

echo "==> Toolchain"
echo "    developer dir: $(xcode-select -p 2>/dev/null || echo '<none>')"
echo "    swift:         $(swift --version 2>&1 | head -1)"
echo "    version:       $VERSION"

# ---------------------------------------------------------------- build

# Map the checkout path to "." so no absolute build paths end up in the
# binary (#file strings, debug info).
SWIFT_FLAGS=(-c release
             -Xswiftc -file-prefix-map -Xswiftc "$ROOT=."
             -Xswiftc -debug-prefix-map -Xswiftc "$ROOT=."
             --package-path "$ROOT")

ARCH_FLAGS=()
if [ "${UNIVERSAL:-1}" = "1" ]; then
  echo "==> Building universal release binary (arm64 + x86_64)"
  if swift build "${SWIFT_FLAGS[@]}" --arch arm64 --arch x86_64; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
  else
    cat <<EOF

    NOTE: the universal build failed. Older toolchains need Xcode's build
          system for multi-architecture builds. If Xcode is installed but the
          Command Line Tools are selected, switch with:
            sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

          Falling back to a $(uname -m)-only build.

EOF
  fi
fi

if [ ${#ARCH_FLAGS[@]} -eq 0 ]; then
  echo "==> Building release binary ($(uname -m))"
  swift build "${SWIFT_FLAGS[@]}"
fi

BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"

if [ ! -f "$BIN" ]; then
  echo "ERROR: build product not found at $BIN" >&2
  exit 1
fi

# ---------------------------------------------------------------- bundle

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
# Drop debug symbols and local symbols. Must happen before signing.
strip -S -x "$APP/Contents/MacOS/$APP_NAME"
sed "s/__BUNDLE_ID__/$BUNDLE_ID/" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"

# ---------------------------------------------------------------- icon
# Must happen before signing so the signature seals the icon too.

ICONSET="$ROOT/icon/AppIcon.iconset"
if [ -d "$ICONSET" ]; then
  echo "==> Building app icon"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  echo "==> icon/AppIcon.iconset not found; the app will use the generic icon"
fi

# ---------------------------------------------------------------- sign

echo "==> Signing with hardened runtime (identity: $SIGN_ID)"
codesign --force \
         --options runtime \
         --identifier "$BUNDLE_ID" \
         --sign "$SIGN_ID" \
         --timestamp=none \
         "$APP"

# ---------------------------------------------------------------- verify

echo
echo "=================== VERIFICATION ==================="

echo "--- seal ---"
codesign --verify --strict --verbose=2 "$APP"

echo "--- signature ---"
codesign -dvvv "$APP" 2>&1 | grep -E "^Identifier=|flags=|^Signature=|^TeamIdentifier=" || true

echo "--- hardened runtime ---"
SIGINFO="$(codesign -dvvv "$APP" 2>&1 || true)"
if [[ "$SIGINFO" =~ flags=[^[:space:]]*runtime ]]; then
  echo "OK: hardened runtime enabled"
else
  echo "FAIL: hardened runtime NOT enabled" >&2
  exit 1
fi

echo "--- debug entitlement ---"
ENTS="$(codesign -d --entitlements - "$APP" 2>&1 || true)"
if [[ "$ENTS" == *get-task-allow* ]]; then
  echo "FAIL: get-task-allow present; this is a debug build" >&2
  exit 1
else
  echo "OK: no get-task-allow"
fi

echo "--- architectures ---"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"

echo "--- linked libraries ---"
otool -L "$APP/Contents/MacOS/$APP_NAME" | tail -n +2 | awk '{print $1}'
if otool -L "$APP/Contents/MacOS/$APP_NAME" | grep -q PrivateFrameworks; then
  echo "FAIL: links a private framework" >&2
  exit 1
fi

echo "--- embedded paths ---"
# The folder that holds the checkout, and the folder that holds home directories.
PARENT="$(dirname "$ROOT")/"
HOMES="$(dirname "${HOME:-$ROOT}")/"
# grep -a scans every byte; strings(1) skips parts of the symbol table.
if LC_ALL=C grep -a -q -F -e "$PARENT" -e "$HOMES" "$APP/Contents/MacOS/$APP_NAME"; then
  echo "FAIL: the binary contains absolute build or home paths" >&2
  LC_ALL=C grep -a -o -F -e "$PARENT" -e "$HOMES" "$APP/Contents/MacOS/$APP_NAME" | sort | uniq -c >&2
  exit 1
else
  echo "OK: no absolute build or home paths"
fi

# ---------------------------------------------------------------- package

ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"
echo
echo "==> Packaging $ZIP"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"

echo
echo "Built:    $APP"
echo "Package:  $ZIP"
echo "Install:  cp -R \"$APP\" /Applications/"

if [ "$SIGN_ID" = "-" ]; then
  cat <<'NOTE'

NOTE: this build is ad-hoc signed. Its code hash changes on every rebuild, so
macOS treats each rebuild as a different app and the Accessibility grant
(needed for the media keys) has to be given again. To keep the grant across
rebuilds, create a fixed certificate once:

  ./make-signing-cert.sh
NOTE
fi

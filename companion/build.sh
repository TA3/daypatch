#!/bin/bash
# Builds ~/Applications/DayPatch.app: the menu bar companion, with the daypatch
# dylib bundled so it can patch Dia without a compiler.
#
#   ./companion/build.sh               build and install
#   ./companion/build.sh --launch      build, install, and open it
#   ./companion/build.sh --no-install  build only (build/DayPatch.app; used by CI)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="$ROOT/build/DayPatch.app"
DEST="$HOME/Applications/DayPatch.app"
VERSION="$(cat "$ROOT/VERSION")"
REPO="${DAYPATCH_REPO:-TA3/daypatch}"
# Public key that update downloads must be signed with (see scripts/make-update-key.sh).
UPDATE_KEY="${DAYPATCH_UPDATE_PUBLIC_KEY:-$(cat "$HERE/update-public-key.txt" 2>/dev/null || true)}"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

# The patch itself.
clang -dynamiclib -arch arm64 -fobjc-arc -O2 -Wall -Wno-unused-function \
    -framework AppKit -framework QuartzCore -lsqlite3 -DDAYPATCH_VERSION="\"$VERSION\"" \
    -o "$OUT/Contents/Resources/daypatch.dylib" "$ROOT"/src/*.m
cp "$ROOT/entitlements.plist" "$OUT/Contents/Resources/"
echo "$VERSION" > "$OUT/Contents/Resources/VERSION"

# The companion.
swiftc -O -swift-version 5 -module-name DayPatch -target arm64-apple-macos14 \
    -o "$OUT/Contents/MacOS/DayPatch" "$HERE"/Sources/*.swift

"$OUT/Contents/MacOS/DayPatch" --make-icon "$OUT/Contents/Resources"

cat > "$OUT/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.ta3.daypatch</string>
  <key>CFBundleName</key><string>DayPatch</string>
  <key>CFBundleExecutable</key><string>DayPatch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>dev.ta3.daypatch</string>
    <key>CFBundleURLSchemes</key><array><string>daypatch</string></array>
  </dict></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>DayPatchRepo</key><string>$REPO</string>
  <key>DayPatchUpdatePublicKey</key><string>$UPDATE_KEY</string>
</dict></plist>
EOF

codesign -f -s - "$OUT/Contents/Resources/daypatch.dylib"
codesign -f -s - "$OUT"

if [[ "${1:-}" == "--no-install" ]]; then echo "Built: $OUT"; exit 0; fi

if pgrep -fx "$DEST/Contents/MacOS/DayPatch" >/dev/null; then pkill -fx "$DEST/Contents/MacOS/DayPatch"; sleep 1; fi
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$OUT" "$DEST"
echo "Built: $DEST"

if [[ "${1:-}" == "--launch" ]]; then open "$DEST"; fi

#!/bin/zsh
# Builds the distributable FloBlur DMG: universal Release app, signed,
# premium Finder window (background art + fixed icon positions).
#
# Usage: ./Tools/build-dmg.sh [version]   (default 0.1.0)
# Env:   SIGN_IDENTITY (default "FloBlur")
#
# Ordering lessons baked in (do NOT reorder):
#   1. Finder layout pass deletes dotfiles -> .VolumeIcon.icns goes on AFTER.
#   2. Background picture must be SET during layout (file present, then set).
#   3. Verify detach via `ls /Volumes` before converting, or the
#      convert fails on a busy image and you lose the artifact.
set -euo pipefail

VERSION="${1:-0.1.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:-FloBlur}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Release universal build"
xcodebuild -project FloBlur.xcodeproj -scheme FloBlur -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build \
  | grep -E "error|BUILD (SUCCEEDED|FAILED)"

APP="$(ls -d ~/Library/Developer/Xcode/DerivedData/FloBlur-*/Build/Products/Release/FloBlur.app | head -n 1)"
echo "==> Architectures: $(lipo -archs "$APP/Contents/MacOS/FloBlur")"

echo "==> Signing as $SIGN_IDENTITY"
codesign --deep --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Authority|Signature"

STAGE="$(mktemp -d)/floblur-dmg"
RW="/tmp/FloBlur-rw.dmg"
OUT="dist/FloBlur-$VERSION.dmg"
rm -rf "$STAGE" "$RW" "$OUT"
mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -srcfolder "$STAGE" -format UDRW -ov -o "$RW" >/dev/null
# A stale mount would steal the "FloBlur" name at rename time ("FloBlur 1")
# and break detach-by-path afterwards — clear them first.
for m in "/Volumes/FloBlur" "/Volumes/FloBlur 1" "/Volumes/floblur-dmg"; do
  [ -d "$m" ] && hdiutil detach "$m" >/dev/null 2>&1 || true
done
ATTACH_OUT="$(hdiutil attach "$RW" -nobrowse)"
DEV="$(printf '%s' "$ATTACH_OUT" | grep -o '/dev/disk[0-9]*' | head -n 1)"
VOL="$(printf '%s' "$ATTACH_OUT" | awk '{print $NF}')"
[ -n "$DEV" ] && [ -d "$VOL" ] || { echo "ERROR: attach failed"; exit 1; }
mkdir -p "$VOL/.background"
cp "Tools/dmg-background.png" "$VOL/.background/background.png"

osascript -e 'tell application "Finder"
  tell disk "floblur-dmg"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, 660, 440}
    set arrangement of icon view options of container window to not arranged
    set icon size of icon view options of container window to 96
    set background picture of icon view options of container window to file ".background:background.png"
    set position of item "FloBlur.app" of container window to {150, 190}
    set position of item "Applications" of container window to {410, 190}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell'

# Volume icon AFTER layout (Finder strips dotfiles during layout).
cp "FloBlur/AppIcon.icns" "$VOL/.VolumeIcon.icns"
SetFile -a C "$VOL/.VolumeIcon.icns"
SetFile -a C "$VOL"
diskutil rename "$VOL" "FloBlur" >/dev/null
# Detach by device node: mountpoint renames can lag ("FloBlur 1"), the
# device node never lies. Verify by listing before converting.
hdiutil detach "$DEV" >/dev/null
sleep 1
if ls /Volumes/ | grep -qx "FloBlur"; then
  echo "ERROR: volume still attached, aborting convert"; exit 1
fi

hdiutil convert "$RW" -format UDZO -ov -o "$OUT" >/dev/null
rm -f "$RW"
hdiutil verify "$OUT" | tail -n 1
hdiutil attach "$OUT" -nobrowse -readonly >/dev/null
codesign -dvv "/Volumes/FloBlur/FloBlur.app" 2>&1 | grep Authority
ls "/Volumes/FloBlur/"
hdiutil detach "/Volumes/FloBlur" >/dev/null
ls -la "$OUT"
echo "==> DONE: $OUT"

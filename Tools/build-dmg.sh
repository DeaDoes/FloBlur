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
# NOTE: deliberately NO `--options runtime` (hardened runtime). With a
# self-signed identity (no Team ID), hardened runtime turns on library
# validation and dyld refuses our own re-signed Sparkle.framework at
# launch ("different Team IDs") — the app crash-loops on other Macs.
# Debug builds never hit this (ad-hoc = validation off). Re-add `runtime`
# only together with a real Developer ID signature.
codesign --deep --force --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Authority|Signature"

STAGE="$(mktemp -d)/floblur-dmg"
RW="/tmp/FloBlur-rw.dmg"
OUT="dist/FloBlur-$VERSION.dmg"
rm -rf "$STAGE" "$RW" "$OUT"
mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -srcfolder "$STAGE" -format UDRW -ov -o "$RW" >/dev/null
# Explicit /Volumes mountpoint: Finder cannot address disks mounted
# anywhere else (`tell disk` -> -1728), and bare attaches risk "Name 1"
# suffix collisions. Stale same-name mounts are force-detached first.
for m in /Volumes/FloBlur*(N) /Volumes/floblur-dmg*(N); do
  hdiutil detach "$m" -force >/dev/null 2>&1 || true
done
MNT="/Volumes/floblur-dmg"
rm -rf "$MNT"
hdiutil attach "$RW" -nobrowse -mountpoint "$MNT" >/dev/null
[ -d "$MNT/FloBlur.app" ] || { echo "ERROR: attach failed"; exit 1; }
VOL="$MNT"
mkdir -p "$VOL/.background"
cp "Tools/dmg-background.png" "$VOL/.background/background.png"

if osascript -e 'tell application "Finder"
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
end tell'; then
  # A passing script that wrote no .DS_Store means silent unstyled output:
  # fail loudly instead of shipping a plain-looking DMG.
  if [ ! -f "$VOL/.DS_Store" ]; then
    echo "ERROR: Finder layout ran but .DS_Store missing — refusing silent unstyled DMG"
    exit 1
  fi
else
  # Headless runners have no Finder session: keep going with an unstyled
  # but fully valid DMG instead of failing the release.
  echo "WARNING: Finder layout skipped (no GUI session); DMG stays valid."
fi

# Volume icon AFTER layout (Finder strips dotfiles during layout).
cp "FloBlur/AppIcon.icns" "$VOL/.VolumeIcon.icns"
SetFile -a C "$VOL/.VolumeIcon.icns"
SetFile -a C "$VOL"
# Capture the device node BEFORE renaming: after `diskutil rename` the
# mountpoint changes and grepping the old path yields an empty DEV,
# which makes detach fail the whole release.
DEV="$(hdiutil info | grep -B1 "$VOL" | grep -o '/dev/disk[0-9]*' | head -n 1)"
diskutil rename "$VOL" "FloBlur" >/dev/null
# Detach by device node: the mountpoint path is ours alone, but the node
# never lies. Verify by listing before converting.
hdiutil detach "$DEV" >/dev/null
sleep 1
if ls /Volumes/ | grep -qx "FloBlur"; then
  echo "ERROR: volume still attached, aborting convert"; exit 1
fi

hdiutil convert "$RW" -format UDZO -ov -o "$OUT" >/dev/null
rm -f "$RW"
hdiutil verify "$OUT" | tail -n 1
VMNT="/tmp/floblur-verify"
rm -rf "$VMNT"
mkdir -p "$VMNT"
hdiutil attach "$OUT" -nobrowse -readonly -mountpoint "$VMNT" >/dev/null
codesign -dvv "$VMNT/FloBlur.app" 2>&1 | grep Authority
ls -la "$VMNT/"
hdiutil detach "$VMNT" >/dev/null
rmdir "$VMNT" 2>/dev/null || true
ls -la "$OUT"
echo "==> DONE: $OUT"

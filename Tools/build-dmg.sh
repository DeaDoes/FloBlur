#!/bin/zsh
# Builds the distributable FloBlur DMG: universal Release app, signed,
# premium Finder window (background art + fixed icon positions).
#
# Usage: ./Tools/build-dmg.sh [version] (defaults to the built bundle version)
# Env:   SIGN_IDENTITY (default "FloBlur")
#        FLOBLUR_DERIVED_DATA_PATH (optional directory for reusing this build)
#
# Ordering lessons baked in (do NOT reorder):
#   1. Finder layout pass deletes dotfiles -> .VolumeIcon.icns goes on AFTER.
#   2. Background picture must be SET during layout (file present, then set).
#   3. Detach the device returned by this run’s attach before converting.
set -euo pipefail

REQUESTED_VERSION="${1:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-FloBlur}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/floblur-package.XXXXXX")"
MNT=""
DEV=""
ATTACHED_IMAGE=""

# The attach plist identifies the mounted device. The info plist is used
# only as a fallback if the script exits before reading the attach result.
image_device() {
  python3 - "$@" <<'PYTHON'
import os
import plistlib
import re
import sys

mode, report, image, mount = sys.argv[1:]
with open(report, "rb") as stream:
    data = plistlib.load(stream)

if mode == "attach":
    entities = data.get("system-entities", [])
    if not any(entry.get("mount-point") == mount for entry in entities):
        sys.exit("ERROR: image did not mount at the requested path")
    # The first device is the image itself. APFS can also report a
    # synthesized disk for the mounted volume.
    devices = [entry.get("dev-entry", "") for entry in entities]
else:
    devices = [entry.get("dev-entry", "")
               for item in data.get("images", [])
               if os.path.realpath(item.get("image-path", "")) == os.path.realpath(image)
               for entry in item.get("system-entities", [])]

for device in devices:
    match = re.fullmatch(r"(/dev/disk[0-9]+)(?:s[0-9]+)*", device)
    if match:
        print(match[1])
        break
else:
    if mode == "attach":
        sys.exit("ERROR: no device found for this mount")
PYTHON
}

detach_image() {
  [[ -n "$ATTACHED_IMAGE" ]] || return 0
  if [[ -z "$DEV" ]]; then
    hdiutil info -plist > "$WORK/attached.plist" || return 1
    DEV="$(image_device info "$WORK/attached.plist" "$ATTACHED_IMAGE" "$MNT")" || return 1
  fi
  if [[ -n "$DEV" ]]; then
    hdiutil detach "$DEV" >/dev/null || return 1
  fi
  DEV=""
  ATTACHED_IMAGE=""
}

cleanup() {
  if ! detach_image; then
    echo "WARNING: Could not detach this run’s disk image. Work files remain at $WORK." >&2
    return
  fi
  rm -rf -- "$WORK"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

attach_image() {
  local image="$1"
  shift
  ATTACHED_IMAGE="$image"
  hdiutil attach "$image" -nobrowse -mountpoint "$MNT" -plist "$@" > "$WORK/attach.plist" || return 1
  DEV="$(image_device attach "$WORK/attach.plist" "$image" "$MNT")"
}

DERIVED_DATA="${FLOBLUR_DERIVED_DATA_PATH:-$WORK/derived-data}"
echo "==> Release universal build"
xcodebuild -project FloBlur.xcodeproj -scheme FloBlur -configuration Release \
  -derivedDataPath "$DERIVED_DATA" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build \
  | grep -E "error|BUILD (SUCCEEDED|FAILED)"

APP="$DERIVED_DATA/Build/Products/Release/FloBlur.app"
test -x "$APP/Contents/MacOS/FloBlur"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [[ -n "$REQUESTED_VERSION" && "$VERSION" != "$REQUESTED_VERSION" ]]; then
  echo "ERROR: built bundle version $VERSION does not match $REQUESTED_VERSION" >&2
  exit 1
fi
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

STAGE="$WORK/stage"
RW="$WORK/staging.dmg"
PACKAGED="$WORK/FloBlur.dmg"
OUT="dist/FloBlur-$VERSION.dmg"
mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Finder uses the unique volume label for the temporary layout pass.
VOLUME_NAME="${WORK:t}"
MNT="/Volumes/$VOLUME_NAME"
[[ ! -e "$MNT" && ! -L "$MNT" ]] || { echo "ERROR: mount path already exists: $MNT" >&2; exit 1; }
hdiutil create -srcfolder "$STAGE" -volname "$VOLUME_NAME" -format UDRW -o "$RW" >/dev/null
attach_image "$RW" || exit 1
[ -d "$MNT/FloBlur.app" ] || { echo "ERROR: attach failed"; exit 1; }
VOL="$MNT"
mkdir -p "$VOL/.background"
cp "Tools/dmg-background.png" "$VOL/.background/background.png"

if osascript - "$VOLUME_NAME" <<'APPLESCRIPT'
on run argv
tell application "Finder"
  tell disk (item 1 of argv)
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
end tell
end run
APPLESCRIPT
then
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
diskutil rename "$VOL" "FloBlur" >/dev/null
detach_image || exit 1

hdiutil convert "$RW" -format UDZO -o "$PACKAGED" >/dev/null
hdiutil verify "$PACKAGED" | tail -n 1
attach_image "$PACKAGED" -readonly || exit 1
codesign -dvv "$MNT/FloBlur.app" 2>&1 | grep Authority
ls -la "$MNT/"
detach_image || exit 1

mv -f -- "$PACKAGED" "$OUT"
ls -la "$OUT"
echo "==> DONE: $OUT"

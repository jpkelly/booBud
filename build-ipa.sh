#!/bin/zsh
# build-ipa.sh — packages the most recent Xcode device build as a .ipa on the Desktop.
#
# USAGE:
#   1. In Xcode, select your iPhone as the destination and press ⌘R to build & run.
#   2. Then run this script: ./build-ipa.sh
#   3. AirDrop booBud.ipa from your Desktop to your iPhone.
#   4. In AltStore → My Apps → + → select the .ipa to install/update.
#
# WHY ⌘R first? xcodebuild can't access your Apple ID credentials from the terminal,
# so it can't auto-sign. Xcode handles signing when you build normally; this script
# just packages the result.

set -e

DESKTOP="$HOME/Desktop"
IPA_NAME="booBud.ipa"

echo "▸ Finding .app bundle from last Xcode device build…"
APP=$(find "$HOME/Library/Developer/Xcode/DerivedData/booBud-"*/Build/Products/Debug-iphoneos \
    -name "booBud.app" -maxdepth 1 2>/dev/null | head -1)

if [[ -z "$APP" ]]; then
    echo "✗ Could not find booBud.app."
    echo "  → Open Xcode, select your iPhone as the destination, and press ⌘R first."
    exit 1
fi

if [[ ! -f "$APP/embedded.mobileprovision" ]]; then
    echo "✗ No provisioning profile in the app bundle."
    echo "  → Make sure your iPhone is selected (not a simulator) in Xcode, then press ⌘R."
    exit 1
fi

echo "▸ Packaging $APP…"
cd /tmp
rm -rf Payload
mkdir Payload
cp -a "$APP" Payload/
zip -qr "$IPA_NAME" Payload
mv "$IPA_NAME" "$DESKTOP/"
rm -rf Payload

echo "✓ Done: $DESKTOP/$IPA_NAME"
open "$DESKTOP"

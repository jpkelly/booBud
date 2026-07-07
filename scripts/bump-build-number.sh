#!/bin/zsh
# bump-build-number.sh — increment CFBundleVersion in Info.plist before each build.
#
# This script reads the current CFBundleVersion from booBud's Info.plist,
# increments it by 1, and writes it back. It does NOT use agvtool and does
# NOT modify the Xcode project file, so it will not cause Xcode to cancel.
#
# Called from the Xcode scheme Build pre-action.

set -euo pipefail

# Derive project root from the script's own location (scripts/ -> project root)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST="$PROJECT_ROOT/booBud/Resources/Info.plist"

if [[ ! -f "$PLIST" ]]; then
    echo "error: $PLIST not found" >&2
    exit 1
fi

CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null)

if [[ -z "$CURRENT" ]]; then
    echo "error: CFBundleVersion key not found in $PLIST" >&2
    exit 1
fi

if ! [[ "$CURRENT" =~ ^[0-9]+$ ]]; then
    echo "error: CFBundleVersion is not an integer: $CURRENT" >&2
    exit 1
fi

NEW=$((CURRENT + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW" "$PLIST"

echo "Build number: $CURRENT -> $NEW"

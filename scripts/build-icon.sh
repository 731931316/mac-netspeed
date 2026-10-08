#!/bin/bash
# Export the approved PNG master into a standard macOS .icns without changing its design.
set -euo pipefail
if [[ $# -ne 1 ]]; then
    echo "Usage: scripts/build-icon.sh /path/to/AppIcon.icns" >&2
    exit 2
fi

# Resolve source and scratch directories relative to the checkout, never a developer path.
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
BUILD_DIRECTORY="${NETSPEED_BUILD_DIR:-$PROJECT_DIRECTORY/.build/packaging}"
SOURCE_ICON="$PROJECT_DIRECTORY/Resources/AppIcon.png"
OUTPUT_ICON="$1"
mkdir -p "$BUILD_DIRECTORY" "$(dirname "$OUTPUT_ICON")"
ICON_DIRECTORY="$(mktemp -d "$BUILD_DIRECTORY/icon.XXXXXX")/AppIcon.iconset"
mkdir -p "$ICON_DIRECTORY"

# Generate pixel-exact standard and Retina representations from the same master.
for POINT_SIZE in 16 32 128 256 512; do
    /usr/bin/sips -z "$POINT_SIZE" "$POINT_SIZE" "$SOURCE_ICON" \
        --out "$ICON_DIRECTORY/icon_${POINT_SIZE}x${POINT_SIZE}.png" >/dev/null
    RETINA_SIZE=$((POINT_SIZE * 2))
    /usr/bin/sips -z "$RETINA_SIZE" "$RETINA_SIZE" "$SOURCE_ICON" \
        --out "$ICON_DIRECTORY/icon_${POINT_SIZE}x${POINT_SIZE}@2x.png" >/dev/null
done
/usr/bin/iconutil --convert icns --output "$OUTPUT_ICON" "$ICON_DIRECTORY"
echo "Application icon: $OUTPUT_ICON"

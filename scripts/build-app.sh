#!/bin/bash
# Build a standalone macOS bundle using only Xcode's Swift tools and system utilities.
set -euo pipefail

# Resolve the checkout at runtime so no developer-specific path enters the project.
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
BUILD_DIRECTORY="${NETSPEED_BUILD_DIR:-$PROJECT_DIRECTORY/.build/packaging}"
OUTPUT_DIRECTORY="${NETSPEED_OUTPUT_DIR:-$PROJECT_DIRECTORY/dist}"
ARCHITECTURES="${NETSPEED_ARCHITECTURES:-arm64 x86_64}"
APP_DIRECTORY="$OUTPUT_DIRECTORY/速喵.app"
BINARIES=()

mkdir -p "$BUILD_DIRECTORY" "$APP_DIRECTORY/Contents/MacOS" "$APP_DIRECTORY/Contents/Resources"
cd "$PROJECT_DIRECTORY"

# Separate scratch directories keep cross-architecture compiler outputs isolated.
for ARCHITECTURE in $ARCHITECTURES; do
    case "$ARCHITECTURE" in
        arm64|x86_64) ;;
        *) echo "Unsupported architecture: $ARCHITECTURE" >&2; exit 2 ;;
    esac
    swift build --configuration release --product NetSpeed --arch "$ARCHITECTURE" \
        --scratch-path "$BUILD_DIRECTORY/$ARCHITECTURE"
    BINARY_DIRECTORY="$(swift build --configuration release --arch "$ARCHITECTURE" \
        --scratch-path "$BUILD_DIRECTORY/$ARCHITECTURE" --show-bin-path)"
    BINARIES+=("$BINARY_DIRECTORY/NetSpeed")
done

# A universal binary runs natively on both Apple Silicon and Intel Macs.
/usr/bin/lipo -create "${BINARIES[@]}" -output "$APP_DIRECTORY/Contents/MacOS/NetSpeed"
/bin/chmod 755 "$APP_DIRECTORY/Contents/MacOS/NetSpeed"
/usr/bin/install -m 644 "$PROJECT_DIRECTORY/Resources/Info.plist" "$APP_DIRECTORY/Contents/Info.plist"
# Export the approved mascot at all standard macOS icon resolutions before signing.
"$PROJECT_DIRECTORY/scripts/build-icon.sh" "$APP_DIRECTORY/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$APP_DIRECTORY/Contents/Info.plist"

# Local ad-hoc signing verifies bundle integrity without a paid developer account.
/usr/bin/codesign --force --sign - "$APP_DIRECTORY"
/usr/bin/codesign --verify --strict "$APP_DIRECTORY"
echo "Application: $APP_DIRECTORY"
/usr/bin/lipo -archs "$APP_DIRECTORY/Contents/MacOS/NetSpeed"

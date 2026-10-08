#!/bin/bash
# Run the isolated Swift unit-test suites without starting the menu-bar application.
set -euo pipefail
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
BUILD_DIRECTORY="${NETSPEED_TEST_BUILD_DIR:-$PROJECT_DIRECTORY/.build/tests}"
cd "$PROJECT_DIRECTORY"
swift test --scratch-path "$BUILD_DIRECTORY"

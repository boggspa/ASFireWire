#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

cd "$ROOT_DIR"

log "cleaning release output"
rm -rf "$DERIVED" "$DIST_DIR"
mkdir -p "$DIST_DIR"

log "building unsigned Release app for manual Developer ID signing"
xcodebuild \
  -project ASFW.xcodeproj \
  -scheme ASFW \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination "platform=macOS,arch=$ARCH_NAME" \
  ASFW_APP_BUNDLE_IDENTIFIER="$APP_ID" \
  ASFW_DRIVER_BUNDLE_IDENTIFIER="$DRIVER_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_VERSION" \
  MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
  DRIVERKIT_DEPLOYMENT_TARGET="$DRIVERKIT_DEPLOYMENT_TARGET" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY= \
  DEVELOPMENT_TEAM= \
  build

built_app="$DERIVED/Build/Products/$CONFIGURATION/ASFW.app"
[[ -d "$built_app" ]] || fail "Built app not found: $built_app"

/usr/bin/ditto "$built_app" "$APP_PATH"
printf 'Release app staged for signing:\n  %s\n' "$APP_PATH"

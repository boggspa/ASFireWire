#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED="${ASFW_DERIVED_DATA:-$ROOT_DIR/build/DerivedDataLychzord}"
SOURCE_APP="${1:-$DERIVED/Build/Products/$CONFIGURATION/ASFW.app}"
APP_XCENT="$DERIVED/Build/Intermediates.noindex/ASFW.build/$CONFIGURATION/ASFW.build/ASFW.app.xcent"

ASFW_LOCAL_APP_DEST="${ASFW_LOCAL_APP_DEST:-/Applications/ASFWLychzord.app}" \
ASFW_LOCAL_APP_ENTITLEMENTS="${ASFW_LOCAL_APP_ENTITLEMENTS:-$APP_XCENT}" \
"$ROOT_DIR/tools/debug/stage_local_app.sh" "$SOURCE_APP"

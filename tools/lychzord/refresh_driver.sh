#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ASFW_DRIVER_ID="${ASFW_DRIVER_BUNDLE_IDENTIFIER:-com.lychzord.ASFWTest.ASFWDriver}" \
ASFW_LOCAL_APP="${ASFW_LOCAL_APP:-/Applications/ASFWLychzord.app}" \
"$ROOT_DIR/tools/debug/refresh_local_driver.sh" "$@"

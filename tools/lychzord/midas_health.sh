#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

ASFW_DRIVER_ID="${ASFW_DRIVER_BUNDLE_IDENTIFIER:-com.chrisizatt.ASFWLocal.ASFWDriver}" \
ASFW_LOCAL_APP="${ASFW_LOCAL_APP:-/Applications/ASFWLychzord.app}" \
ASFW_RECORDING_HEALTH_DIR="${ASFW_RECORDING_HEALTH_DIR:-$HOME/Desktop/asfw-lychzord-midas-$STAMP}" \
"$ROOT_DIR/tools/debug/recording_health.sh" "$@"

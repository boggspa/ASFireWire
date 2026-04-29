#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

cd "$ROOT_DIR"

stamp="${ASFW_PACKAGE_STAMP:-$(date +%Y%m%d-%H%M%S)}"
diagnostic_zip="$DIST_DIR/ASFWLych2Notarised-diagnostics-v$BUILD_VERSION-$stamp.zip"
mkdir -p "$DIST_DIR"

{
  printf 'ASFW Lych2 notarised diagnostics\n'
  printf 'date=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'git=%s\n' "$(git rev-parse --short HEAD)"
  printf 'branch=%s\n' "$(git rev-parse --abbrev-ref HEAD)"
  printf 'app_id=%s\n' "$APP_ID"
  printf 'driver_id=%s\n' "$DRIVER_ID"
  printf 'notary_profile=%s\n' "$NOTARY_PROFILE"
  printf '\n== identities ==\n'
  security find-identity -v -p codesigning || true
  printf '\n== preflight ==\n'
  "$SCRIPT_DIR/preflight.sh" || true
} > "$DIST_DIR/diagnostics.txt"

/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$DIST_DIR/diagnostics.txt" "$diagnostic_zip"
printf 'Diagnostic package:\n  %s\n' "$diagnostic_zip"

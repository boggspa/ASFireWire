#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

cd "$ROOT_DIR"

errors=0
check() {
  local label="$1"
  shift
  if ( "$@" ); then
    printf '[ok] %s\n' "$label"
  else
    printf '[fail] %s\n' "$label" >&2
    errors=$((errors + 1))
  fi
}

check_identity() {
  local identity
  identity="$(developer_id_identity)" || return 1
  [[ -n "$identity" ]]
}

check_notary() {
  /usr/bin/xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1
}

check_app_profile() {
  resolve_app_profile >/dev/null
}

check_driver_profile() {
  resolve_driver_profile >/dev/null
}

check_repo() {
  [[ "$(git rev-parse --short HEAD)" == "c4d6278" || -n "$(git diff --name-only)" ]]
}

printf 'ASFireWire Lych2 notarised preflight\n'
printf '  repo: %s\n' "$ROOT_DIR"
printf '  app: %s\n' "$APP_ID"
printf '  driver: %s\n' "$DRIVER_ID"
printf '  version: %s macOS=%s DriverKit=%s\n' "$BUILD_VERSION" "$MACOS_DEPLOYMENT_TARGET" "$DRIVERKIT_DEPLOYMENT_TARGET"
printf '  notary profile: %s\n\n' "$NOTARY_PROFILE"

check "repo accessible" check_repo
check "Developer ID Application identity" check_identity
check "notarytool keychain profile '$NOTARY_PROFILE'" check_notary
check "Developer ID app provisioning profile" check_app_profile
check "Developer ID DriverKit provisioning profile" check_driver_profile

if [[ "$errors" -ne 0 ]]; then
  cat >&2 <<EOF

Preflight failed. Create/refresh Developer ID distribution profiles for:
  app:    $APP_ID
  driver: $DRIVER_ID

The profiles must not be development profiles, must not contain get-task-allow,
and must not be limited to ProvisionedDevices. Store notary credentials with:

  xcrun notarytool store-credentials $NOTARY_PROFILE --team-id $TEAM_ID

Then rerun this preflight.
EOF
  exit 1
fi

printf '\nResolved profiles:\n'
printf '  app: %s\n' "$(resolve_app_profile)"
printf '  driver: %s\n' "$(resolve_driver_profile)"
printf '\nPreflight passed.\n'

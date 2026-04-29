#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRIVER_ID="${ASFW_DRIVER_BUNDLE_IDENTIFIER:-com.lychzord.ASFWTest.ASFWDriver}"
APP_ID="${ASFW_APP_BUNDLE_IDENTIFIER:-com.lychzord.ASFWTest}"

section() {
  printf '\n== %s ==\n' "$1"
}

section "Package"
printf 'Repo: %s\n' "$ROOT_DIR"
printf 'App bundle ID: %s\n' "$APP_ID"
printf 'Driver bundle ID: %s\n' "$DRIVER_ID"
printf 'ASFW_DEVELOPMENT_TEAM: %s\n' "${ASFW_DEVELOPMENT_TEAM:-<unset>}"

section "Xcode"
xcode-select -p || true
xcodebuild -version || true
xcrun --sdk driverkit --show-sdk-path || true

section "Signing Identities"
security find-identity -v -p codesigning || true

section "System Extension Developer Mode"
systemextensionsctl developer || true

section "Existing ASFW System Extensions"
systemextensionsctl list | grep -E 'ASFW|lychzord|mrmidi|chrisizatt' || true

section "Existing ASFW Processes"
pgrep -fl "ASFW|ASFWDriver|${DRIVER_ID}" || true

section "Notes"
if [[ -z "${ASFW_DEVELOPMENT_TEAM:-}" ]]; then
  echo "Set ASFW_DEVELOPMENT_TEAM before a signed build, for example:"
  echo "  export ASFW_DEVELOPMENT_TEAM=YOURTEAMID"
fi
echo "Run ./tools/lychzord/build_local.sh after preflight looks sane."

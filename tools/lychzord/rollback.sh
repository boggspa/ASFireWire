#!/usr/bin/env bash
set -euo pipefail

DRIVER_ID="${ASFW_DRIVER_BUNDLE_IDENTIFIER:-com.lychzord.ASFWTest.ASFWDriver}"
APP_PATH="${ASFW_LOCAL_APP:-/Applications/ASFWLychzord.app}"
TEAM_ID="${ASFW_DEVELOPMENT_TEAM:-}"
CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes)
      CONFIRM=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 --yes"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$CONFIRM" != true ]]; then
  echo "This will quit ASFWLychzord, request system-extension uninstall, and remove $APP_PATH."
  echo "Rerun with --yes to continue."
  exit 2
fi

if [[ -z "$TEAM_ID" ]]; then
  echo "ASFW_DEVELOPMENT_TEAM is required for systemextensionsctl uninstall." >&2
  exit 2
fi

pkill -TERM -f "$APP_PATH/Contents/MacOS/ASFW" 2>/dev/null || true
systemextensionsctl uninstall "$TEAM_ID" "$DRIVER_ID" || true
rm -rf "$APP_PATH"
echo "Rollback requested for $DRIVER_ID"

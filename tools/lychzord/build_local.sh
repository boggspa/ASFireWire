#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

APP_ID="${ASFW_APP_BUNDLE_IDENTIFIER:-com.lychzord.ASFWTest}"
DRIVER_ID="${ASFW_DRIVER_BUNDLE_IDENTIFIER:-com.lychzord.ASFWTest.ASFWDriver}"
TEAM_ID="${ASFW_DEVELOPMENT_TEAM:-}"
CONFIGURATION="${CONFIGURATION:-Debug}"
ARCH_NAME="${ARCH_NAME:-$(uname -m)}"
DERIVED="${ASFW_DERIVED_DATA:-$ROOT_DIR/build/DerivedDataLychzord}"
UNSIGNED_REFERENCE=false

usage() {
  cat <<USAGE
Usage: $0 [--unsigned-reference]

Builds the Lychzord private ASFW app with isolated bundle identifiers.

Required for signed builds:
  export ASFW_DEVELOPMENT_TEAM=YOURTEAMID

Optional:
  export ASFW_APP_BUNDLE_IDENTIFIER=$APP_ID
  export ASFW_DRIVER_BUNDLE_IDENTIFIER=$DRIVER_ID
  export ASFW_ALLOW_PROVISIONING_UPDATES=1

--unsigned-reference builds a compile/reference artifact only. It is not
installable as a DriverKit system extension.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned-reference)
      UNSIGNED_REFERENCE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$UNSIGNED_REFERENCE" == false && -z "$TEAM_ID" ]]; then
  echo "ASFW_DEVELOPMENT_TEAM is required for a signed DriverKit build." >&2
  echo "Use --unsigned-reference only for a non-installable reference build." >&2
  exit 2
fi

mkdir -p "$DERIVED"

args=(
  xcodebuild
  -project ASFW.xcodeproj
  -scheme ASFW
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED"
  -destination "platform=macOS,arch=$ARCH_NAME"
  ASFW_APP_BUNDLE_IDENTIFIER="$APP_ID"
  ASFW_DRIVER_BUNDLE_IDENTIFIER="$DRIVER_ID"
  CURRENT_PROJECT_VERSION=15
)

if [[ "${ASFW_ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
  args+=(-allowProvisioningUpdates)
fi

if [[ "$UNSIGNED_REFERENCE" == true ]]; then
  args+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGN_IDENTITY=
    DEVELOPMENT_TEAM=
  )
else
  args+=(
    DEVELOPMENT_TEAM="$TEAM_ID"
    CODE_SIGN_STYLE=Automatic
  )
  if [[ -n "${ASFW_CODE_SIGN_IDENTITY:-}" ]]; then
    args+=(CODE_SIGN_IDENTITY="$ASFW_CODE_SIGN_IDENTITY")
  fi
fi

"${args[@]}" build

printf '\nBuild output app:\n  %s\n' "$DERIVED/Build/Products/$CONFIGURATION/ASFW.app"
printf 'Driver bundle ID:\n  %s\n' "$DRIVER_ID"

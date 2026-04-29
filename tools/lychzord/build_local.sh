#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

APP_ID="${ASFW_APP_BUNDLE_IDENTIFIER:-}"
DRIVER_ID="${ASFW_DRIVER_BUNDLE_IDENTIFIER:-}"
TEAM_ID="${ASFW_DEVELOPMENT_TEAM:-}"
CONFIGURATION="${CONFIGURATION:-Debug}"
ARCH_NAME="${ARCH_NAME:-$(uname -m)}"
DERIVED="${ASFW_DERIVED_DATA:-$ROOT_DIR/build/DerivedDataLychzord}"
BUILD_VERSION="${ASFW_BUILD_VERSION:-16}"
MACOS_DEPLOYMENT_TARGET="${ASFW_MACOS_DEPLOYMENT_TARGET:-15.5}"
DRIVERKIT_DEPLOYMENT_TARGET="${ASFW_DRIVERKIT_DEPLOYMENT_TARGET:-24.0}"
UNSIGNED_REFERENCE=false
CHRIS_PREBUILT=false

usage() {
  cat <<USAGE
Usage: $0 [--unsigned-reference] [--chris-prebuilt]

Builds the Lychzord private ASFW app with isolated bundle identifiers.

Required for signed builds:
  export ASFW_DEVELOPMENT_TEAM=YOURTEAMID

Optional:
  export ASFW_APP_BUNDLE_IDENTIFIER=<app id>
  export ASFW_DRIVER_BUNDLE_IDENTIFIER=<driver id>
  export ASFW_BUILD_VERSION=$BUILD_VERSION
  export ASFW_MACOS_DEPLOYMENT_TARGET=$MACOS_DEPLOYMENT_TARGET
  export ASFW_DRIVERKIT_DEPLOYMENT_TARGET=$DRIVERKIT_DEPLOYMENT_TARGET
  export ASFW_ALLOW_PROVISIONING_UPDATES=1

--unsigned-reference builds a compile/reference artifact only. It is not
installable as a DriverKit system extension.

--chris-prebuilt builds the Chris-ID prebuilt base with Xcode signing disabled.
Run ./tools/lychzord/sign_chris_prebuilt.sh afterwards to embed the approved
ASFWLocal provisioning profiles and sign the app/dext.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --unsigned-reference)
      UNSIGNED_REFERENCE=true
      shift
      ;;
    --chris-prebuilt)
      CHRIS_PREBUILT=true
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

if [[ "$CHRIS_PREBUILT" == true && -z "$TEAM_ID" ]]; then
  TEAM_ID="${ASFW_CHRIS_DEVELOPMENT_TEAM:-8CZML8FK2D}"
fi

if [[ "$CHRIS_PREBUILT" == true ]]; then
  APP_ID="${APP_ID:-com.chrisizatt.ASFWLocal}"
  DRIVER_ID="${DRIVER_ID:-com.chrisizatt.ASFWLocal.ASFWDriver}"
  UNSIGNED_REFERENCE=true
fi

APP_ID="${APP_ID:-com.chrisizatt.ASFWLocal}"
DRIVER_ID="${DRIVER_ID:-com.chrisizatt.ASFWLocal.ASFWDriver}"

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
  CURRENT_PROJECT_VERSION="$BUILD_VERSION"
  MACOSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
  DRIVERKIT_DEPLOYMENT_TARGET="$DRIVERKIT_DEPLOYMENT_TARGET"
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
printf 'Version/deployment:\n  CFBundleVersion=%s, macOS=%s, DriverKit=%s\n' "$BUILD_VERSION" "$MACOS_DEPLOYMENT_TARGET" "$DRIVERKIT_DEPLOYMENT_TARGET"

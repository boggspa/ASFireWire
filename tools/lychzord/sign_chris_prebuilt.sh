#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED="${ASFW_DERIVED_DATA:-$ROOT_DIR/build/DerivedDataLychzord}"
APP_PATH="${1:-$DERIVED/Build/Products/$CONFIGURATION/ASFW.app}"
REFERENCE_APP="${ASFW_CHRIS_REFERENCE_APP:-/Applications/ASFWLocal.app}"
SIGN_IDENTITY="${ASFW_CODESIGN_IDENTITY:-}"
APP_PROFILE="${ASFW_APP_PROFILE:-}"
DRIVER_PROFILE="${ASFW_DRIVER_PROFILE:-}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found: $APP_PATH" >&2
  echo "Run ./tools/lychzord/build_local.sh --chris-prebuilt first." >&2
  exit 1
fi

if [[ ! -d "$REFERENCE_APP" ]]; then
  echo "Reference signed app not found: $REFERENCE_APP" >&2
  exit 1
fi

ref_dext="$(find "$REFERENCE_APP/Contents/Library/SystemExtensions" -maxdepth 1 -type d -name '*.dext' -print | head -n 1)"
built_dext="$(find "$APP_PATH/Contents/Library/SystemExtensions" -maxdepth 1 -type d -name '*.dext' -print | head -n 1)"

if [[ -z "$ref_dext" || -z "$built_dext" ]]; then
  echo "Reference or built dext missing." >&2
  exit 1
fi

APP_PROFILE="${APP_PROFILE:-$REFERENCE_APP/Contents/embedded.provisionprofile}"
DRIVER_PROFILE="${DRIVER_PROFILE:-$ref_dext/embedded.provisionprofile}"

if [[ ! -f "$APP_PROFILE" ]]; then
  echo "App provisioning profile not found: $APP_PROFILE" >&2
  exit 1
fi

if [[ ! -f "$DRIVER_PROFILE" ]]; then
  echo "Driver provisioning profile not found: $DRIVER_PROFILE" >&2
  exit 1
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$built_dext/Info.plist")"
expected_dext="$(dirname "$built_dext")/$bundle_id.dext"
if [[ "$built_dext" != "$expected_dext" ]]; then
  rm -rf "$expected_dext"
  mv "$built_dext" "$expected_dext"
  built_dext="$expected_dext"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(/usr/bin/codesign -dv --verbose=4 "$REFERENCE_APP" 2>&1 | /usr/bin/sed -n 's/^Authority=//p' | /usr/bin/head -n 1)"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "Unable to determine signing identity. Set ASFW_CODESIGN_IDENTITY." >&2
  exit 1
fi

install -m 0644 "$APP_PROFILE" "$APP_PATH/Contents/embedded.provisionprofile"
install -m 0644 "$DRIVER_PROFILE" "$built_dext/embedded.provisionprofile"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
app_entitlements="$tmp_dir/app.entitlements"
driver_entitlements="$tmp_dir/driver.entitlements"

/usr/bin/codesign -d --entitlements :- "$REFERENCE_APP" 2>/dev/null > "$app_entitlements"
/usr/bin/codesign -d --entitlements :- "$ref_dext" 2>/dev/null > "$driver_entitlements"

for nested in "$APP_PATH"/Contents/MacOS/*.dylib; do
  [[ -f "$nested" ]] || continue
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp=none "$nested"
done

/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --options runtime --entitlements "$driver_entitlements" --timestamp=none "$built_dext"
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --options runtime --entitlements "$app_entitlements" --timestamp=none "$APP_PATH"
/usr/bin/codesign --verify --strict --deep --verbose=2 "$APP_PATH"

printf 'Signed Chris prebuilt app:\n  %s\n' "$APP_PATH"
printf 'Embedded dext:\n  %s\n' "$built_dext"
printf 'Signing identity:\n  %s\n' "$SIGN_IDENTITY"
printf 'Provisioning profiles:\n  app: %s\n  driver: %s\n' "$APP_PROFILE" "$DRIVER_PROFILE"

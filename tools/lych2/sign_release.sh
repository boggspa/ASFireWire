#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

cd "$ROOT_DIR"

[[ -d "$APP_PATH" ]] || fail "Release app not found: $APP_PATH. Run tools/lych2/build_release.sh first."

sys_ext_dir="$APP_PATH/Contents/Library/SystemExtensions"
dext_path="$sys_ext_dir/$DRIVER_ID.dext"
if [[ ! -d "$dext_path" ]]; then
  found="$(/usr/bin/find "$sys_ext_dir" -maxdepth 1 -type d -name '*.dext' -print | /usr/bin/head -n 1 || true)"
  [[ -n "$found" ]] || fail "No embedded dext found in $sys_ext_dir"
  rm -rf "$dext_path"
  mv "$found" "$dext_path"
fi

identity="$(developer_id_identity)"
app_profile="$(resolve_app_profile)"
driver_profile="$(resolve_driver_profile)"

install -m 0644 "$app_profile" "$APP_PATH/Contents/embedded.provisionprofile"
install -m 0644 "$driver_profile" "$dext_path/embedded.provisionprofile"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
app_entitlements="$tmp_dir/app.entitlements"
driver_entitlements="$tmp_dir/driver.entitlements"

make_resolved_entitlements "$ROOT_DIR/ASFW/App.entitlements" "$app_entitlements"
make_resolved_entitlements "$ROOT_DIR/ASFWDriver/ASFWDriver.entitlements" "$driver_entitlements"

plist_set_or_add_string "$app_entitlements" 'com.apple.application-identifier' "$TEAM_ID.$APP_ID"
plist_set_or_add_string "$app_entitlements" 'com.apple.developer.team-identifier' "$TEAM_ID"
plist_delete_if_present "$app_entitlements" 'com.apple.security.get-task-allow'
plist_delete_if_present "$app_entitlements" 'get-task-allow'

plist_set_or_add_string "$driver_entitlements" 'application-identifier' "$TEAM_ID.$DRIVER_ID"
plist_set_or_add_string "$driver_entitlements" 'com.apple.application-identifier' "$TEAM_ID.$DRIVER_ID"
plist_set_or_add_string "$driver_entitlements" 'com.apple.developer.team-identifier' "$TEAM_ID"
plist_delete_if_present "$driver_entitlements" 'com.apple.security.get-task-allow'
plist_delete_if_present "$driver_entitlements" 'get-task-allow'

log "signing nested dylibs"
while IFS= read -r nested; do
  /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$nested"
done < <(/usr/bin/find "$APP_PATH/Contents/MacOS" -maxdepth 1 -type f -name '*.dylib' -print)

log "signing DriverKit extension"
/usr/bin/codesign --force --options runtime --timestamp --entitlements "$driver_entitlements" --sign "$identity" "$dext_path"

log "signing app"
/usr/bin/codesign --force --options runtime --timestamp --entitlements "$app_entitlements" --sign "$identity" "$APP_PATH"

/usr/bin/codesign --verify --strict --deep --verbose=4 "$APP_PATH"

printf 'Signed Developer ID app:\n  %s\n' "$APP_PATH"
printf 'Identity:\n  %s\n' "$identity"
printf 'Profiles:\n  app: %s\n  driver: %s\n' "$app_profile" "$driver_profile"

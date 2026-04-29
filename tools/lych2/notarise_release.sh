#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

cd "$ROOT_DIR"

[[ -d "$APP_PATH" ]] || fail "Release app not found: $APP_PATH"

stamp="${ASFW_PACKAGE_STAMP:-$(date +%Y%m%d-%H%M%S)}"
upload_zip="$DIST_DIR/ASFWLych2Notarised-notary-upload-v$BUILD_VERSION-$stamp.zip"
notary_log="$DIST_DIR/notary-v$BUILD_VERSION-$stamp.json"
final_zip="$DIST_DIR/ASFWLych2Notarised-v$BUILD_VERSION-$stamp.zip"

log "creating notary upload zip"
/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$APP_PATH" "$upload_zip"

log "submitting to Apple notary service"
/usr/bin/xcrun notarytool submit "$upload_zip" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json | tee "$notary_log"

log "stapling notarisation ticket"
/usr/bin/xcrun stapler staple "$APP_PATH"
/usr/bin/xcrun stapler validate "$APP_PATH"

log "validating Gatekeeper assessment"
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_PATH"

log "creating final distributable zip"
/usr/bin/ditto -c -k --keepParent --sequesterRsrc "$APP_PATH" "$final_zip"
/usr/bin/shasum -a 256 "$final_zip" > "$final_zip.sha256"

printf 'Notarised app:\n  %s\n' "$APP_PATH"
printf 'Distributable zip:\n  %s\n' "$final_zip"
printf 'SHA-256:\n  %s\n' "$(cat "$final_zip.sha256")"

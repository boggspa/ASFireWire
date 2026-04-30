#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_ID="${ASFW_APP_BUNDLE_IDENTIFIER:-com.chrisizatt.ASFWLocal}"
DRIVER_ID="${ASFW_DRIVER_BUNDLE_IDENTIFIER:-com.chrisizatt.ASFWLocal.ASFWDriver}"
TEAM_ID="${ASFW_DEVELOPMENT_TEAM:-8CZML8FK2D}"
BUILD_VERSION="${ASFW_BUILD_VERSION:-16}"
MACOS_DEPLOYMENT_TARGET="${ASFW_MACOS_DEPLOYMENT_TARGET:-15.5}"
DRIVERKIT_DEPLOYMENT_TARGET="${ASFW_DRIVERKIT_DEPLOYMENT_TARGET:-24.0}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCH_NAME="${ARCH_NAME:-$(uname -m)}"
DERIVED="${ASFW_DERIVED_DATA:-$ROOT_DIR/build/DerivedDataLych2}"
DIST_DIR="${ASFW_DIST_DIR:-$ROOT_DIR/build/lych2}"
APP_NAME="${ASFW_RELEASE_APP_NAME:-ASFWLych2Notarised.app}"
APP_PATH="${ASFW_RELEASE_APP:-$DIST_DIR/$APP_NAME}"
NOTARY_PROFILE="${ASFW_NOTARY_PROFILE:-asfw-notary}"
DEVELOPER_ID_IDENTITY="${ASFW_DEVELOPER_ID_IDENTITY:-}"

log() {
  printf '[lych2] %s\n' "$*"
}

fail() {
  printf '[lych2] ERROR: %s\n' "$*" >&2
  exit 1
}

profile_search_dirs() {
  printf '%s\n' \
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
    "$HOME/Library/MobileDevice/Provisioning Profiles"
}

decode_profile() {
  local profile="$1"
  local plist="$2"
  /usr/bin/security cms -D -i "$profile" > "$plist"
}

plist_print() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print $key" "$plist" 2>/dev/null || true
}

profile_app_identifier() {
  local plist="$1"
  local value
  value="$(plist_print "$plist" ':Entitlements:com.apple.application-identifier')"
  if [[ -z "$value" ]]; then
    value="$(plist_print "$plist" ':Entitlements:application-identifier')"
  fi
  printf '%s\n' "$value"
}

profile_has_key() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Print :Entitlements:$key" "$plist" >/dev/null 2>&1
}

profile_true() {
  local plist="$1"
  local key="$2"
  [[ "$(plist_print "$plist" ":Entitlements:$key")" == "true" ]]
}

profile_has_devices() {
  local plist="$1"
  /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$plist" >/dev/null 2>&1
}

profile_get_task_allow() {
  local plist="$1"
  local value
  value="$(plist_print "$plist" ':Entitlements:com.apple.security.get-task-allow')"
  if [[ -z "$value" ]]; then
    value="$(plist_print "$plist" ':Entitlements:get-task-allow')"
  fi
  printf '%s\n' "$value"
}

validate_profile() {
  local profile="$1"
  local bundle_id="$2"
  local kind="$3"
  local plist="$4"
  shift 4

  decode_profile "$profile" "$plist" || return 1

  local app_identifier
  app_identifier="$(profile_app_identifier "$plist")"
  [[ "$app_identifier" == "$TEAM_ID.$bundle_id" ]] || return 1

  [[ "$(profile_get_task_allow "$plist")" != "true" ]] || return 1
  ! profile_has_devices "$plist" || return 1

  case "$kind" in
    app)
      profile_true "$plist" 'com.apple.developer.system-extension.install' || return 1
      profile_has_key "$plist" 'com.apple.developer.driverkit.userclient-access' || return 1
      ;;
  esac
}

find_profile() {
  local bundle_id="$1"
  local kind="$2"
  shift 2

  local explicit=""
  case "$kind" in
    app) explicit="${ASFW_APP_PROFILE:-}" ;;
    driver) explicit="${ASFW_DRIVER_PROFILE:-}" ;;
  esac

  local tmp
  tmp="$(mktemp)"

  if [[ -n "$explicit" ]]; then
    [[ -f "$explicit" ]] || fail "$kind profile not found: $explicit"
    validate_profile "$explicit" "$bundle_id" "$kind" "$tmp" "$@" ||
      fail "$kind profile is not a matching Developer ID distribution profile: $explicit. For the app profile, Apple must grant com.apple.developer.driverkit.userclient-access; DriverKit Communicates with Drivers is not the macOS substitute."
    rm -f "$tmp"
    printf '%s\n' "$explicit"
    return 0
  fi

  local matches=()
  local dir profile
  while IFS= read -r dir; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r profile; do
      if validate_profile "$profile" "$bundle_id" "$kind" "$tmp" "$@"; then
        matches+=("$profile")
      fi
    done < <(/usr/bin/find "$dir" -maxdepth 1 -type f \( -name '*.provisionprofile' -o -name '*.mobileprovision' \) -print 2>/dev/null)
  done < <(profile_search_dirs)

  if [[ "${#matches[@]}" -eq 0 ]]; then
    local env_name
    case "$kind" in
      app) env_name="ASFW_APP_PROFILE" ;;
      driver) env_name="ASFW_DRIVER_PROFILE" ;;
      *) env_name="ASFW_PROFILE" ;;
    esac
    fail "No matching Developer ID distribution $kind profile found for $bundle_id. Set $env_name."
  fi
  if [[ "${#matches[@]}" -gt 1 ]]; then
    local env_name
    case "$kind" in
      app) env_name="ASFW_APP_PROFILE" ;;
      driver) env_name="ASFW_DRIVER_PROFILE" ;;
      *) env_name="ASFW_PROFILE" ;;
    esac
    printf '[lych2] Multiple matching %s profiles found:\n' "$kind" >&2
    printf '  %s\n' "${matches[@]}" >&2
    fail "Set $env_name to the intended profile."
  fi
  rm -f "$tmp"
  printf '%s\n' "${matches[0]}"
}

developer_id_identity() {
  if [[ -n "$DEVELOPER_ID_IDENTITY" ]]; then
    printf '%s\n' "$DEVELOPER_ID_IDENTITY"
    return 0
  fi

  local identity
  identity="$(/usr/bin/security find-identity -v -p codesigning |
    /usr/bin/awk '/Developer ID Application: Christopher Izatt \(8CZML8FK2D\)/ { print $2; exit }')"
  [[ -n "$identity" ]] || fail "Developer ID Application identity for team $TEAM_ID was not found."
  printf '%s\n' "$identity"
}

resolve_app_profile() {
  find_profile "$APP_ID" app
}

resolve_driver_profile() {
  find_profile "$DRIVER_ID" driver
}

make_resolved_entitlements() {
  local src="$1"
  local dst="$2"
  /usr/bin/perl -0pe \
    "s/\\\$\\(ASFW_APP_BUNDLE_IDENTIFIER\\)/$APP_ID/g; s/\\\$\\(ASFW_DRIVER_BUNDLE_IDENTIFIER\\)/$DRIVER_ID/g" \
    "$src" > "$dst"
  /usr/bin/plutil -convert xml1 "$dst"
}

plist_set_or_add_string() {
  local plist="$1"
  local key="$2"
  local value="$3"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
}

plist_delete_if_present() {
  local plist="$1"
  local key="$2"
  /usr/libexec/PlistBuddy -c "Delete :$key" "$plist" >/dev/null 2>&1 || true
}

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PARENT_DIR="$(dirname "$ROOT_DIR")"
REPO_NAME="$(basename "$ROOT_DIR")"
STAMP="${ASFW_PACKAGE_STAMP:-$(date +%Y%m%d-%H%M%S)}"
ARTIFACT_DIR="${ASFW_ARTIFACT_DIR:-$PARENT_DIR/${REPO_NAME}-artifacts}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED="${ASFW_DERIVED_DATA:-$ROOT_DIR/build/DerivedDataLychzord}"
BUILD_VERSION="${ASFW_BUILD_VERSION:-16}"
PACKAGE_LABEL="${ASFW_PACKAGE_LABEL:-v${BUILD_VERSION}-lych}"
APP_PACKAGE_KIND="${ASFW_APP_PACKAGE_KIND:-reference-app}"
SOURCE_ZIP="$ARTIFACT_DIR/${REPO_NAME}-source-$PACKAGE_LABEL-$STAMP.zip"
APP_ZIP="$ARTIFACT_DIR/${REPO_NAME}-$APP_PACKAGE_KIND-$PACKAGE_LABEL-$STAMP.zip"
APP_PATH="${ASFW_REFERENCE_APP:-$DERIVED/Build/Products/$CONFIGURATION/ASFW.app}"

mkdir -p "$ARTIFACT_DIR"
export COPYFILE_DISABLE=1

(
  cd "$PARENT_DIR"
  bsdtar -a -cf "$SOURCE_ZIP" \
    --exclude "$REPO_NAME/.git" \
    --exclude "$REPO_NAME/build" \
    --exclude "$REPO_NAME/build-*" \
    --exclude "$REPO_NAME/**/xcuserdata" \
    --exclude "$REPO_NAME/**/*.xcuserstate" \
    --exclude "$REPO_NAME/.DS_Store" \
    --exclude "$REPO_NAME/**/.DS_Store" \
    --exclude "*/.DS_Store" \
    --exclude "__MACOSX" \
    --exclude "$REPO_NAME/**/*.mobileprovision" \
    --exclude "$REPO_NAME/**/*.provisionprofile" \
    --exclude "$REPO_NAME/**/*.p12" \
    --exclude "$REPO_NAME/**/*.cer" \
    "$REPO_NAME"
)

echo "Source package: $SOURCE_ZIP"

if [[ -d "$APP_PATH" ]]; then
  ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$APP_PATH" "$APP_ZIP"
  echo "Reference app package: $APP_ZIP"
else
  echo "Reference app not found, skipped: $APP_PATH"
fi

#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MailClient.xcodeproj"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
ARCHIVE_DIR="$BUILD_DIR/Release"
APP_NAME="MailStrea.app"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
STAGING_DIR="$BUILD_DIR/dmg"
DMG_PATH="$ARCHIVE_DIR/MailStrea.dmg"

mkdir -p "$BUILD_DIR" "$ARCHIVE_DIR"

cd "$ROOT_DIR"
xcodegen generate

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme MailClient \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "MailStrea" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "DMG created at: $DMG_PATH"

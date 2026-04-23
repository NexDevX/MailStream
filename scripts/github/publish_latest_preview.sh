#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RELEASE_TAG="${RELEASE_TAG:-latest-main}"
RELEASE_TITLE="${RELEASE_TITLE:-Latest Preview}"
DMG_PATH="$ROOT_DIR/build/Release/MailStrea.dmg"
CHECKSUM_PATH="$ROOT_DIR/build/Release/MailStrea.dmg.sha256"
NOTES_FILE="$(mktemp)"

cat > "$NOTES_FILE" <<EOF
Automated preview build from commit \`${GITHUB_SHA:-unknown}\`.

- Branch: \`${GITHUB_REF_NAME:-main}\`
- Installer: \`MailStrea.dmg\`
- Channel: rolling prerelease

This release is updated on every push to \`main\`.
EOF

if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  gh release upload "$RELEASE_TAG" "$DMG_PATH" "$CHECKSUM_PATH" --clobber
  gh release edit "$RELEASE_TAG" \
    --title "$RELEASE_TITLE" \
    --notes-file "$NOTES_FILE" \
    --prerelease \
    --target "${GITHUB_SHA:-HEAD}"
else
  gh release create "$RELEASE_TAG" "$DMG_PATH" "$CHECKSUM_PATH" \
    --title "$RELEASE_TITLE" \
    --notes-file "$NOTES_FILE" \
    --prerelease \
    --latest=false \
    --target "${GITHUB_SHA:-HEAD}"
fi

rm -f "$NOTES_FILE"

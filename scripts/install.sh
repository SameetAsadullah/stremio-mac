#!/usr/bin/env bash
# Copies a built Stremio.app to ~/Applications. Never touches /Applications/Stremio.app, and
# replaces an existing copy only when it is this app.
set -euo pipefail

SRC="${1:?Usage: install.sh path/to/Stremio.app}"
ID="com.sameetasadullah.stremio-mac"
DEST="$HOME/Applications/Stremio.app"

bundle_id() { /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true; }

if [ "$(bundle_id "$SRC")" != "$ID" ]; then
  echo "$SRC is not this app (expected $ID)." >&2
  exit 1
fi
if [ -e "$DEST" ] && [ "$(bundle_id "$DEST")" != "$ID" ]; then
  echo "Refusing to replace $DEST: its bundle identifier is not $ID." >&2
  exit 1
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$SRC" "$DEST"
codesign --verify --deep --strict "$DEST"
echo "Installed $DEST (signature valid)."

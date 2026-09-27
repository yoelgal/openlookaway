#!/bin/bash
# OpenLookAway installer: curl -fsSL https://lookaway.yoelgal.com/install.sh | bash
#
# Why a script? The app isn't notarized (no paid Apple Developer account). Files downloaded
# by a browser get a quarantine flag that makes macOS block unnotarized apps. Files fetched
# with curl don't, so the app opens normally. Read this script before running it, it's short.
set -euo pipefail

REPO="yoelgal/openlookaway"
NAME="OpenLookAway.app"
URL="https://github.com/$REPO/releases/latest/download/OpenLookAway.zip"

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; red=$'\033[31m'; reset=$'\033[0m'
step() { printf "%s==>%s %s\n" "$bold" "$reset" "$1"; }
fail() { printf "%sError:%s %s\n" "$red" "$reset" "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "OpenLookAway is a macOS app."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "OpenLookAway needs macOS 14 (Sonoma) or newer."

# /Applications is writable for admin users; fall back to ~/Applications otherwise.
DEST="/Applications"
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

step "Downloading the latest release"
curl -fL --progress-bar "$URL" -o "$tmp/app.zip" || fail "Download failed. Check your connection and try again."
ditto -x -k "$tmp/app.zip" "$tmp"

if pgrep -x OpenLookAway >/dev/null; then
  step "Quitting the running copy"
  osascript -e 'quit app id "com.yoelgal.openlookaway"' >/dev/null 2>&1 || true
  sleep 1
  pkill -x OpenLookAway 2>/dev/null || true
fi

step "Installing to $DEST"
rm -rf "$DEST/$NAME"
mv "$tmp/$NAME" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/$NAME" 2>/dev/null || true

step "Opening OpenLookAway"
open "$DEST/$NAME"

printf "\n%s✓ Installed.%s Look for the eye icon in your menu bar.\n" "$green" "$reset"
printf "%s  Update: run this command again, or use \"Check for Updates…\" in the menu.\n" "$dim"
printf "  Uninstall: quit the app and drag it from %s to the Trash.%s\n" "$DEST" "$reset"

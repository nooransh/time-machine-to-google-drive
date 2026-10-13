#!/bin/bash
# Installs tm2gdrive and rclone with Homebrew.
set -e
cd "$(dirname "$0")"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "tm2gdrive runs on macOS." >&2
    exit 1
fi
if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required. Install it from https://brew.sh and run this again." >&2
    exit 1
fi

echo "==> Installing rclone"
brew install rclone

BIN="$(brew --prefix)/bin"
echo "==> Installing tm2gdrive to $BIN"
install -m 755 tm2gdrive "$BIN/tm2gdrive"

echo
if [[ -f "/Library/Application Support/tm2gdrive/config" ]]; then
    echo "Updated. Apply the update to the background service with:  tm2gdrive setup"
else
    echo "Installed. Next: create your Google client ID (README, step 2), then run:  tm2gdrive setup"
fi

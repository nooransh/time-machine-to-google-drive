#!/bin/bash
# Installs tm2gdrive and its dependencies (restic, rclone) with Homebrew.
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

echo "==> Installing restic and rclone"
brew install restic rclone

BIN="$(brew --prefix)/bin"
echo "==> Installing tm2gdrive to $BIN"
install -m 755 tm2gdrive "$BIN/tm2gdrive"

echo
echo "Installed. Next steps (see README.md):"
echo "  1. Create your Google client ID   (README: Step 2)"
echo "  2. Give Terminal Full Disk Access  (README: Step 3)"
echo "  3. tm2gdrive setup"

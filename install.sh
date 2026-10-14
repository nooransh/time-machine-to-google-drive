#!/bin/bash
# Installs the tm2gdrive command. "tm2gdrive setup" installs the rest
# (FUSE-T, Samba and rclone with tm2gdrive's patches).
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

BIN="$(brew --prefix)/bin"
echo "==> Installing tm2gdrive to $BIN"
install -m 755 tm2gdrive "$BIN/tm2gdrive"

echo
if [[ -f "/Library/LaunchDaemons/io.github.nooranshdhaka.tm2gdrive.plist" ]]; then
    echo "tm2gdrive 2.x is installed. Remove it first (your 2.x backups stay in Google Drive):"
    echo "    sudo /Library/Application\\ Support/tm2gdrive/bin/tm2gdrive uninstall"
    echo "Then run:  tm2gdrive setup"
elif [[ -f "$HOME/Library/Application Support/tm2gdrive/config" ]]; then
    echo "Updated. Apply the update to the background service with:  tm2gdrive setup"
else
    echo "Installed. Next: create your Google client ID (README, step 2), then run:  tm2gdrive setup"
fi

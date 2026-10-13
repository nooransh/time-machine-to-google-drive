#!/bin/bash
#
# Real-world integration test (macOS only, run as root; used by CI).
#
# Makes a real Time Machine backup onto an APFS disk image, then runs tm2gdrive
# against it with real tmutil / diskutil / mount_apfs. A local folder stands in
# for Google Drive. Finally restores the backup and compares the files.
#
#   sudo -E bash test/integration-macos.sh
#
set -eu -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
TOOL="$HERE/../tm2gdrive"

[[ "$(uname -s)" == "Darwin" ]] || { echo "macOS only" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo -E bash $0" >&2; exit 1; }

step() { printf '\n=== %s\n' "$*"; }

WORK=$(mktemp -d /private/tmp/tm2gdrive-it.XXXXXX)
VOL="TM2GDRIVE-IT"
DEST="/Volumes/$VOL"
DATA_DIR="/Users/Shared/tm2gdrive-it"

cleanup() {
    tmutil disable >/dev/null 2>&1 || true
    tmutil removedestination "$(tmutil destinationinfo | awk -F': ' '/^ID/ { print $2; exit }')" >/dev/null 2>&1 || true
    umount "$WORK/mnt" >/dev/null 2>&1 || true
    hdiutil detach "$DEST" -force >/dev/null 2>&1 || true
}
trap cleanup EXIT

step "Test data"
mkdir -p "$DATA_DIR"
echo "hello from tm2gdrive $(date)" > "$DATA_DIR/hello.txt"
head -c 2000000 /dev/urandom > "$DATA_DIR/random.bin"
ls -l "$DATA_DIR"

step "APFS disk image as the Time Machine disk"
hdiutil create -size 8g -fs APFS -volname "$VOL" -type SPARSE "$WORK/tm"
hdiutil attach "$WORK/tm.sparseimage"
tmutil setdestination "$DEST"
tmutil destinationinfo

step "Exclude everything except the test data, to keep the backup small"
exclude() { tmutil addexclusion -p "$1" 2>/dev/null || echo "  (could not exclude $1)"; }
for p in /System/Volumes/Data/*; do
    name=${p##*/}
    [[ "$name" == "Users" ]] && continue
    exclude "/$name"
done
for p in /Users/*; do
    [[ "$p" == "/Users/Shared" ]] || exclude "$p"
done
for p in /Users/Shared/*; do
    [[ "$p" == "$DATA_DIR" ]] || exclude "$p"
done

step "Run a Time Machine backup"
tmutil startbackup --block || true
tmutil listbackups -d "$DEST" || true
diskutil apfs listSnapshots "$DEST" || true
diskutil apfs listSnapshots "$DEST" | grep -q "com.apple.TimeMachine" \
    || { echo "Time Machine did not create a backup on this runner; cannot continue." >&2; exit 1; }

step "Second Time Machine backup with a changed file"
echo "changed $(date)" >> "$DATA_DIR/hello.txt"
sleep 5
tmutil startbackup --block || true
diskutil apfs listSnapshots "$DEST"

step "tm2gdrive configuration (a local folder stands in for Google Drive)"
export TM2GDRIVE_CONFIG_DIR="$WORK/config"
export TM2GDRIVE_MOUNT_POINT="$WORK/mnt"
mkdir -p "$TM2GDRIVE_CONFIG_DIR"
cat > "$TM2GDRIVE_CONFIG_DIR/config" <<EOF
DRIVE_FOLDER="$WORK/drive"
TM_DEST="$DEST"
DAILY_UPLOAD_GB=0
EOF
printf '[gdrive]\ntype = local\n' > "$TM2GDRIVE_CONFIG_DIR/rclone.conf"
echo "integration-test-password" > "$TM2GDRIVE_CONFIG_DIR/restic-password"
"$TOOL" restic init

step "tm2gdrive inspect"
"$TOOL" inspect
# CI runners may not grant Full Disk Access the way Terminal does; root can read the test data anyway.
export TM2GDRIVE_SKIP_FDA_CHECK=1

step "tm2gdrive backup"
"$TOOL" backup
"$TOOL" status
"$TOOL" snapshots

step "tm2gdrive backup again (nothing to do)"
"$TOOL" backup | tee "$WORK/second-run.txt"
grep -q "Nothing to upload" "$WORK/second-run.txt"

step "Restore and compare"
"$TOOL" restore latest "$WORK/restore"
restored=$(find "$WORK/restore" -path "*Users/Shared/tm2gdrive-it/hello.txt" | head -1)
echo "restored: $restored"
[[ -n "$restored" ]]
cmp "$restored" "$DATA_DIR/hello.txt"
cmp "$(dirname "$restored")/random.bin" "$DATA_DIR/random.bin"
"$TOOL" verify 100%

step "PASSED"

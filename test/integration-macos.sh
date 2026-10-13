#!/bin/bash
#
# Real-world integration test (macOS only, run as root; used by CI).
#
# WARNING: this reconfigures Time Machine on the machine it runs on (backup
# destination, exclusions). It only runs on disposable CI machines, or when
# TM2GDRIVE_DESTRUCTIVE_OK=1 is set. Never run it on a Mac you rely on.
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
if [[ "${CI:-}" != "true" && "${TM2GDRIVE_DESTRUCTIVE_OK:-}" != "1" ]]; then
    echo "Refusing to run: this test reconfigures Time Machine. It is meant for disposable CI machines." >&2
    exit 1
fi
if tmutil destinationinfo 2>/dev/null | grep -q '^ID' && [[ "${TM2GDRIVE_DESTRUCTIVE_OK:-}" != "1" ]]; then
    echo "Refusing to run: this machine already has a Time Machine destination." >&2
    exit 1
fi

step() { printf '\n=== %s\n' "$*"; }

WORK=$(mktemp -d /private/tmp/tm2gdrive-it.XXXXXX)
VOL="TM2GDRIVE-IT"
DEST="/Volumes/$VOL"
DATA_DIR="/Users/Shared/tm2gdrive-it"

DEST_ID=""
EXCLUDED=()
cleanup() {
    # Undo only what this test changed.
    local p
    for p in ${EXCLUDED[@]+"${EXCLUDED[@]}"}; do
        tmutil removeexclusion -p "$p" >/dev/null 2>&1 || true
    done
    [[ -n "$DEST_ID" ]] && { tmutil removedestination "$DEST_ID" >/dev/null 2>&1 || true; }
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
tmutil setdestination -a "$DEST"
tmutil destinationinfo
DEST_ID=$(tmutil destinationinfo | awk -v m="$DEST" '
    /^ID/ { id = $3 } /^Mount Point/ { sub(/^Mount Point *: */, ""); if ($0 == m) found = 1 }
    /^====/ { if (found) { print id; exit } found = 0 } END { if (found) print id }')
echo "test destination ID: $DEST_ID"

step "Exclude everything except the test data, to keep the backup small"
exclude() {
    if tmutil addexclusion -p "$1" 2>/dev/null; then EXCLUDED+=("$1"); else echo "  (could not exclude $1)"; fi
}
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

step "tm2gdrive configuration (a local folder stands in for Google Drive)"
export TM2GDRIVE_CONFIG_DIR="$WORK/config"
export TM2GDRIVE_MOUNT_POINT="$WORK/mnt"
mkdir -p "$TM2GDRIVE_CONFIG_DIR"
printf 'DRIVE_FOLDER="%s"\nDAILY_UPLOAD_GB=0\n' "$WORK/drive" > "$TM2GDRIVE_CONFIG_DIR/config"
printf '[gdrive]\ntype = local\n' > "$TM2GDRIVE_CONFIG_DIR/rclone.conf"
echo "integration-test-password" > "$TM2GDRIVE_CONFIG_DIR/restic-password"
"$TOOL" restic init

step "tm2gdrive finds and reads the real disk"
"$TOOL" inspect 2>&1 | tee "$WORK/inspect.txt" || true
grep -q "chosen disk: $DEST   filesystem: apfs   device: /dev/disk" "$WORK/inspect.txt"
echo "OK: Time Machine disk detected; APFS and its device node read correctly"

step "Run a Time Machine backup"
# backupd is not always running on CI machines; try to start it.
tmutil enable || true
launchctl enable system/com.apple.backupd || true
launchctl enable system/com.apple.backupd-helper || true
launchctl kickstart system/com.apple.backupd-helper || true
sleep 5
tmutil startbackup --block || true
tmutil listbackups -d "$DEST" || true
diskutil apfs listSnapshots "$DEST" || true
if ! diskutil apfs listSnapshots "$DEST" | grep -q "com.apple.TimeMachine"; then
    echo "::warning::Time Machine can't run on this CI machine; skipped the snapshot part of the integration test."
    exit 0
fi

step "Second Time Machine backup with a changed file"
echo "changed $(date)" >> "$DATA_DIR/hello.txt"
sleep 5
tmutil startbackup --block || true
diskutil apfs listSnapshots "$DEST"

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

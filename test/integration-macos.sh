#!/bin/bash
#
# End-to-end test on a real Mac (used by CI).
#
# Runs the real tm2gdrive setup, background service, NFS mount, encrypted disk
# image and Time Machine destination. A local folder stands in for Google
# Drive. Then it writes data to the backup disk and checks that it arrives in
# "Drive" encrypted, survives restarts and an rclone crash, can be read back
# with an empty cache, and can be opened again as if on a new Mac.
#
# WARNING: installs a system service and changes Time Machine settings. It
# only runs on disposable CI machines, or with TM2GDRIVE_DESTRUCTIVE_OK=1.
#
# Run as a normal user with sudo rights: bash test/integration-macos.sh
#
# shellcheck disable=SC2016,SC2034,SC2001,SC2009  # checks are passed to eval on purpose
set -u -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
TOOL="$HERE/../tm2gdrive"
VOLUME="/Volumes/Google Drive Backup"
LOG=/Library/Logs/tm2gdrive.log

[[ "$(uname -s)" == "Darwin" ]] || { echo "macOS only" >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo "Run as a normal user with sudo rights, not as root." >&2; exit 1; }
if [[ "${CI:-}" != "true" && "${TM2GDRIVE_DESTRUCTIVE_OK:-}" != "1" ]]; then
    echo "Refusing to run: this installs a system service and changes Time Machine settings." >&2
    echo "It is meant for disposable CI machines." >&2
    exit 1
fi

PASS=0
FAIL=0
check() {
    local desc="$1"
    shift
    if "$@"; then PASS=$((PASS + 1)); echo "  ok    $desc"; else FAIL=$((FAIL + 1)); echo "  FAIL  $desc"; fi
}
step() { printf '\n=== %s  (%s)\n' "$*" "$(date '+%H:%M:%S')"; }

diagnostics() {
    echo "--- service log";      sudo tail -n 100 "$LOG" 2>/dev/null
    echo "--- mounts";           mount
    echo "--- disk images";      hdiutil info 2>&1 | tail -n 30
    echo "--- processes";        ps axww -o pid,ppid,stat,etime,command | grep -E "rclone|hdiutil|tm2gdrive|mount|diskimage" | grep -v grep
    echo "--- service";          sudo launchctl print system/io.github.nooranshdhaka.tm2gdrive 2>&1 | head -n 25
}

# A hang must not burn CI time silently: after 20 minutes, show what is stuck and stop.
( sleep 1200; echo; echo "=== WATCHDOG: the test hung. State of the system:"; diagnostics; kill -TERM -$$ 2>/dev/null; kill -TERM $$ ) &
WATCHDOG=$!
wait_until() {   # wait_until <seconds> <command...>
    local t="$1" _
    shift
    for _ in $(seq 1 "$t"); do "$@" && return 0; sleep 1; done
    return 1
}
mounted()   { mount | grep -qF " on $1 ("; }
uploaded()  { sudo "$TOOL" status 2>/dev/null | grep -q "Everything is uploaded"; }
checksums() { (cd "$VOLUME/data" && shasum -a 256 ./* ) 2>/dev/null; }

DRIVE=$(mktemp -d /private/tmp/tm2gdrive-fake-drive.XXXXXX)
CONF=$(mktemp /private/tmp/tm2gdrive-rclone.XXXXXX)
printf '[gdrive]\ntype = local\n' > "$CONF"
export TM2GDRIVE_RCLONE_CONF="$CONF"
export TM2GDRIVE_DRIVE_FOLDER="$DRIVE"
export TM2GDRIVE_DISK_PASSWORD="integration-test-password"
export TM2GDRIVE_DISK_SIZE_GB=4
export TM2GDRIVE_ASSUME_YES=1
export TM2GDRIVE_SKIP_FDA_CHECK=1   # CI machines grant root what Full Disk Access would
IMAGE="$DRIVE/TimeMachine.sparsebundle"

finish() {
    kill "$WATCHDOG" 2>/dev/null
    if [[ $FAIL -gt 0 ]]; then
        echo; echo "=== diagnostics"; diagnostics
    fi
    sudo "$TOOL" uninstall --purge >/dev/null 2>&1
    echo; echo "$PASS passed, $FAIL failed"
}
trap finish EXIT

step "Setup"
"$TOOL" setup
setup_rc=$?
check "setup succeeds" test $setup_rc -eq 0
[[ $setup_rc -eq 0 ]] || { diagnostics; exit 1; }
check "the background service is running" sudo launchctl print system/io.github.nooranshdhaka.tm2gdrive
check "Google Drive (the stand-in) is mounted over NFS" eval 'mount | grep -q " on /private/var/tm2gdrive/drive (nfs"'
check "the backup disk is attached" mounted "$VOLUME"
check "the backup disk is encrypted" eval '[[ "$(hdiutil info)" == *"image-encrypted : TRUE"* ]]'
check "the backup disk is APFS" eval 'diskutil info "$VOLUME" | grep -q "APFS"'
check "ownership is enabled (Time Machine needs it)" eval 'diskutil info "$VOLUME" | grep -qE "Owners: +Enabled"'
check "Time Machine has the disk as a destination" eval 'tmutil destinationinfo | grep -qF "Mount Point   : $VOLUME"'
check "the service runs root-owned copies of its programs" eval '[[ "$(sudo stat -f %Su "/Library/Application Support/tm2gdrive/bin/rclone")" == root ]]'
check "the disk password is private" eval '[[ "$(sudo stat -f %Lp "/Library/Application Support/tm2gdrive/disk-password")" == 600 ]]'

step "Writing to the backup disk reaches Drive, encrypted"
sudo mkdir -p "$VOLUME/data"
sudo dd if=/dev/urandom of="$VOLUME/data/random.bin" bs=1m count=300 2>/dev/null
printf 'PLAINTEXT-MARKER-%s\n' "$RANDOM$RANDOM" | sudo tee "$VOLUME/data/marker.txt" >/dev/null
marker=$(cat "$VOLUME/data/marker.txt")
sync
before=$(checksums)
check "files were written" test -n "$before"
check "all uploads finish" wait_until 300 uploaded
check "the backup disk is a sparse bundle in Drive" sudo test -f "$IMAGE/Info.plist"
bands=$(sudo find "$IMAGE/bands" -type f | wc -l | tr -d ' ')
size_mb=$(sudo du -sm "$IMAGE" | awk '{print $1}')
echo "        $bands band files, $size_mb MB in Drive"
check "the data is in Drive" test "$size_mb" -ge 300
check "bands are 16 MiB or smaller" eval '[[ -z "$(sudo find "$IMAGE/bands" -type f -size +16384k)" ]]'
check "Drive only holds encrypted data" eval '! sudo grep -rqF "$marker" "$DRIVE"'
out=$(sudo "$TOOL" status)
check "status reports a healthy setup" test $? -eq 0
echo "$out" | sed 's/^/        /'

step "Restart"
sudo "$TOOL" restart
check "the disk comes back after a restart" wait_until 120 mounted "$VOLUME"
check "the data is intact after a restart" eval '[[ "$(checksums)" == "$before" ]]'

step "rclone crash while the disk is in use"
sudo pkill -9 -f "rclone serve nfs"
sudo dd if=/dev/urandom of="$VOLUME/data/after-crash.bin" bs=1m count=20 2>/dev/null
check "writing still works after rclone is restarted" test -s "$VOLUME/data/after-crash.bin"
check "the service logged the restart" eval 'sudo grep -q "restarting it" "$LOG"'
after_crash=$(checksums)
check "all uploads finish after the crash" wait_until 300 uploaded

step "Empty cache: everything is read back from Drive"
sudo "$TOOL" stop
check "stopping detaches the disk" eval '! mounted "$VOLUME"'
check "stopping unmounts Drive" eval '! mount | grep -q "/private/var/tm2gdrive/drive"'
sudo rm -rf /Library/Caches/tm2gdrive
sudo "$TOOL" start
check "the disk attaches with an empty cache" wait_until 180 mounted "$VOLUME"
check "the data read back from Drive is intact" eval '[[ "$(checksums)" == "$after_crash" ]]'

step "A new Mac: set up again from the backup in Drive"
sudo "$TOOL" uninstall --purge
check "uninstall removes the Time Machine destination" eval '! tmutil destinationinfo 2>/dev/null | grep -qF "$VOLUME"'
check "uninstall detaches the disk" eval '! mounted "$VOLUME"'
check "uninstall keeps the backup in Drive" sudo test -f "$IMAGE/Info.plist"
TM2GDRIVE_DISK_PASSWORD="wrong-password" "$TOOL" setup > /tmp/tm2gdrive-wrongpw.txt 2>&1
check "a wrong password is refused" grep -q "didn't open the backup disk" /tmp/tm2gdrive-wrongpw.txt
sudo "$TOOL" uninstall --purge >/dev/null 2>&1
"$TOOL" setup
check "setup finds the existing backup" mounted "$VOLUME"
check "the old data is all there" eval '[[ "$(checksums)" == "$after_crash" ]]'

[[ $FAIL -eq 0 ]]

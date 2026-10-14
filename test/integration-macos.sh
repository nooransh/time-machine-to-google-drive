#!/bin/bash
#
# End-to-end test on a real Mac (used by CI).
#
# Runs the real tm2gdrive setup and background service: rclone (with
# tm2gdrive's patches) on FUSE-T, and Samba as the Time Machine share. A local
# folder stands in for Google Drive. It writes to the share over SMB, like
# Time Machine does, and checks that the data reaches "Drive" encrypted,
# survives an rclone crash and a restart with an empty cache, and opens again
# with the backup password as if on a new Mac. Time Machine itself can't run
# on CI machines, so the Time Machine step is skipped.
#
# Everything lives in a temporary folder, but the background service uses
# tm2gdrive's real LaunchAgent label, so this would replace a real install.
# It only runs on CI machines, or with TM2GDRIVE_DESTRUCTIVE_OK=1.
#
# Needs FUSE-T and Homebrew's Samba. Uses $TM2GDRIVE_RCLONE if set; otherwise
# setup downloads the patched rclone like it does for users.
#
# shellcheck disable=SC2016  # checks are passed to eval on purpose
set -u -o pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
TOOL="$HERE/../tm2gdrive"

[[ "$(uname -s)" == "Darwin" ]] || { echo "macOS only" >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo "Run as a normal user, not as root." >&2; exit 1; }
if [[ "${CI:-}" != "true" && "${TM2GDRIVE_DESTRUCTIVE_OK:-}" != "1" ]]; then
    echo "Refusing to run: this replaces tm2gdrive's background service, if installed." >&2
    echo "It is meant for CI machines (or set TM2GDRIVE_DESTRUCTIVE_OK=1)." >&2
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
wait_until() {   # wait_until <seconds> <shell condition>
    local _
    for _ in $(seq 1 "$1"); do eval "$2" && return 0; sleep 1; done
    return 1
}

# Short paths: Samba's sockets live under the state folder.
W=$(mktemp -d /private/tmp/tm2g-it.XXXX)
mkdir -p "$W/drive-standin" "$W/smb"
printf '[gdrive]\ntype = alias\nremote = %s/drive-standin\n' "$W" > "$W/remote.conf"
export TM2GDRIVE_STATE_DIR="$W/state" TM2GDRIVE_CACHE_DIR="$W/cache" TM2GDRIVE_LOG="$W/tm2gdrive.log"
export TM2GDRIVE_PLIST="$W/agent.plist" TM2GDRIVE_DRIVE_REMOTE_CONF="$W/remote.conf"
export TM2GDRIVE_SKIP_TIME_MACHINE=1 TM2GDRIVE_ASSUME_YES=1 TM2GDRIVE_BACKUP_PASSWORD="correct horse battery staple"
MARKER="TM2GDRIVE-PLAINTEXT-$$-MARKER"

smb_mount() {   # macOS's SMB client may fail once right after Samba restarts
    local pw _
    pw=$(cat "$TM2GDRIVE_STATE_DIR/smb-password")
    for _ in 1 2 3; do
        mount_smbfs "//tm2gdrive:$pw@127.0.0.1:44545/tm2gdrive" "$W/smb" 2>/dev/null && return 0
        sleep 2
    done
    return 1
}
smb_unmount() { umount "$W/smb" 2>/dev/null || diskutil unmount force "$W/smb" >/dev/null 2>&1; }
uploaded() { local out; out=$("$TOOL" status 2>/dev/null); [[ "$out" == *"Everything is uploaded"* ]]; }

cleanup() {
    smb_unmount
    "$TOOL" uninstall --purge >/dev/null 2>&1
    rm -rf "$W"
}
trap cleanup EXIT

step "setup"
"$TOOL" setup; rc=$?
check "setup succeeds" test $rc -eq 0
check "the service is running" launchctl print "gui/$(id -u)/io.github.nooranshdhaka.tm2gdrive"
check "the share is on 127.0.0.1 only" sh -c "lsof -nP -iTCP:44545 -sTCP:LISTEN | grep -q '127.0.0.1:44545' && ! lsof -nP -iTCP:44545 -sTCP:LISTEN | grep -q '\*:44545'"
check "status is healthy" "$TOOL" status
check "Samba runs as the user, not root" sh -c "ps -o user= -p \$(pgrep -f 'samba-dot-org-smbd.*$W' | head -1) | grep -qx '$(id -un)'"

crash_rclone() { pkill -9 -f "rclone.* mount tm2gdrive: $W/state/drive"; }

step "write over SMB like Time Machine"
check "the share mounts" smb_mount
{ head -c 5000000 /dev/urandom; echo "$MARKER"; head -c 5000000 /dev/urandom; } > "$W/source.bin"
cp -X "$W/source.bin" "$W/smb/backup.bin"
mkdir -p "$W/smb/bundle.sparsebundle/bands" && head -c 2000000 /dev/urandom > "$W/smb/bundle.sparsebundle/bands/0"
mv "$W/smb/bundle.sparsebundle" "$W/smb/renamed.sparsebundle"
check "a renamed folder keeps its files" test -f "$W/smb/renamed.sparsebundle/bands/0"
smb_unmount   # the SMB client keeps files open; open files aren't uploaded
check "everything uploads" wait_until 120 uploaded
check "\"Drive\" holds files" test -n "$(find "$W/drive-standin" -type f)"
check "\"Drive\" holds no plaintext names" test -z "$(find "$W/drive-standin" -name 'backup.bin' -o -name '*.sparsebundle')"
check "\"Drive\" holds no plaintext data" sh -c "! grep -rqa '$MARKER' '$W/drive-standin'"

step "rclone crash"
crash_rclone
check "the service brings the share back" wait_until 90 '"$TOOL" status >/dev/null 2>&1'
check "the share mounts again" smb_mount
check "the data is intact" cmp -s "$W/source.bin" "$W/smb/backup.bin"
cp -X "$W/source.bin" "$W/smb/late.bin"
smb_unmount
crash_rclone   # before late.bin is uploaded
check "the service comes back" wait_until 90 '"$TOOL" status >/dev/null 2>&1'
check "files closed before the crash still upload" wait_until 120 uploaded

step "restart with an empty cache (data must come from \"Drive\")"
"$TOOL" stop >/dev/null
rm -rf "$W/cache"
"$TOOL" start >/dev/null
check "the share comes back" wait_until 90 '"$TOOL" status >/dev/null 2>&1'
check "the share mounts" smb_mount
check "the data is intact" cmp -s "$W/source.bin" "$W/smb/backup.bin"
check "the file closed before the crash is intact" cmp -s "$W/source.bin" "$W/smb/late.bin"
smb_unmount

step "a new Mac: the backup password restores access"
"$TOOL" uninstall --purge >/dev/null
TM2GDRIVE_BACKUP_PASSWORD="wrong password" "$TOOL" setup > "$W/wrong.log" 2>&1; rc=$?
check "a wrong password is refused" sh -c "test $rc -ne 0 && grep -q \"doesn't decrypt\" '$W/wrong.log'"
"$TOOL" uninstall --purge >/dev/null
"$TOOL" setup >/dev/null 2>&1; rc=$?
check "the right password is accepted" test $rc -eq 0
check "the share mounts" smb_mount
check "the backups are there" cmp -s "$W/source.bin" "$W/smb/backup.bin"
smb_unmount

step "uninstall"
"$TOOL" uninstall --purge >/dev/null
check "the service is gone" sh -c "! launchctl print gui/$(id -u)/io.github.nooranshdhaka.tm2gdrive >/dev/null 2>&1"
check "nothing is left listening" sh -c "! lsof -nP -iTCP:44545 -sTCP:LISTEN >/dev/null"
check "the backups stay in \"Drive\"" test -n "$(ls "$W/drive-standin")"

echo
echo "$PASS passed, $FAIL failed"
if [[ $FAIL -ne 0 ]]; then
    echo "--- service log"; tail -40 "$W/tm2gdrive.log" 2>/dev/null
    exit 1
fi

#!/bin/bash
#
# End-to-end tests for tm2gdrive.
#
# The macOS tools tm2gdrive drives (tmutil, diskutil, mount_apfs, umount) are
# replaced by fakes in test/mocks that serve "Time Machine backups" from a temp
# folder. restic and rclone are real; a local folder stands in for Google Drive.
#
# Requirements: restic (0.17+), rclone, openssl. Runs on Linux and macOS. Must
# run as root, like tm2gdrive itself (use: sudo -E bash test/run-tests.sh).
#
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
TOOL="$HERE/../tm2gdrive"
PASS=0
FAIL=0

REAL_RCLONE=$(command -v rclone) || { echo "rclone not found" >&2; exit 1; }
REAL_RESTIC=$(command -v restic) || { echo "restic not found" >&2; exit 1; }
export REAL_RCLONE REAL_RESTIC
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo -E bash $0" >&2; exit 1; }

TMP_ROOTS=()
cleanup() { [[ ${#TMP_ROOTS[@]} -gt 0 ]] && rm -rf "${TMP_ROOTS[@]}"; }
trap cleanup EXIT

check() {   # check "description" command [args...]
    local desc="$1"
    shift
    if "$@"; then
        PASS=$((PASS + 1)); echo "  ok    $desc"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL  $desc"
        if [[ -n "${out:-}" ]]; then printf '%s\n' "$out" | sed 's/^/        | /' | tail -15; fi
    fi
}
contains() { grep -qF -- "$2" <<<"$1"; }
lacks()    { ! grep -qF -- "$2" <<<"$1"; }

# Creates a fresh fake Mac + Time Machine disk + "Google Drive" and a config.
# new_env <apfs|hfs> [noinit]
new_env() {
    FAKE_ROOT=$(mktemp -d)
    TMP_ROOTS+=("$FAKE_ROOT")
    export FAKE_ROOT FAKE_FS="$1"
    export TM2GDRIVE_ALLOW_NON_MAC=1 TM2GDRIVE_SKIP_FDA_CHECK=1
    export TM2GDRIVE_TEST_PATH="$HERE/mocks"
    export TM2GDRIVE_CONFIG_DIR="$FAKE_ROOT/config"
    export TM2GDRIVE_MOUNT_POINT="$FAKE_ROOT/mnt"
    mkdir -p "$FAKE_ROOT/tmdisk" "$FAKE_ROOT/snapshots" "$FAKE_ROOT/mac/Users/me/Documents" "$TM2GDRIVE_CONFIG_DIR"
    cat > "$TM2GDRIVE_CONFIG_DIR/config" <<CFG
RCLONE_REMOTE="gdrive"
DRIVE_FOLDER="$FAKE_ROOT/drive/backup"
MACHINE_NAME="TestMac"
DAILY_UPLOAD_GB=0
PACK_SIZE_MB=4
QUOTA_WAIT_MINUTES=0
ERROR_WAIT_MINUTES=0
MAX_ERROR_RETRIES=1
CFG
    printf '[gdrive]\ntype = local\n' > "$TM2GDRIVE_CONFIG_DIR/rclone.conf"
    if [[ "${2:-}" != "noinit" ]]; then
        echo "test-password" > "$TM2GDRIVE_CONFIG_DIR/restic-password"
        "$TOOL" restic init >/dev/null 2>&1 || { echo "repository init failed" >&2; exit 1; }
    fi
}

# Copies the fake Mac into a new fake Time Machine backup.
make_backup() {
    local dst="$FAKE_ROOT/snapshots/com.apple.TimeMachine.$1.backup/$1.backup"
    mkdir -p "$dst"
    cp -pR "$FAKE_ROOT/mac/." "$dst/Macintosh HD - Data"
}

run() { "$TOOL" "$@" 2>&1; }
snapshot_count() { "$TOOL" snapshots --json 2>/dev/null | grep -oE '"short_id"' | grep -c .; }

# ---------------------------------------------------------------------------
echo "Full workflow on an APFS Time Machine disk"
new_env apfs
head -c 3000000 /dev/urandom > "$FAKE_ROOT/mac/Users/me/Documents/photo.raw"
echo "v1" > "$FAKE_ROOT/mac/Users/me/Documents/notes.txt"
make_backup 2025-01-01-100000
echo "v2" > "$FAKE_ROOT/mac/Users/me/Documents/notes.txt"
make_backup 2025-01-02-100000
head -c 1000000 /dev/urandom > "$FAKE_ROOT/mac/Users/me/Documents/new.bin"
make_backup 2025-01-03-100000

out=$(run status)
check "status lists 3 pending backups" contains "$out" "0 of 3 Time Machine backups are on Google Drive"
check "status shows Drive free space" contains "$out" "Google Drive free space:"

out=$(run backup --dry-run)
check "dry run plans 3 uploads" contains "$out" "3 to upload"
check "dry run reports what it would do" contains "$out" "Dry run finished: 3 backup(s) would be uploaded."
check "dry run uploads nothing" test "$(snapshot_count)" -eq 0
check "dry run leaves nothing mounted" test ! -L "$FAKE_ROOT/mnt"

touch "$FAKE_ROOT/quota-once"
out=$(run backup)
check "backup uploads all 3" contains "$out" "Finished: 3 backup(s) uploaded."
check "Google's daily upload limit is waited out" contains "$out" "Reached Google's daily upload limit"
check "newest backup is uploaded first" test "$(head -1 "$FAKE_ROOT/mount.log")" = "com.apple.TimeMachine.2025-01-03-100000.backup"
check "later backups only read changed files" contains "$out" "using parent snapshot"
check "snapshot is unmounted afterwards" test ! -L "$FAKE_ROOT/mnt"
check "lock is released afterwards" test ! -d "$TM2GDRIVE_CONFIG_DIR/.backup.lock"
check "a log file is written" test -n "$(ls "$TM2GDRIVE_CONFIG_DIR"/logs/backup-*.log 2>/dev/null)"
snaps=$(run snapshots)
for d in 2025-01-01-100000 2025-01-02-100000 2025-01-03-100000; do
    check "snapshot tagged tm:$d" contains "$snaps" "tm:$d"
done
check "snapshot time is the Time Machine backup time" contains "$snaps" "2025-01-02 10:00:00"
check "snapshot host is the machine name" contains "$snaps" "TestMac"

out=$(run status)
check "status shows all uploaded" contains "$out" "3 of 3 Time Machine backups are on Google Drive"

out=$(run backup)
check "re-run uploads nothing" contains "$out" "Nothing to upload: Google Drive is up to date."

echo "v3" > "$FAKE_ROOT/mac/Users/me/Documents/notes.txt"
make_backup 2025-01-04-100000
out=$(run backup)
check "a new Time Machine backup is picked up" contains "$out" "1 to upload"
check "only the changed file is read" contains "$out" "1 changed"

rm -rf "$FAKE_ROOT/snapshots/com.apple.TimeMachine.2025-01-01-100000.backup"
out=$(run status)
check "backups Time Machine deleted stay on Drive" contains "$out" "already deleted from the Time Machine disk): 2025-01-01-100000"

out=$(run restore 2025-01-02-100000 "$FAKE_ROOT/restore-old")
check "an old version restores with its old contents" test "$(cat "$FAKE_ROOT/restore-old/Macintosh HD - Data/Users/me/Documents/notes.txt" 2>/dev/null)" = "v2"
out=$(run restore latest "$FAKE_ROOT/restore")
check "latest restore matches the Mac exactly" diff -r "$FAKE_ROOT/mac" "$FAKE_ROOT/restore/Macintosh HD - Data"
out=$(run restore latest "$FAKE_ROOT/restore-one" --include "/Macintosh HD - Data/Users/me/Documents/notes.txt")
check "a single file can be restored" test -f "$FAKE_ROOT/restore-one/Macintosh HD - Data/Users/me/Documents/notes.txt" -a ! -e "$FAKE_ROOT/restore-one/Macintosh HD - Data/Users/me/Documents/photo.raw"
out=$(run restore 1999-01-01-000000 "$FAKE_ROOT/restore-none")
check "restoring an unknown backup is an error" contains "$out" "No backup on Google Drive matches"

out=$(run verify 100%)
check "verify reads back all data" contains "$out" "no errors were found"
out=$(run verify)
check "verify defaults to a sample" contains "$out" "downloading 10G of the data"

out=$(run inspect)
check "inspect finds the backups" contains "$out" "2025-01-04-100000"
check "inspect shows the backup contents" contains "$out" "Macintosh HD - Data"

# A running backup has a snapshot mounted; inspect must not touch it.
mkdir -p "$FAKE_ROOT/mnt"
"$HERE/mocks/mount_apfs" -s com.apple.TimeMachine.2025-01-03-100000.backup /dev/disk9s1 "$FAKE_ROOT/mnt"
run inspect >/dev/null
check "inspect leaves a running backup's mount alone" test -L "$FAKE_ROOT/mnt"
"$HERE/mocks/umount" "$FAKE_ROOT/mnt"

out=$(run restic forget --tag tm2gdrive --group-by host --keep-last 1 --dry-run)
check "the README's retention command (--group-by host) thins backups" contains "$out" "remove 3 snapshots"

# ---------------------------------------------------------------------------
echo "Backup selection options"
new_env apfs
echo a > "$FAKE_ROOT/mac/a"; make_backup 2025-02-01-100000
echo b > "$FAKE_ROOT/mac/a"; make_backup 2025-02-02-100000
echo c > "$FAKE_ROOT/mac/a"; make_backup 2025-02-03-100000
out=$(run backup --only-latest)
check "--only-latest uploads one backup" contains "$out" "1 to upload"
check "--only-latest picks the newest" contains "$(run snapshots)" "tm:2025-02-03-100000"
out=$(run backup --only-latest)
check "--only-latest again has nothing to do" contains "$out" "Nothing to upload"
out=$(run backup --oldest-first --max 1)
check "--oldest-first --max 1 uploads the oldest" contains "$(run snapshots)" "tm:2025-02-01-100000"
check "--max 1 stops after one" test "$(snapshot_count)" -eq 2
out=$(run backup --since 2025-02-03)
check "--since skips older backups" contains "$out" "Nothing to upload"
out=$(run backup --max lots)
check "--max must be a number" contains "$out" "--max needs a number"
out=$(run backup --since yesterday)
check "--since must be a date" contains "$out" "--since needs a date"
out=$(run backup --bogus)
check "unknown options are rejected" contains "$out" "Unknown option for backup: --bogus"

# ---------------------------------------------------------------------------
echo "Errors and safety"
new_env apfs
echo a > "$FAKE_ROOT/mac/a"; make_backup 2025-03-01-100000
mv "$TM2GDRIVE_CONFIG_DIR/restic-password" "$FAKE_ROOT/pw"
echo wrong > "$TM2GDRIVE_CONFIG_DIR/restic-password"
out=$(run backup)
check "a wrong password is reported" contains "$out" "Wrong encryption password"
mv "$FAKE_ROOT/pw" "$TM2GDRIVE_CONFIG_DIR/restic-password"

sleep 60 & sleeper=$!
mkdir "$TM2GDRIVE_CONFIG_DIR/.backup.lock"; echo "$sleeper" > "$TM2GDRIVE_CONFIG_DIR/.backup.lock/pid"
out=$(run backup)
check "a second backup run at the same time is refused" contains "$out" "already running"
kill "$sleeper"; wait "$sleeper" 2>/dev/null
rm "$TM2GDRIVE_CONFIG_DIR/.backup.lock/pid"
out=$(run backup)
check "a lock that is still being created is respected" contains "$out" "starting right now"
echo 999999 > "$TM2GDRIVE_CONFIG_DIR/.backup.lock/pid"
out=$(run backup)
check "a stale lock from a crashed run is ignored" contains "$out" "Finished: 1 backup(s) uploaded."
check "the lock is gone afterwards" test ! -e "$TM2GDRIVE_CONFIG_DIR/.backup.lock"

echo z > "$FAKE_ROOT/mac/a"; make_backup 2025-03-01-200000
run backup > "$FAKE_ROOT/race1" 2>&1 &
first=$!
run backup > "$FAKE_ROOT/race2" 2>&1
wait "$first"
check "two backups started together upload a backup only once" \
    test "$(run snapshots --json | grep -o '"tm:2025-03-01-200000"' | grep -c .)" -eq 1

echo b > "$FAKE_ROOT/mac/a"; make_backup 2025-03-02-100000
touch "$FAKE_ROOT/vanish"
out=$(run backup)
check "a disk that disappears mid-upload is reported" contains "$out" "stopped responding during the upload"
check "that backup is not counted as uploaded" contains "$(run status)" "2025-03-02-100000  incomplete"
out=$(run backup)
check "the backup is redone on the next run" contains "$out" "Finished: 1 backup(s) uploaded."
check "the incomplete attempt is removed" lacks "$(run snapshots)" "tm2gdrive-incomplete"

echo c > "$FAKE_ROOT/mac/a"; make_backup 2025-03-03-100000
touch "$FAKE_ROOT/unreadable"
out=$(run backup)
check "unreadable files are reported" contains "$out" "some files could not be read"
check "the run summary mentions it" contains "$out" "1 with unreadable files (retried next run)"
check "status shows the backup as incomplete" contains "$(run status)" "2025-03-03-100000  incomplete"
out=$(run backup)
check "a backup with unreadable files is retried" contains "$out" "Finished: 1 backup(s) uploaded."
check "once complete, the incomplete copy is dropped" test "$(run snapshots --json | grep -o '"tm:2025-03-03-100000"' | grep -c .)" -eq 1
check "status then shows it as uploaded" contains "$(run status)" "2025-03-03-100000  uploaded"

# Snapshot contents directly at the snapshot root: a vanished disk leaves an empty mount folder.
mkdir -p "$FAKE_ROOT/snapshots/com.apple.TimeMachine.2025-03-04-100000.backup/Macintosh HD - Data"
echo d > "$FAKE_ROOT/snapshots/com.apple.TimeMachine.2025-03-04-100000.backup/Macintosh HD - Data/a"
touch "$FAKE_ROOT/vanish"
out=$(run backup)
check "a vanished disk is caught even when an empty mount folder remains" contains "$out" "stopped responding during the upload"
run backup >/dev/null

rm -rf "$FAKE_ROOT/snapshots"/*
out=$(run backup)
check "an empty Time Machine disk is reported" contains "$out" "No Time Machine backups found"

out=$(run backup --dest "$FAKE_ROOT/not-there")
check "a missing --dest disk is reported" contains "$out" "Time Machine disk not found"

touch "$FAKE_ROOT/expired"
out=$(run status)
check "an expired Google sign-in says how to reconnect" contains "$out" "Your Google sign-in has expired. Run \"tm2gdrive reconnect\""
rm "$FAKE_ROOT/expired"

mv "$TM2GDRIVE_CONFIG_DIR/rclone.conf" "$FAKE_ROOT/rc"
out=$(run status)
check "commands ask for setup when not set up" contains "$out" "Not set up yet"
mv "$FAKE_ROOT/rc" "$TM2GDRIVE_CONFIG_DIR/rclone.conf"

# ---------------------------------------------------------------------------
echo "Settings file"
new_env apfs
echo a > "$FAKE_ROOT/mac/a"; make_backup 2025-04-01-100000
cat >> "$TM2GDRIVE_CONFIG_DIR/config" <<'CFG'

# a comment
MACHINE_NAME = 'Quoted Mac'   # trailing comment
CONNECTIONS=3 # comment after a number
NOT_A_SETTING=1
CFG
out=$(run backup)
check "comments, spaces and quotes are understood" contains "$(run snapshots)" "Quoted-Mac"
check "unknown settings are flagged" contains "$out" "Unknown setting in"
echo 'DAILY_UPLOAD_GB=680' >> "$TM2GDRIVE_CONFIG_DIR/config"
echo b > "$FAKE_ROOT/mac/a"; make_backup 2025-04-02-100000
out=$(run status)
check "status estimates the first upload time" contains "$out" "A full first upload at 680 GiB/day takes about"
out=$(run backup)
check "uploads work with the daily speed cap on" contains "$out" "Upload speed capped at 680 GiB/day"
check "the capped upload finishes" contains "$out" "Finished: 1 backup(s) uploaded."
cp "$TM2GDRIVE_CONFIG_DIR/config" "$FAKE_ROOT/config.good"
echo 'DAILY_UPLOAD_GB=lots' >> "$TM2GDRIVE_CONFIG_DIR/config"
out=$(run status)
check "non-numeric numbers are rejected" contains "$out" "DAILY_UPLOAD_GB in"
cp "$FAKE_ROOT/config.good" "$TM2GDRIVE_CONFIG_DIR/config"
rm -f "$FAKE_ROOT/pwned"
# shellcheck disable=SC2016  # the $(...) and backticks must reach the file unexpanded
printf '%s\n' "MACHINE_NAME=\"\`touch $FAKE_ROOT/pwned\`\"" "TM_DEST=\$(touch $FAKE_ROOT/pwned)" >> "$TM2GDRIVE_CONFIG_DIR/config"
out=$(run status)
check "the settings file is never executed" test ! -e "$FAKE_ROOT/pwned"
check "the injected value is used as plain text" contains "$out" "touch $FAKE_ROOT/pwned"

# ---------------------------------------------------------------------------
echo "Setup"
new_env apfs noinit
out=$(printf 'y\n' | env -u SUDO_USER "$TOOL" setup 2>&1)
check "setup creates the backup" contains "$out" "Setup complete"
check "setup generates a strong password" test "$(wc -c < "$TM2GDRIVE_CONFIG_DIR/restic-password")" -ge 33
check "the password file is private" test -z "$(find "$TM2GDRIVE_CONFIG_DIR/restic-password" -perm +044 2>/dev/null || find "$TM2GDRIVE_CONFIG_DIR/restic-password" -perm /044)"
check "setup keeps existing settings" contains "$(cat "$TM2GDRIVE_CONFIG_DIR/config")" "$FAKE_ROOT/drive/backup"
out=$(env -u SUDO_USER "$TOOL" setup 2>&1 </dev/null)
check "running setup again is safe" contains "$out" "Using the existing backup"
out=$(env -u SUDO_USER "$TOOL" setup --full-drive-access 2>&1 </dev/null)
check "--full-drive-access upgrades an existing connection" contains "$(cat "$FAKE_ROOT/rclone-update.log" 2>/dev/null)" "config update gdrive scope=drive"

echo a > "$FAKE_ROOT/mac/a"; make_backup 2025-05-01-100000
run backup >/dev/null
pw=$(cat "$TM2GDRIVE_CONFIG_DIR/restic-password")
rm "$TM2GDRIVE_CONFIG_DIR/restic-password"   # e.g. a new Mac
out=$(printf 'not-it\n%s\n' "$pw" | env -u SUDO_USER "$TOOL" setup 2>&1)
check "setup on a new Mac asks for the existing password" contains "$out" "already holds a backup"
check "a wrong password is asked again" contains "$out" "Wrong password, try again."
check "the right password is accepted" contains "$out" "Password accepted"
check "the existing backup is then usable" contains "$(run snapshots)" "tm:2025-05-01-100000"

new_env apfs noinit
out=$(env -u SUDO_USER "$TOOL" setup 2>&1 </dev/null)
check "setup without a terminal stops instead of looping" contains "$out" "No answer received"

# ---------------------------------------------------------------------------
echo "HFS+ (Backups.backupdb) Time Machine disk"
new_env hfs
mkdir -p "$FAKE_ROOT/tmdisk/Backups.backupdb/FakeMac/2019-05-01-120000/Macintosh HD/Users/me"
echo old > "$FAKE_ROOT/tmdisk/Backups.backupdb/FakeMac/2019-05-01-120000/Macintosh HD/Users/me/file"
mkdir -p "$FAKE_ROOT/snapshots/com.apple.TimeMachine.2019-05-01-120000.backup"  # makes fake tmutil list it
out=$(run backup)
check "HFS+ backup is uploaded" contains "$out" "Uploaded 2019-05-01-120000"
check "HFS+ backups are read in place, not mounted" test ! -e "$FAKE_ROOT/mount.log"
check "HFS+ contents are stored" contains "$(run restic ls latest)" "/Macintosh HD/Users/me/file"

# ---------------------------------------------------------------------------
echo "Command line"
out=$(run help)
check "help lists the commands" contains "$out" "restore WHICH DIR"
out=$(run version)
check "version prints the version" contains "$out" "tm2gdrive 1."
out=$(run frobnicate)
check "unknown commands show usage" contains "$out" "Usage: tm2gdrive"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

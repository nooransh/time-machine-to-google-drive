#!/bin/bash
#
# Unit tests for tm2gdrive's internal functions. Runs anywhere (Linux or macOS):
#   bash test/unit-tests.sh
#
# shellcheck disable=SC2034,SC2317,SC2329  # settings and stubs are used by the sourced script
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
PASS=0
FAIL=0

check() {   # check "description" command [args...]
    local desc="$1"
    shift
    if "$@"; then
        PASS=$((PASS + 1)); echo "  ok    $desc"
    else
        FAIL=$((FAIL + 1)); echo "  FAIL  $desc"
    fi
}
eq() { [[ "$1" == "$2" ]] || { echo "        expected [$2], got [$1]"; return 1; }; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export TM2GDRIVE_STATE_DIR="$WORK/state" TM2GDRIVE_SOURCE_ONLY=1
mkdir -p "$TM2GDRIVE_STATE_DIR"
# shellcheck disable=SC1091
. "$HERE/../tm2gdrive"

echo "Settings file"
cat > "$CONFIG_FILE" <<'EOF'
# comment

DRIVE_FOLDER = 'My Backups'   # trailing comment
CACHE_MAX_GB=30 # a number with a comment
VOLUME_NAME="Cloud TM"
NOT_A_SETTING=1
EOF
out=$(load_config 2>&1; echo "folder=$DRIVE_FOLDER cache=$CACHE_MAX_GB volume=$VOLUME")
load_config 2>/dev/null
check "quoted values with spaces" eq "$DRIVE_FOLDER" "My Backups"
check "numbers with trailing comments" eq "$CACHE_MAX_GB" "30"
check "volume path follows the name" eq "$VOLUME" "/Volumes/Cloud TM"
check "unknown settings are flagged" grep -q "Unknown setting in .*NOT_A_SETTING" <<<"$out"

# shellcheck disable=SC2016  # the $(...) and backticks must reach the file unexpanded
cd "$WORK" || exit 1
# shellcheck disable=SC2016  # must reach the file unexpanded
printf '%s\n' 'DRIVE_FOLDER=$(touch pwned)' 'RCLONE_REMOTE="`touch pwned`"' 'VOLUME_NAME=$(touch pwned)' > "$CONFIG_FILE"
load_config 2>/dev/null
cd - >/dev/null || exit 1
check "the settings file is never executed" test ! -e "$WORK/pwned"
check "injected text stays plain text" eq "$DRIVE_FOLDER" "\$(touch pwned)"
check "backticks stay plain text" eq "$RCLONE_REMOTE" "\`touch pwned\`"

echo 'CACHE_MAX_GB=lots' > "$CONFIG_FILE"
out=$( (load_config) 2>&1 )
check "non-numeric numbers are rejected" grep -q "CACHE_MAX_GB in .* must be a whole number" <<<"$out"
echo 'VOLUME_NAME="a/b"' > "$CONFIG_FILE"
out=$( (load_config) 2>&1 )
check "a disk name with a slash is rejected" grep -q "not a valid disk name" <<<"$out"

rm -f "$CONFIG_FILE"
RCLONE_REMOTE="gdrive"; DRIVE_FOLDER="tm2gdrive"; VOLUME_NAME="Google Drive Backup"; CACHE_MAX_GB=50
load_config
write_config
saved_folder="$DRIVE_FOLDER"
DRIVE_FOLDER="changed"
load_config
check "settings survive a write and read" eq "$DRIVE_FOLDER" "$saved_folder"
check "the settings file is private" test -z "$(find "$CONFIG_FILE" -perm +044 2>/dev/null || find "$CONFIG_FILE" -perm /044)"

echo "Backup disk size"
GB=1000000000
check "twice the Mac's data" eq "$(choose_disk_size $((5000 * GB)) $((400 * GB)))" "800"
check "at least 200 GB" eq "$(choose_disk_size $((5000 * GB)) $((50 * GB)))" "200"
check "no more than 90% of Drive's free space" eq "$(choose_disk_size $((500 * GB)) $((400 * GB)))" "450"
check "no more than 7 TB (Drive's files-per-folder limit)" eq "$(choose_disk_size $((30000 * GB)) $((6000 * GB)))" "7000"
check "works when Drive's free space is unknown" eq "$(choose_disk_size "" $((400 * GB)))" "800"

echo "Time Machine destination lookup"
tmutil() {
    cat <<'EOF'
====================================================
Name          : Old SSD
Kind          : Local
Mount Point   : /Volumes/Old SSD
ID            : 11111111-1111-1111-1111-111111111111
====================================================
Name          : Google Drive Backup
Kind          : Local
Mount Point   : /Volumes/Google Drive Backup
ID            : 22222222-2222-2222-2222-222222222222
EOF
}
VOLUME="/Volumes/Google Drive Backup"
check "finds our disk among several" eq "$(tm_destination_id)" "22222222-2222-2222-2222-222222222222"
VOLUME="/Volumes/Old SSD"
check "matches the exact mount point" eq "$(tm_destination_id)" "11111111-1111-1111-1111-111111111111"
VOLUME="/Volumes/Google"
check "no partial matches" eq "$(tm_destination_id)" ""
unset -f tmutil

echo "rclone version check"
fake_rclone() { echo "rclone v$FAKE_V"; echo "- os/version: test"; }
FAKE_V=1.75.2; check "accepts 1.75" rclone_ok fake_rclone
FAKE_V=1.65.0; check "accepts 1.65 (first with serve nfs)" rclone_ok fake_rclone
FAKE_V=1.64.2; check "rejects 1.64" eval '! rclone_ok fake_rclone'
FAKE_V=2.0.0;  check "accepts 2.x" rclone_ok fake_rclone
FAKE_V=garbage; check "rejects an unreadable version" eval '! rclone_ok fake_rclone'

echo "Service definition"
PLIST="$WORK/test.plist"
chown() { :; }   # tests don't run as root
write_plist
unset -f chown
if command -v plutil >/dev/null 2>&1; then
    check "the service file is a valid plist" plutil -lint -s "$PLIST"
elif command -v xmllint >/dev/null 2>&1; then
    check "the service file is valid XML" xmllint --noout "$PLIST"
fi
check "it runs the root-owned copy" grep -qF "<string>$BIN_DIR/tm2gdrive</string>" "$PLIST"
check "it restarts if it stops" grep -q "<key>KeepAlive</key>" "$PLIST"
check "it has time to detach the disk at shutdown" grep -q "<integer>120</integer>" "$PLIST"

echo "Upload status"
rc() { echo '{"diskCache": {"uploadsInProgress": 2, "uploadsQueued": 5, "bytesUsed": 1}}'; }
check "adds in-progress and queued uploads" eq "$(pending_uploads)" "7"
rc() { echo '{"diskCache": {"uploadsInProgress": 0, "uploadsQueued": 0}}'; }
check "zero when everything is uploaded" eq "$(pending_uploads)" "0"
rc() { return 1; }
check "empty when the service can't be asked" eq "$(pending_uploads)" ""

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

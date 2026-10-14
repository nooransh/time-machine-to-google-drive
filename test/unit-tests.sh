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
BWLIMIT="08:00,512k 23:00,off"
NOT_A_SETTING=1
EOF
out=$(load_config 2>&1; echo "folder=$DRIVE_FOLDER cache=$CACHE_MAX_GB")
load_config 2>/dev/null
check "quoted values with spaces" eq "$DRIVE_FOLDER" "My Backups"
check "numbers with trailing comments" eq "$CACHE_MAX_GB" "30"
check "a bandwidth timetable is accepted" eq "$BWLIMIT" "08:00,512k 23:00,off"
check "unknown settings are flagged" grep -q "Unknown setting in .*NOT_A_SETTING" <<<"$out"

cd "$WORK" || exit 1
# shellcheck disable=SC2016  # must reach the file unexpanded
printf '%s\n' 'DRIVE_FOLDER=$(touch pwned)' 'BWLIMIT="`touch pwned`"' > "$CONFIG_FILE"
(load_config) >/dev/null 2>&1
read_config 2>/dev/null
cd - >/dev/null || exit 1
check "the settings file is never executed" test ! -e "$WORK/pwned"
check "injected text stays plain text" eq "$DRIVE_FOLDER" "\$(touch pwned)"
check "backticks stay plain text" eq "$BWLIMIT" "\`touch pwned\`"
out=$( (load_config) 2>&1 )
check "a bandwidth limit with shell characters is rejected" grep -q "BWLIMIT .* not a valid" <<<"$out"

echo 'CACHE_MAX_GB=lots' > "$CONFIG_FILE"
out=$( (load_config) 2>&1 )
check "non-numeric numbers are rejected" grep -q "CACHE_MAX_GB in .* must be a whole number" <<<"$out"
echo 'SMB_PORT=445' > "$CONFIG_FILE"
out=$( (load_config) 2>&1 )
check "a privileged port is rejected" grep -q "SMB_PORT .* between 1024" <<<"$out"
echo 'DRIVE_FOLDER="../elsewhere"' > "$CONFIG_FILE"
out=$( (load_config) 2>&1 )
check "a folder outside Drive's root is rejected" grep -q "not a valid folder name" <<<"$out"

rm -f "$CONFIG_FILE"
DRIVE_FOLDER="tm2gdrive-backups"; CACHE_MAX_GB=5; BWLIMIT=""
load_config
BACKUP_SIZE_GB=430
write_config
DRIVE_FOLDER="changed"; BACKUP_SIZE_GB=0
load_config
check "settings survive a write and read" eq "$DRIVE_FOLDER/$BACKUP_SIZE_GB" "tm2gdrive-backups/430"
check "the settings file is private" test -z "$(find "$CONFIG_FILE" -perm +044 2>/dev/null || find "$CONFIG_FILE" -perm /044)"

echo "Backup size limit (sets Time Machine's band size)"
GB=1000000000
check "1.5 times the Mac's data" eq "$(choose_backup_size $((5000 * GB)) $((400 * GB)))" "600"
check "at least 100 GB" eq "$(choose_backup_size $((5000 * GB)) $((20 * GB)))" "100"
check "no more than 90% of Drive's free space" eq "$(choose_backup_size $((500 * GB)) $((400 * GB)))" "450"
check "works when Drive's free space is unknown" eq "$(choose_backup_size "" $((400 * GB)))" "600"

echo "Samba configuration"
SMB_PORT=44545; BACKUP_SIZE_GB=430
write_smb_conf
check "listens on 127.0.0.1 only" sh -c "grep -q '^  interfaces = 127.0.0.1$' '$SMB_CONF' && grep -q '^  bind interfaces only = yes$' '$SMB_CONF'"
check "uses the configured port" grep -q "^  smb ports = 44545$" "$SMB_CONF"
check "no guest access" grep -q "^  map to guest = never$" "$SMB_CONF"
check "is a Time Machine share with the size limit" sh -c "grep -q 'fruit:time machine = yes' '$SMB_CONF' && grep -q 'fruit:time machine max size = 430G' '$SMB_CONF'"
check "no stream module (they break on the rclone mount)" sh -c "grep -q '^  vfs objects = catia fruit$' '$SMB_CONF'"
check "serves the Drive folder" grep -qF "path = $DRIVE_MNT" "$SMB_CONF"
check "Time Machine logs in as tm2gdrive" grep -qx "$(id -un) = tm2gdrive" "$SAMBA_DIR/usermap"
check "the configuration is private" test -z "$(find "$SMB_CONF" -perm +044 2>/dev/null || find "$SMB_CONF" -perm /044)"

echo "Time Machine destination lookup"
tmutil() {
    cat <<'EOF'
====================================================
Name          : SSD
Kind          : Local
Mount Point   : /Volumes/SSD
ID            : 11111111-1111-1111-1111-111111111111
====================================================
Name          : tm2gdrive
Kind          : Network
URL           : smb://tm2gdrive@127.0.0.1:44545/tm2gdrive
ID            : 22222222-2222-2222-2222-222222222222
====================================================
Name          : tm2gdrive
Kind          : Local
Mount Point   : /Volumes/tm2gdrive
ID            : 33333333-3333-3333-3333-333333333333
EOF
}
check "finds our share among several" eq "$(tm_destination_id)" "22222222-2222-2222-2222-222222222222"
SHARE="SSD"
check "only network destinations count" eq "$(tm_destination_id)" ""
SHARE="tm2g"
check "no partial matches" eq "$(tm_destination_id)" ""
SHARE="tm2gdrive"
unset -f tmutil

echo "Service definition"
PLIST="$WORK/test.plist"
write_plist
if command -v plutil >/dev/null 2>&1; then
    check "the service file is a valid plist" plutil -lint -s "$PLIST"
elif command -v xmllint >/dev/null 2>&1; then
    check "the service file is valid XML" xmllint --noout "$PLIST"
fi
check "it runs the installed copy" grep -qF "<string>$BIN_DIR/tm2gdrive</string>" "$PLIST"
check "it restarts if it stops" grep -q "<key>KeepAlive</key>" "$PLIST"
check "it doesn't run as root (no UserName, it's a LaunchAgent)" sh -c "! grep -q '<key>UserName</key>' '$PLIST'"

echo "Upload status"
rc() { echo '{"diskCache": {"dirtyFiles": 9, "dirtyBytes": 5, "pendingFiles": 7, "pendingBytes": 3000000000}}'; }
check "pending files, bytes and files still open" eq "$(pending_uploads)" "7 3000000000 2"
rc() { echo '{"diskCache": {"dirtyFiles": 0, "dirtyBytes": 0, "pendingFiles": 0, "pendingBytes": 0}}'; }
check "zero when everything is uploaded" eq "$(pending_uploads)" "0 0 0"
rc() { echo '{"diskCache": {"uploadsQueued": 0}}'; }
check "empty with an unpatched rclone" eq "$(pending_uploads)" ""
rc() { return 1; }
check "empty when the service can't be asked" eq "$(pending_uploads)" ""

echo "Patched rclone check"
RCLONE="$WORK/fake-rclone"
printf '#!/bin/sh\necho "      --vfs-cache-max-pending SizeSuffix   Pause writes"\n' > "$RCLONE"; chmod +x "$RCLONE"
check "accepts rclone with tm2gdrive's patches" rclone_patched
printf '#!/bin/sh\necho "      --vfs-cache-max-size SizeSuffix"\n' > "$RCLONE"
check "rejects stock rclone" eval '! rclone_patched'
rm -f "$RCLONE"
check "rejects a missing rclone" eval '! rclone_patched'

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

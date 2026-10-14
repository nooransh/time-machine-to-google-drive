# Changelog

## 3.0.0

macOS 27 refuses disk images as Time Machine disks (`tmutil setdestination`
fails with error 45), which 2.x relied on. 3.0 makes Google Drive a Time
Machine network disk instead.

- Samba shares an rclone mount of your Drive folder as a Time Machine disk,
  on 127.0.0.1 only. rclone runs on FUSE-T, which needs no kernel
  extension. Time Machine keeps its backup bundle there,
  like on a NAS.
- Encryption moved to rclone crypt: file contents and names are encrypted
  before upload with one backup password (`tm2gdrive password` shows it).
- Backups never fill the Mac's disk: writes pause while more than
  `MAX_PENDING_GB` (5 GB) waits to upload.
- Everything runs as the user (a LaunchAgent). Root is only used during
  setup, to install FUSE-T and to add the Time Machine disk. Samba from
  Homebrew no longer has to run as root.
- `BACKUP_SIZE_GB` (1.5 × the Mac's data by default) is the size Time
  Machine sees. It also sets Time Machine's band size, about ÷ 3800, so
  each change re-uploads about 100 MB instead of over 1 GB.
- Ships a build of rclone 1.75.2 with five patches that Time Machine needs
  ([rclone/README.md](rclone/README.md)). It is built by GitHub Actions and
  its checksum is verified on download.
- `status` shows how much is still waiting to upload, in files and GB.
- New integration test: real setup and service, writes over SMB, an rclone
  crash, a restart with an empty cache, and restoring with the password.
- Not compatible with 2.x backups. See "Upgrading from 2.x" in the README.

## 2.0.0

tm2gdrive now makes Google Drive itself a Time Machine backup disk. No
external drive is needed.

- `tm2gdrive setup` installs a background service that mounts a Google Drive
  folder over NFS (rclone `serve nfs` + macOS's built-in NFS client). It
  creates an AES-256 encrypted APFS sparse bundle there, attaches it as
  **Google Drive Backup**, and adds it to Time Machine.
- Writes are cached locally and uploaded in the background. Unsent data
  survives restarts and crashes. The service restarts rclone if it stops,
  and the mount carries on.
- `status` shows the service, the mount, the disk, Time Machine and pending
  uploads. Also added: `logs`, `reconnect`, `start`, `stop`, `restart` and
  `uninstall [--purge]`.
- Setup on a new Mac finds the existing backup disk and asks for its
  password, ready for Migration Assistant or Time Machine restores.
- The service runs root-owned copies of its programs; the settings file is
  parsed, never executed.
- Tested end to end on a real Mac in CI: setup, uploads, restarts, a crash,
  reading back with an empty cache, and restoring on a "new Mac".

Version 1.x (copying existing Time Machine backups to Drive with restic) is
replaced. It remains in the git history.

## 1.0.0

First release: copied existing Time Machine backups to Google Drive with
restic.

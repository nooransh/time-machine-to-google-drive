# Changelog

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

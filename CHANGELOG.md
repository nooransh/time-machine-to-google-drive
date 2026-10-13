# Changelog

## 1.0.0

First release.

- Upload every Time Machine backup (APFS snapshots or HFS+ `Backups.backupdb`)
  to Google Drive as an encrypted, deduplicated, compressed restic repository.
- Newest backup first; each backup is compared with an already uploaded one,
  so only changed files are read.
- Uploads capped at 680 GiB/day to stay under Google's 750 GB/day limit;
  waits and resumes automatically if the limit is reached anyway.
- Resumable, safe against concurrent runs, and drops incomplete snapshots if
  the backup disk disappears mid-upload.
- Guided `setup` (own Google OAuth client, generated encryption password,
  reconnecting to an existing backup on a new Mac), plus `status`, `restore`,
  `verify`, `snapshots`, `inspect` and a `restic` passthrough.

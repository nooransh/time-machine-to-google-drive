# rclone with tm2gdrive's patches

tm2gdrive needs a few changes to [rclone](https://github.com/rclone/rclone)'s
VFS layer, which `rclone mount` uses. They are in
[`tm2gdrive.patch`](tm2gdrive.patch), against the rclone version in
[`VERSION`](VERSION). Each was found by running real Time Machine backups
through Samba and FUSE-T.

1. **Truncating a file that isn't uploaded yet.** rclone failed with "can't
   open file - writer failed" (an I/O error) when a file had been written and
   closed but not uploaded yet, and then was truncated through its path.
   FUSE-T truncates that way, so Time Machine failed to create its disk
   image. Now the cached copy is truncated.
2. **`--vfs-cache-max-pending SIZE`.** It pauses writes while more than SIZE
   of closed files are waiting to be uploaded. Without it, the first backup
   is written to the Mac as fast as the disk allows and uploaded at the
   speed of the internet connection, so it can fill the Mac's disk. Files
   that are still open don't count, since they can't be uploaded until they
   are closed.
3. **Closing waits for writes in progress.** FUSE-T can send "release" for
   a file while writes to it are still running. A paused write then failed
   because the file had been closed underneath it.
4. **Moving or deleting a file after its folder was renamed.** rclone kept
   the file's old remote path, so moving or deleting it later failed and left
   a stale file behind. Time Machine renames its disk image folder right
   after creating it.
5. **`vfs/stats` reports files not yet uploaded.** `dirtyFiles`/`dirtyBytes`
   (all of them) and `pendingFiles`/`pendingBytes` (closed ones only).
   `tm2gdrive status` uses these.

rclone's own `vfs` and `vfs/vfscache` tests pass with the patches applied.
The plan is to offer them upstream; once rclone includes them, tm2gdrive can
use a normal rclone release again.

## How the binaries are built

[`.github/workflows/rclone.yml`](../.github/workflows/rclone.yml) builds
them on GitHub's macOS machines when a tag like `rclone-v1.75.2-tm2gdrive.1`
is pushed. It checks out that rclone version, applies the patch, runs the
tests and builds `rclone mount` support (`-tags cmount`) for Apple silicon
and Intel. The zips are attached to a GitHub release of that name, and
`tm2gdrive` checks them against the SHA256 checksums pinned in its source.

To build it yourself:

```bash
git clone --depth 1 --branch "$(cat rclone/VERSION)" https://github.com/rclone/rclone.git rclone-src
git -C rclone-src apply ../rclone/tm2gdrive.patch
cd rclone-src && CGO_ENABLED=1 go build -tags cmount -o rclone .
```

Building needs Go and the FUSE headers from FUSE-T
(`brew install --cask macos-fuse-t/cask/fuse-t`). To use your own build, set
`TM2GDRIVE_RCLONE=/path/to/rclone` when you run `tm2gdrive setup`.

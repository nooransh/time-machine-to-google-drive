# tm2gdrive

**Use Google Drive as your Time Machine backup disk.** No external drive, no NAS.

[![CI](https://github.com/nooranshdhaka/time-machine-to-google-drive/actions/workflows/ci.yml/badge.svg)](https://github.com/nooranshdhaka/time-machine-to-google-drive/actions/workflows/ci.yml)
![Platform: macOS](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

`tm2gdrive` adds a backup disk called **Google Drive Backup** to your Mac. It
behaves like a plugged-in drive, but everything on it is stored in your
Google Drive. Time Machine backs up to it every hour, and you keep using the
Time Machine app as before: enter Time Machine, scroll back through time,
and restore any file or folder.

- **Everything stays Time Machine:** hourly backups, the Time Machine app,
  Finder restores and Migration Assistant.
- **Encrypted on your Mac.** The backup disk is an AES-256 encrypted disk
  image, so Google only ever stores scrambled data.
- **Nothing to plug in.** A small background service keeps the disk mounted
  through restarts, sleep and Wi-Fi changes.
- **Resilient.** Backups land on the Mac first and upload in the background.
  If the Mac is offline or restarts, uploads pick up where they left off.
- **One command to set up.** It uses only macOS's built-in NFS client and
  [rclone](https://rclone.org): no kernel extensions, no virtual machines.

> **Status: new.** The full chain (service, Drive mount, encrypted disk,
> restarts, crash recovery, reading back from Drive) is tested on a real Mac in
> CI on every change. Time Machine's own backup engine can't run on CI
> machines, so keep your existing backup until you've seen a few hourly
> backups complete and tried a restore.

## Contents

- [How it works](#how-it-works)
- [Setup](#setup)
- [Using it](#using-it)
- [Restoring on a new Mac](#restoring-on-a-new-mac)
- [Settings](#settings)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Development](#development)

## How it works

```
Time Machine ──hourly──▶ "Google Drive Backup"   (encrypted APFS disk image, attached like a USB drive)
                                │
                                ▼  stored as 16 MB "band" files in
                        /private/var/tm2gdrive/drive   (your Drive folder, mounted over NFS on 127.0.0.1)
                                │
                                ▼  rclone: local cache → background upload
                         Google Drive  ›  tm2gdrive/TimeMachine.sparsebundle
```

1. **rclone serves your Drive folder** to the Mac over NFS, on the local
   machine only (127.0.0.1). macOS mounts it with its built-in NFS client.
2. **A sparse bundle disk image lives in that folder.** It's an encrypted
   APFS disk stored as many 16 MB files. Only the files that change are
   uploaded, and empty space takes up nothing.
3. **The image is attached as a normal disk** and set as a Time Machine
   destination, next to any disk you already use.
4. **Writes go to a local cache first.** rclone uploads each changed band
   about 30 seconds after Time Machine stops writing to it. Anything not yet
   uploaded survives restarts and crashes and is sent later. Reads come from
   the cache or are downloaded from Drive on demand.
5. **A LaunchDaemon** (`io.github.nooranshdhaka.tm2gdrive`) keeps it all
   running. If rclone ever stops, it is restarted, and the disk carries on:
   the NFS mount waits for it instead of failing.

## Setup

You need macOS 13 or later, [Homebrew](https://brew.sh), and a Google
account with enough Drive storage (about twice the data on your Mac is ideal).

### 1. Install

```bash
git clone https://github.com/nooranshdhaka/time-machine-to-google-drive.git ~/Developer/tm2gdrive
cd ~/Developer/tm2gdrive && bash install.sh
```

### 2. Create a Google client ID (free, ~5 minutes, once)

This is your own private "app" that lets rclone reach your Drive. rclone's
shared one
[stops working in 2026](https://rclone.org/drive/#making-your-own-client-id).

1. Open the [Google Cloud console](https://console.cloud.google.com/). Create
   a project named `tm2gdrive` and select it.
2. Go to **APIs & Services → Library**, find **Google Drive API**, and click
   **Enable**.
3. Go to **APIs & Services → OAuth consent screen** and click **Get started**.
   Use app name `tm2gdrive` and your email.
   - **Audience:** choose **Internal** for a Google Workspace (work) account,
     or **External** for a personal Gmail account.
4. Open **Data Access → Add or remove scopes**. Under **Manually add scopes**,
   add `https://www.googleapis.com/auth/drive.file`, then click **Update**
   and **Save**. With this scope, tm2gdrive can only see the files it
   creates.
5. **External only:** publish the app so Google doesn't sign you out every 7
   days.
   1. Under **Branding**, set the **home page** to
      `https://github.com/nooranshdhaka/time-machine-to-google-drive`.
   2. Set the **privacy policy** to
      `https://github.com/nooranshdhaka/time-machine-to-google-drive/blob/main/PRIVACY.md`.
   3. Add `github.com` as an **authorized domain**.
   4. Leave the logo empty: a logo triggers Google's verification.
   5. Open **Audience** and click **Publish app**.

   Google's verification isn't needed: you'll click past an "unverified app"
   notice once.
6. Open **Clients**, click **Create client**, and choose **Desktop app**.
   Keep the **Client ID** and **Client secret** for setup.

### 3. Run setup

```bash
tm2gdrive setup
```

Setup asks for:

- The client ID and secret. A browser opens: sign in with your Google
  account and allow access.
- Your Mac password, once. It's needed to install the background service.

Then it:

- creates the encrypted backup disk in Google Drive, sized at about twice
  your Mac's data (space is only used as it fills)
- shows you the **backup disk password**: **save it in your password
  manager**, because you need it to restore onto another Mac
- adds **Google Drive Backup** to Time Machine and offers to start the first
  backup

If macOS doesn't let setup add the disk to Time Machine itself, it opens
Time Machine settings. Click **Add Backup Disk**, choose **Google Drive
Backup**, and leave **Encrypt Backup** off: the disk is already encrypted.

## Using it

There's nothing to do: Time Machine backs up every hour by itself.

```bash
tm2gdrive status      # is everything running, and has it all reached Google Drive?
tm2gdrive logs        # what the background service has been doing
```

- **The first backup** is the big one: about the size of your data. It's
  written to the Mac first and uploaded as fast as your connection and
  Google allow (Google caps uploads at 750 GB a day). Leave the Mac on and
  connected until `tm2gdrive status` says **Everything is uploaded**.
- **Hourly backups** are small and upload within minutes.
- **Offline?** Time Machine still backs up, into the local cache, and
  everything uploads once you're back online.
- **Restoring:** use Time Machine as usual (Time Machine in the menu bar →
  **Browse Time Machine Backups**). Files that aren't cached are downloaded
  from Drive, so browsing old backups can be slower than a USB drive.

## Restoring on a new Mac

1. Install tm2gdrive ([steps 1–2](#setup), reusing your client ID).
2. Run `tm2gdrive setup`. It finds the existing backup disk in your Drive and
   asks for the **backup disk password**.
3. The disk appears as **Google Drive Backup**. Then either:
   - open **Migration Assistant** and choose **From a Mac, Time Machine
     backup or startup disk** to bring everything over, or
   - use **Browse Time Machine Backups** to pick out files.

## Settings

Settings are in `/Library/Application Support/tm2gdrive/config`. Edit them
with `sudo nano`, then run `tm2gdrive restart`.

| Setting | Default | Meaning |
|---|---|---|
| `DRIVE_FOLDER` | `tm2gdrive` | Google Drive folder that holds the backup disk |
| `VOLUME_NAME` | `Google Drive Backup` | Name of the disk in Finder and Time Machine (set before the first setup) |
| `DISK_SIZE_GB` | twice your data | Maximum size of the backup disk. Time Machine deletes the oldest backups when it's full. |
| `CACHE_MAX_GB` | `50` | Already-uploaded data kept on the Mac for speed |
| `CACHE_MIN_FREE_GB` | `20` | The cache gives space back when the Mac has less than this free |
| `TRANSFERS` | `8` | Parallel uploads |
| `BWLIMIT` | *(none)* | Optional speed limit, e.g. `20M` for 20 MB/s ([rclone format](https://rclone.org/docs/#bwlimit-bandwidth-spec)) |

## Troubleshooting

Start with `tm2gdrive status`, then `tm2gdrive logs`. Include both if you
[open an issue](https://github.com/nooranshdhaka/time-machine-to-google-drive/issues).

| Problem | Fix |
|---|---|
| The disk isn't attached | `tm2gdrive logs` shows why. Run `tm2gdrive restart`. |
| "Your Google sign-in has expired" or uploads fail with `invalid_grant` | Run `tm2gdrive reconnect`. If it happens weekly, publish your Google app (setup step 2.5). |
| Uploads are stuck | Check the internet connection, then look at `tm2gdrive logs`. Unsent data stays safely in the cache. |
| Time Machine says the disk is full | It deletes old backups automatically. To give it more room, raise `DISK_SIZE_GB` and run `hdiutil resize` (or set up a new disk). |
| The Mac's own disk is filling up | During the first backup, data waits in the cache until it's uploaded. Leave the Mac online so uploads can catch up; the space is freed as they finish. |

## Uninstall

```bash
tm2gdrive uninstall           # remove the service and the Time Machine disk
tm2gdrive uninstall --purge   # also delete the stored disk password and cache from this Mac
```

Your backups stay in Google Drive until you delete the folder.

## Development

- `test/unit-tests.sh` tests the script's logic on any OS.
- `test/integration-macos.sh` is the real test. On a disposable Mac it:
  - installs the service, mounts a local folder standing in for Drive, and
    creates and attaches the encrypted disk
  - writes data and checks that only encrypted bands reach "Drive"
  - restarts the service, kills rclone mid-write, and checks the data survives
  - clears the cache and reads everything back from "Drive"
  - simulates a new Mac, including a wrong password

  CI runs both, plus ShellCheck, on every push. The script targets the
  bash 3.2 that ships with macOS.

[Privacy policy](PRIVACY.md) · [Changelog](CHANGELOG.md) · [MIT License](LICENSE)

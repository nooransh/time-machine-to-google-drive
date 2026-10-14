# tm2gdrive

**Time Machine backups to Google Drive, encrypted on your Mac.** No external
drive, no NAS.

[![CI](https://github.com/nooranshdhaka/time-machine-to-google-drive/actions/workflows/ci.yml/badge.svg)](https://github.com/nooranshdhaka/time-machine-to-google-drive/actions/workflows/ci.yml)
![Platform: macOS](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

`tm2gdrive` gives Time Machine a network backup disk called **tm2gdrive**
whose contents live in your Google Drive. Time Machine backs up to it every
hour, and you keep using the Time Machine app as before.

- **Everything stays Time Machine:** hourly backups, the Time Machine app,
  browsing and restoring old versions.
- **Encrypted before upload.** File contents and names are encrypted on your
  Mac with a password only you have. Google only ever stores scrambled data.
- **Doesn't fill your Mac.** Backups wait on the Mac only until they're
  uploaded. When too much is waiting (5 GB by default), Time Machine simply
  slows down to your upload speed.
- **Runs as you, not as root.** No kernel extensions, no virtual machine, no
  system service. Administrator rights are only needed during setup.
- **One command to set up:** `tm2gdrive setup`.

> **Status: new (3.0).** Real Time Machine backups to real Google Drive work,
> including picking up again after a restart with an empty cache. CI tests
> the whole chain on a Mac on every change, apart from Time Machine itself,
> which can't run on CI machines. Restoring a complete backup hasn't been
> tested end to end yet, so keep your existing backup until you've restored
> some files from this one.

## Contents

- [How it works](#how-it-works)
- [Setup](#setup)
- [Using it](#using-it)
- [Restoring on a new Mac](#restoring-on-a-new-mac)
- [Settings](#settings)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)
- [Upgrading from 2.x](#upgrading-from-2x)
- [Development](#development)

## How it works

```
Time Machine ──hourly──▶ smb://127.0.0.1:44545/tm2gdrive    (Samba, on this Mac only)
                                │
                                ▼
                 ~/Library/Application Support/tm2gdrive/drive
                                │   rclone mount (FUSE-T): encrypts, keeps changed
                                ▼   files on the Mac until they're uploaded
                 Google Drive  ›  tm2gdrive-backups   (encrypted names and contents)
```

1. **Samba shares a folder as a Time Machine disk**, on 127.0.0.1 only, so
   nothing on your network can reach it. Time Machine treats it like a NAS:
   it keeps its backups in a disk image (a "sparse bundle") stored as many
   ~100 MB "band" files.
2. **That folder is your Google Drive folder,** mounted by
   [rclone](https://rclone.org) with
   [FUSE-T](https://www.fuse-t.org) (no kernel extension). rclone's
   [crypt](https://rclone.org/crypt/) layer encrypts every file and file
   name before it leaves the Mac.
3. **Changed bands are uploaded in the background** shortly after Time
   Machine finishes with them. Anything not yet uploaded survives restarts
   and crashes and is sent later. If too much is waiting, writes pause
   until uploads catch up, so the first backup never fills your disk.
4. **A LaunchAgent** (`io.github.nooranshdhaka.tm2gdrive`) keeps rclone and
   Samba running while you're logged in, and restarts them if they stop.

tm2gdrive uses a build of rclone with a few fixes that Time Machine needs
([rclone/README.md](rclone/README.md)). GitHub Actions builds it from
rclone's source, and setup checks its checksum.

## Setup

You need macOS 13 or later, [Homebrew](https://brew.sh), and a Google
account with enough Drive storage: about 1.5 times the data on your Mac.

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

### 3. Give your terminal Full Disk Access

Open **System Settings → Privacy & Security → Full Disk Access** and turn on
**Terminal** (or iTerm). If it isn't listed, click **+** and add it from
**Applications → Utilities**. Then **quit the terminal (⌘Q) and open it
again**.

Why: setup adds the backup disk with Apple's `tmutil` command, and macOS
only allows that from an app with Full Disk Access.

### 4. Run setup

```bash
tm2gdrive setup
```

Setup:

- installs FUSE-T (Homebrew asks for your Mac password), Samba, and the
  patched rclone
- asks for the client ID and secret, and opens a browser to sign in to
  Google
- creates the encrypted folder `tm2gdrive-backups` in your Drive and shows
  you the **backup password**. **Save it in your password manager:** you
  need it to restore onto another Mac.
- starts the background service and adds **tm2gdrive** to Time Machine
  (asks for your Mac password), then offers to start the first backup

**tm2gdrive** then shows up in **System Settings → General → Time Machine**,
next to any disks you already use.

## Using it

There's nothing to do: Time Machine backs up every hour by itself.

```bash
tm2gdrive status      # is everything running, and has it all reached Google Drive?
tm2gdrive logs        # what the background service has been doing
tm2gdrive password    # show the backup password
```

- **The first backup** is the big one: about the size of your data, uploaded
  as fast as your connection allows (Google caps uploads at 750 GB a day).
  At 40 Mbit/s, 300 GB takes about 17 hours. It carries on after sleep and
  restarts.
- **Hourly backups** only upload the bands that changed, usually within
  minutes.
- **The Mac's disk:** at most about 15 GB is used: up to 5 GB waiting to
  upload, up to 5 GB of recent data kept for speed, and the bands Time
  Machine has open.
- **Restoring:** use Time Machine as usual (Time Machine in the menu bar →
  **Browse Time Machine Backups**). Older data is downloaded from Drive, so
  it's slower than a USB drive.
- **Logged out?** The service runs while you're logged in. Time Machine
  backs up during that time, and also during Power Nap.

## Restoring on a new Mac

1. Install tm2gdrive ([steps 1–3](#setup), reusing your client ID).
2. Run `tm2gdrive setup`. It finds the existing backups in your Drive and
   asks for the **backup password**.
3. Time Machine now lists **tm2gdrive** with your old Mac's backups. Use
   **Browse Time Machine Backups** to restore files.

## Settings

Settings are in `~/Library/Application Support/tm2gdrive/config`. After
editing them, run `tm2gdrive restart`.

| Setting | Default | Meaning |
|---|---|---|
| `BACKUP_SIZE_GB` | 1.5 × your data | Size limit Time Machine sees; it deletes the oldest backups when full. Time Machine stores backups in bands of about this size ÷ 3800, and each changed band is uploaded again, so a much larger limit means more uploading. |
| `MAX_PENDING_GB` | `5` | Time Machine slows down while this much is waiting to upload |
| `CACHE_MAX_GB` | `5` | Already-uploaded data kept on the Mac for speed |
| `CACHE_MIN_FREE_GB` | `20` | The cache gives space back when the Mac has less than this free |
| `TRANSFERS` | `4` | Parallel uploads |
| `BWLIMIT` | *(none)* | Optional speed limit, e.g. `20M` for 20 MB/s ([rclone format](https://rclone.org/docs/#bwlimit-bandwidth-spec)) |
| `SMB_PORT` | `44545` | Local port of the Time Machine share |
| `DRIVE_FOLDER` | `tm2gdrive-backups` | Google Drive folder (set before the first setup) |

`BACKUP_SIZE_GB` only changes the band size of a new backup; Time Machine
keeps the band size of an existing one.

## Troubleshooting

Start with `tm2gdrive status`, then `tm2gdrive logs`. Include both if you
[open an issue](https://github.com/nooranshdhaka/time-machine-to-google-drive/issues).

| Problem | Fix |
|---|---|
| Setup says Time Machine didn't accept the disk | Give the terminal Full Disk Access ([step 3](#3-give-your-terminal-full-disk-access)), reopen it, and run `tm2gdrive setup` again. It keeps your sign-in and password. |
| "Your Google sign-in has expired" or uploads fail with `invalid_grant` | Run `tm2gdrive reconnect`. If it happens weekly, publish your Google app (setup step 2.5). |
| A backup failed right after a restart | The Mac's SMB client sometimes needs one retry after the service restarts. Time Machine tries again within the hour. |
| Uploads are stuck | Check the internet connection, then look at `tm2gdrive logs`. Unsent data stays safely on the Mac. |
| `status` says files are still open | Time Machine (or macOS) still has them open. They upload once closed, at the latest when the service restarts. |

## Uninstall

```bash
tm2gdrive uninstall           # remove the service and the Time Machine disk
tm2gdrive uninstall --purge   # also delete the sign-in, the backup password and the cache from this Mac
```

Your backups stay in Google Drive until you delete the folder. FUSE-T and
Samba stay installed (`brew uninstall --cask fuse-t`, `brew uninstall samba`).

## Upgrading from 2.x

macOS 27 no longer accepts disk images as Time Machine disks, which is how
2.x worked. 3.0 can't use 2.x backups. Uninstall 2.x first:

```bash
sudo "/Library/Application Support/tm2gdrive/bin/tm2gdrive" uninstall
```

Then follow [Setup](#setup). 3.0 uses a new Drive folder, so your 2.x
backup disk stays in the `tm2gdrive` folder until you delete it.

## Development

- `test/unit-tests.sh` tests the script's logic on any OS.
- `test/integration-macos.sh` runs the real setup and service on a Mac with
  a local folder standing in for Google Drive. It writes over SMB like Time
  Machine, crashes rclone, restarts with an empty cache, and restores with
  the backup password. CI runs both, plus ShellCheck.
- [`rclone/`](rclone/) holds the rclone patches and how they're built.

# tm2gdrive

**Back up all your Time Machine backups, with their full history, to Google Drive.**

[![CI](https://github.com/nooranshdhaka/time-machine-to-google-drive/actions/workflows/ci.yml/badge.svg)](https://github.com/nooranshdhaka/time-machine-to-google-drive/actions/workflows/ci.yml)
![Platform: macOS](https://img.shields.io/badge/platform-macOS%2011%2B-lightgrey)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

Time Machine protects you from a dead Mac, but not from losing the Time Machine
disk too (fire, theft, a failed drive). `tm2gdrive` puts an off-site copy of
every Time Machine backup in your Google Drive:

- **Encrypted on your Mac** before upload. Google only ever stores scrambled data.
- **Deduplicated and compressed.** Each file is stored once, however many
  backups contain it. Your whole Time Machine history takes about as much
  space as the Time Machine disk itself.
- **Stays under Google's 750 GB/day upload limit** automatically. If the limit
  is hit anyway, it waits and carries on.
- **Resumable.** Stop it, close the laptop, or lose Wi-Fi, then run it again
  and it picks up where it left off.
- **Incremental.** Later runs upload only new Time Machine backups, and only
  what changed in them.
- **Keeps history that Time Machine deletes.** When Time Machine thins out old
  backups on your disk, the copies on Drive stay.

`tm2gdrive` is a single shell script built on two well-established
open-source tools: [restic](https://restic.net) handles encrypted,
deduplicating backups, and [rclone](https://rclone.org) handles Google Drive.

## Contents

- [How long will it take?](#how-long-will-it-take)
- [Setup](#setup)
- [Uploading](#uploading)
- [Restoring](#restoring)
- [Privacy](PRIVACY.md)
- [Settings](#settings)
- [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works)
- [Development](#development)

## How long will it take?

Google allows **750 GB of uploads per account per day**, however fast your
connection is. A gigabit line uploads 750 GB in about two hours, then has to
wait for the next day.

| Time Machine disk usage | First upload (at the default 680 GiB/day) |
|---|---|
| 1 TB | ~1.5 days |
| 2 TB | ~3 days |
| 4 TB | ~5.5 days |
| 5 TB | ~7 days |

Compression often shortens this. After the first upload, each new Time
Machine backup takes minutes. `tm2gdrive status` estimates the time for your
own disk.

> Your Drive storage is shared with Gmail and Google Photos, so check there's
> room. `tm2gdrive status` shows Drive free space next to your Time Machine
> disk usage.

## Setup

About 15 minutes, once. You need macOS 11 or later, [Homebrew](https://brew.sh),
and your Time Machine disk.

### 1. Install

```bash
git clone https://github.com/nooranshdhaka/time-machine-to-google-drive.git
cd time-machine-to-google-drive
bash install.sh
```

This installs `restic`, `rclone` and the `tm2gdrive` command with Homebrew.
Downloading the ZIP from GitHub works too.

### 2. Create a Google client ID (free, ~5 minutes)

rclone needs its own app registration with Google to upload to your Drive.
rclone's shared registration
[stops working during 2026](https://rclone.org/drive/#making-your-own-client-id)
and is heavily rate-limited anyway.

1. Open the [Google Cloud console](https://console.cloud.google.com/) and sign
   in. Any Google account works.
2. Create a project: in the project picker at the top, choose **New project**,
   name it `tm2gdrive`, click **Create**, then select it.
3. Go to **APIs & Services → Library**, search for **Google Drive API**, and
   click **Enable**.
4. Go to **APIs & Services → OAuth consent screen** (also labelled **Google
   Auth Platform**) and click **Get started**:
   - App name: `tm2gdrive`. User support email: your email.
   - **Audience:**
     - If your Drive is a **Google Workspace** (work) account, choose
       **Internal**. Internal apps need no publishing or verification.
     - For a personal @gmail.com account, choose **External**.
   - Contact email: yours. Agree to the policy and click **Create**.
5. Open **Data Access**, then **Add or remove scopes**. Under *Manually add
   scopes*, paste `https://www.googleapis.com/auth/drive.file`, click **Add to
   table**, then **Update** and **Save**. This scope lets the app see only the
   files it creates, not the rest of your Drive.
6. **External only:** publish the app (see [Publishing the app](#publishing-the-app)
   below). If you skip this, Google signs the app out every 7 days and you
   have to run `tm2gdrive reconnect` each week.
7. Open **Clients**, click **Create client**, choose **Desktop app**, and click
   **Create**. Keep the **Client ID** and **Client secret** for the next steps.

#### Publishing the app

Google only lets an External app leave "Testing" once its branding page has a
home page and a privacy policy. This repository provides both:

1. Open **Branding** and fill in:
   - **Application home page:** `https://github.com/nooranshdhaka/time-machine-to-google-drive`
   - **Application privacy policy link:** `https://github.com/nooranshdhaka/time-machine-to-google-drive/blob/main/PRIVACY.md`
   - **Authorized domains:** `github.com`
   - Leave the **App logo** empty. Uploading a logo makes Google require
     verification before the app can be used.

   Click **Save**.
2. Open **Audience**, click **Publish app**, and confirm. The status changes to
   **In production**.

Google's verification isn't needed for personal use: you'll just click
through an "unverified app" warning once, during setup. If you fork this
project, use your fork's URLs, or your own website and privacy page.

If you would rather not publish, the app still works in Testing. Add yourself
under **Audience → Test users** and run `tm2gdrive reconnect` whenever
tm2gdrive says your Google sign-in has expired (every 7 days).

### 3. Give your terminal Full Disk Access

macOS protects Time Machine data. Open **System Settings → Privacy & Security →
Full Disk Access** and turn it on for **Terminal** (or iTerm). Then quit the
terminal and open it again.

### 4. Run setup

```bash
tm2gdrive setup
```

Setup:

- checks the tools and Full Disk Access, and finds your Time Machine disk
- asks for the client ID and secret, then opens a browser so you can sign in
  to Google. Use the account with the storage plan. If Google warns about an
  unverified app, click *Advanced → Go to tm2gdrive*.
- generates an **encryption password** and creates the encrypted backup in
  the Drive folder `TimeMachine-tm2gdrive`

> 🔑 **Save the encryption password in your password manager.** A copy is kept
> in `~/.config/tm2gdrive/restic-password`. But if your Mac and Time Machine
> disk are both gone and you don't have the password, nobody can decrypt the
> backup, not even you.

## Uploading

```bash
tm2gdrive status             # what's on the Time Machine disk vs. Drive, with estimates
tm2gdrive backup --dry-run   # check that everything works, without uploading
tm2gdrive backup             # start uploading
```

Commands that touch the backup ask for your Mac password. They need
administrator rights to mount Time Machine snapshots and read every file.

The newest backup goes first, so your most important data is safe soonest.
Older backups follow, and they're quick because most of their data is
already uploaded.

While it runs:

- **Keep the Mac plugged in and the lid open.** `tm2gdrive` keeps the Mac
  awake itself, but closing a laptop lid still sleeps it (unless you use an
  external display).
- Keep the Time Machine disk connected. Time Machine can keep running as normal.
- **Stop it any time with Ctrl+C**, then run `tm2gdrive backup` to continue.
  Progress is checkpointed every few minutes.
- If Google's daily limit is reached, it waits 3 hours and retries on its own.
- Logs are saved in `~/.config/tm2gdrive/logs/`.

| Option | What it does |
|---|---|
| `--dry-run` | Show what would be uploaded, without uploading |
| `--only-latest` | Upload only the most recent Time Machine backup |
| `--oldest-first` | Upload from oldest to newest instead |
| `--max N` | Stop after N backups (e.g. `--max 1` for a first test) |
| `--since 2025-01-31` | Skip backups older than this date |
| `--dest "/Volumes/My Backup"` | Choose the Time Machine disk explicitly |

**Staying up to date:** run `tm2gdrive backup` again whenever you like, e.g.
weekly. It uploads only Time Machine backups that aren't on Drive yet.

## Restoring

```bash
tm2gdrive snapshots                                    # list the backups on Drive
tm2gdrive restore latest ~/Restored                    # restore the newest backup
tm2gdrive restore 2025-06-01-093012 ~/Restored         # or a specific one
tm2gdrive restore latest ~/Restored \
    --include "/Macintosh HD - Data/Users/YOU/Documents"   # or just one folder
```

Files come back with their dates, permissions and extended attributes. Paths
inside a backup start with the name of the backed-up volume, usually
`/Macintosh HD - Data`. To browse first, run
`tm2gdrive restic ls latest | less`.

**On a new Mac:** install `tm2gdrive` (setup steps 1–3), then run
`tm2gdrive setup` with the **same client ID**. It finds the existing backup on
Drive and asks for its encryption password.

**If the client ID is gone too** (you deleted the Google Cloud project), create
a new one as in step 2. In step 5, add the scope
`https://www.googleapis.com/auth/drive` instead. Then run
`tm2gdrive setup --full-drive-access`. The `drive.file` scope only shows files
created by the same client ID, so a new one needs access to all of Drive to
find the old backup.

**Checking the backup:** run `tm2gdrive verify` now and then. It downloads
10 GB of the backup and checks it. `tm2gdrive verify 100%` checks everything.

## Settings

Settings live in `~/.config/tm2gdrive/config`:

| Setting | Default | Meaning |
|---|---|---|
| `DAILY_UPLOAD_GB` | `680` | Upload cap in GiB/day (680 GiB ≈ 730 GB, just under Google's 750 GB). `0` uploads at full speed and waits whenever Google's limit is hit. |
| `DRIVE_FOLDER` | `TimeMachine-tm2gdrive` | Folder in Google Drive. Use a different one for each Mac. |
| `TM_DEST` | *(detected)* | Mount point of the Time Machine disk |
| `MACHINE_NAME` | computer name | Label stored with each backup |
| `PACK_SIZE_MB` | `64` | Size of the uploaded chunks. Bigger means fewer files; Drive creates only ~2 files a second. |
| `CONNECTIONS` | `6` | Parallel uploads |
| `READ_CONCURRENCY` | `2` | Files read at once from the disk. 2 suits hard drives; try 4–8 for SSDs. |
| `QUOTA_WAIT_MINUTES` | `180` | Wait after reaching Google's daily limit |
| `ERROR_WAIT_MINUTES` / `MAX_ERROR_RETRIES` | `10` / `5` | Retry policy for other errors (e.g. network drops) |

Every restic feature is available through `tm2gdrive restic ...`, for example
`tm2gdrive restic stats`.

**Trimming old history (optional).** Nothing is ever deleted from Drive by
default. To thin it out with restic's retention rules, for example daily
backups for 30 days, weekly for a year and monthly forever:

```bash
tm2gdrive restic forget --tag tm2gdrive --keep-daily 30 --keep-weekly 52 --keep-monthly 1000 --prune
```

## Troubleshooting

Start with **`tm2gdrive inspect`**. It shows what the tool sees: your Time
Machine disk, its snapshots, the backup list and the latest backup's contents.
Include its output if you open an issue.

| Problem | Fix |
|---|---|
| "No mounted Time Machine disk found" | Connect the disk (unlock it if it's encrypted), or pass `--dest "/Volumes/<name>"`. |
| "needs Full Disk Access" | See [setup step 3](#3-give-your-terminal-full-disk-access), and restart the terminal afterwards. |
| "Several Time Machine disks are mounted" | Pass `--dest`, or set `TM_DEST` in the settings. |
| Network Time Machine (NAS / Time Capsule) | Mount the backup first, e.g. by starting a Time Machine backup, so it appears as `/Volumes/Backups of …`. Then use `--dest "/Volumes/Backups of …"`. |
| "Google Drive is full" | Free up space or upgrade your plan, then run `tm2gdrive backup` again. |
| "Your Google sign-in has expired" | Run `tm2gdrive reconnect`, then run your command again. If it happens weekly, [publish the app](#publishing-the-app). |
| "repository is already locked" | Locks left by a crash are cleared automatically. If one remains and nothing is running: `tm2gdrive restic unlock --remove-all` |

## How it works

1. **Since macOS Big Sur, every Time Machine backup is an APFS snapshot** on
   the backup disk (`com.apple.TimeMachine.YYYY-MM-DD-HHMMSS.backup`). Copying
   the disk's files loses that history, and Google Drive can't be a Time
   Machine destination. Uploading the raw disk image means multi-TB uploads
   that start over after every change.
2. `tm2gdrive` therefore **mounts each snapshot read-only** with `mount_apfs`
   and backs up its contents with **restic**. Each Time Machine backup becomes
   one restic snapshot, with the Time Machine date and the tag `tm:<date>`.
   restic's content-defined chunking stores identical data only once, so
   successive backups add only what changed. Each backup is also compared
   with a neighbouring one that's already uploaded (`--parent`), so only
   files whose size or modification time changed are read from the disk.
   Older HFS+ Time Machine disks (`Backups.backupdb`) work too; their backups
   are plain folders.
3. **Google Drive's limits shaped the settings:**
   - **750 GB/day upload limit:** uploads are capped at 680 GiB/day. rclone's
     `--drive-stop-on-upload-limit` turns the limit error into one
     `tm2gdrive` can detect, wait out and retry.
   - **About 2 new files per second:** restic writes 64 MiB chunks instead
     of 16 MiB.
   - **Deleted files count against your quota while in the trash:** files
     are deleted with `--drive-use-trash=false`.
   - **Your own client ID with the narrow `drive.file` scope.**
4. **Interruptions are cheap.** restic saves its index at least every 10
   minutes, so a stopped upload loses only a few minutes of work. A lock stops
   two runs from overlapping. If the disk disappears mid-upload, the
   incomplete snapshot is discarded and redone next time.

## Development

The `test/` folder holds an end-to-end suite. It runs the real script with
real restic and rclone; a local folder stands in for Google Drive, and fakes
stand in for `tmutil`, `diskutil` and `mount_apfs`. It runs on Linux and
macOS:

```bash
sudo -E bash test/run-tests.sh
```

`test/integration-macos.sh` goes further on a Mac. It makes a real Time
Machine backup onto a disk image, runs `tm2gdrive` against it with the real
macOS tools, restores the result and compares it with the original. CI runs
both, plus [ShellCheck](https://www.shellcheck.net), on every push.

The script targets the bash 3.2 that ships with macOS.

## Uninstall

```bash
rm "$(brew --prefix)/bin/tm2gdrive"
rm -rf ~/.config/tm2gdrive ~/Library/Caches/tm2gdrive   # deletes settings AND the stored password: save it first
```

The backup itself stays in your Google Drive folder `TimeMachine-tm2gdrive`
until you delete it.

## License

[MIT](LICENSE)

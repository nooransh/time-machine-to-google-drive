# Privacy policy

tm2gdrive is a command-line tool that runs entirely on your own Mac. It has no
servers and no analytics, and it collects no data about you.

**What it accesses.** When you connect it to Google Drive, you authorize your
*own* Google Cloud app, the client ID you create during setup. With the
default `drive.file` permission, that app can see and change only the files
tm2gdrive itself creates in your Drive: the folder that holds your backup
disk.

**Where your data goes.** Time Machine writes your backups to an encrypted
disk image (AES-256) on your Mac, with a password only you hold. Only the
encrypted image files are uploaded, straight from your Mac to your own Google
Drive. Nothing is sent to the authors of tm2gdrive or to anyone else. Google
stores the encrypted files under
[Google's privacy policy](https://policies.google.com/privacy).

**What stays on your Mac:**

- Settings, the Google sign-in token and the disk password are in
  `/Library/Application Support/tm2gdrive/`, readable only by root.
- A cache of the backup disk is in `/Library/Caches/tm2gdrive/`.
- The log is `/Library/Logs/tm2gdrive.log`.

**Removing access.** Run `tm2gdrive uninstall --purge` and revoke the app at
<https://myaccount.google.com/permissions>. The backup in your Drive stays
there until you delete it.

Questions: open an issue at
<https://github.com/nooranshdhaka/time-machine-to-google-drive/issues>.

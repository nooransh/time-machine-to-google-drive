# Privacy policy

tm2gdrive is a command-line tool that runs entirely on your own Mac. It has no
servers and no analytics, and it collects no data about you.

**What it accesses.** When you connect it to Google Drive, you authorize your
*own* Google Cloud app, the client ID you create during setup. With the
default `drive.file` permission, that app can see and change only the files
tm2gdrive itself creates in your Drive: the folder that holds your backups.

**Where your data goes.** Every backup file and file name is encrypted on
your Mac ([rclone crypt](https://rclone.org/crypt/): XSalsa20-Poly1305 for
contents, AES-256 for names), with a password only you hold. Only encrypted
files are uploaded, straight from your Mac to your own Google Drive. The
Time Machine share tm2gdrive runs on your Mac is reachable only from the Mac
itself (127.0.0.1). Nothing is sent to the authors of tm2gdrive or to anyone else. Google
stores the encrypted files under
[Google's privacy policy](https://policies.google.com/privacy).

**What stays on your Mac:**

- Settings, the Google sign-in token and the backup password are in
  `~/Library/Application Support/tm2gdrive/`, readable only by your user.
- Backup files waiting to be uploaded, and recently used ones, are in
  `~/Library/Caches/tm2gdrive/` (unencrypted, like your data itself).
- The log is `~/Library/Logs/tm2gdrive.log`.

**Removing access.** Run `tm2gdrive uninstall --purge` and revoke the app at
<https://myaccount.google.com/permissions>. The backup in your Drive stays
there until you delete it.

Questions: open an issue at
<https://github.com/nooranshdhaka/time-machine-to-google-drive/issues>.

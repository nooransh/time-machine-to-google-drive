# Privacy policy

tm2gdrive is a command-line tool that runs entirely on your own Mac. It has no
servers and no analytics, and it collects no data about you.

**What it accesses.** When you connect it to Google Drive, you authorize your
*own* Google Cloud app (the client ID you create during setup). With the
default `drive.file` permission, that app can see and change only the files
tm2gdrive itself creates in your Drive: the encrypted backup folder.

**Where your data goes.** Your Time Machine data is encrypted on your Mac with
a password only you hold, then uploaded straight from your Mac to your own
Google Drive. Nothing is sent to the authors of tm2gdrive or to anyone else.
Google stores the encrypted data under
[Google's privacy policy](https://policies.google.com/privacy).

**What stays on your Mac.** Settings, the Google sign-in token, the
encryption password and logs are kept in `~/.config/tm2gdrive/`. A cache
lives in `~/Library/Caches/tm2gdrive/`.

**Removing access.** Revoke the app at
<https://myaccount.google.com/permissions> and delete the folders above. The
backup in your Drive stays there until you delete it.

Questions: open an issue at
<https://github.com/nooranshdhaka/time-machine-to-google-drive/issues>.

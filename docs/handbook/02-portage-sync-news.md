# Syncing Portage & reading news

> Refresh the ebuild repository so Portage knows about current package versions,
> optionally pick the fastest mirrors first, then read the official news items that
> can affect your next upgrade. Mirrors the script's step 01 (`--no-sync`, `--mirrors`).

## What the script automates

`step_01_sync_news` optionally runs `mirrorselect` to write the fastest
`GENTOO_MIRRORS` into `make.conf` (only with `--mirrors`), then syncs the Portage tree
(preferring `eix-sync` if it is installed, otherwise `emerge --sync` with an
`emerge-webrsync` fallback), and finally shows unread news with `eselect news read new`.
The end state is an up-to-date `/var/db/repos/gentoo` and a news queue you have seen.

## Concepts

Portage builds from an **ebuild repository**: a local tree of package recipes under
`/var/db/repos/gentoo`. Nothing you emerge is newer than that tree, so syncing is the
first thing you do on a fresh system and before any big upgrade.

There are three common ways to refresh it, and the script picks between them:

- **`emerge --sync`** uses the modern `rsync`-based (or git, depending on your repo
  config) sync defined in `/etc/portage/repos.conf`. It is the standard, incremental
  method: fast after the first run, and it verifies the tree's cryptographic signature.
- **`emerge-webrsync`** downloads a single signed daily snapshot over HTTP(S). It is
  the fallback when plain `rsync` is blocked (restrictive firewall, rsync port closed)
  or when a mirror is misbehaving. It transfers more data but needs only HTTPS.
- **`eix-sync`** is a thin wrapper from `app-portage/eix`: it runs the sync, then
  rebuilds the local `eix` search index so `eix <pkg>` searches stay instant. The
  script prefers it *if it is already installed* (you install it in
  [Portage tooling](05-portage-tooling.md)); it is a convenience, not a different sync.

**Mirrors.** `GENTOO_MIRRORS` in `make.conf` is the ordered list of download servers
Portage pulls source tarballs (distfiles) from. A geographically close, fast mirror
makes every later build download quicker. `app-portage/mirrorselect` benchmarks the
official mirror list and writes the fastest ones back into `make.conf` for you.

**News.** Gentoo ships **news items** through the repository: short notices about
changes that may need manual action (profile switches, breaking updates, config
migrations). Ignoring a relevant news item is a common cause of a broken upgrade, so
Portage nags you until you read them with `eselect news`.

## Do it by hand

### 1. (Optional) Pick the fastest mirrors

Do this only if you want the script's `--mirrors` behavior; it rewrites `GENTOO_MIRRORS` in `make.conf`.
Install the tool if you do not have it, back up `make.conf` first (a bad mirror list
is annoying to undo otherwise), then benchmark:

```bash
# root
emerge --ask=n app-portage/mirrorselect
cp -a /etc/portage/make.conf /etc/portage/make.conf.gpi.bak   # once, if no backup yet
mirrorselect -s3 -b10 -D
```

- `-s3`: keep the 3 fastest mirrors (a short list with redundancy, not just one).
- `-b10`: benchmark using 10 blocks of 100 KB each, so the speed test has enough data
  to be meaningful instead of measuring connection setup noise.
- `-D`: deep mode, which actually downloads test data from each candidate rather than
  guessing from the server list.

Without `-o`, `mirrorselect` edits `make.conf` in place (replacing `GENTOO_MIRRORS`),
which is what the script relies on. If you would rather review before applying, use
`mirrorselect -s3 -b10 -D -o` to print the line to stdout and paste it in yourself.

### 2. Sync the Portage tree

If `eix-sync` is available, prefer it so your search index updates in the same step:

```bash
# root
eix-sync
```

Otherwise use the standard sync, with the web fallback if it fails:

```bash
# root
emerge --sync || emerge-webrsync
```

`emerge --sync` does an incremental rsync/git pull of the ebuild tree and verifies its
signature. If that fails (rsync blocked, mirror error), `emerge-webrsync` fetches a
signed daily snapshot over HTTPS instead. Either way you end up with a current,
verified `/var/db/repos/gentoo`.

### 3. Read the news

```bash
# root
eselect news read new
```

This prints every news item you have not yet read. `read new` shows only unread ones;
`eselect news list` lists all of them, and `eselect news read <number>` re-reads a
specific item. Read these before you run the big `@world` upgrade in
[Updating @world & cleanup](06-world-update.md), because some items tell you to change
config or a profile first.

## Verify

```bash
# root
emerge --info | grep -E '^(GENTOO_MIRRORS|SYNC)'   # confirm mirrors / sync source
eselect news count                                 # should report 0 new after reading
ls -la --time-style=+%F /var/db/repos/gentoo/metadata/timestamp.chk
```

`eselect news count` printing `0` (or no "new" items) means the queue is clear. The
repository `timestamp.chk` carrying today's date confirms the sync actually landed. You
can also run `eix -u` (if `eix` is installed) to list packages with pending updates.

## Pitfalls and rollback

- **Syncing too often.** The rsync mirrors ask you not to sync more than once a day;
  hammering them can get your IP rate-limited. Sync when you are about to upgrade, not
  on a loop.
- **Skipping the news.** A missed news item is the single most common cause of a failed
  upgrade. Always run `eselect news read new` after a sync.
- **`emerge --sync` fails with a signature/key error.** Make sure
  `sec-keys/openpgp-keys-gentoo-release` is installed and your clock is correct, then
  retry; `emerge-webrsync` is the quick workaround.
- **Warning:** **A bad mirror list** from `mirrorselect` can leave distfile fetches slow or
  failing. **Rollback** is just restoring the backup you made in step 1:
  ```bash
  # root
  cp -a /etc/portage/make.conf.gpi.bak /etc/portage/make.conf
  ```
  Syncing itself changes only the repository tree, which has no rollback: a later sync
  simply brings it current again.

## Script reference

- **Step:** `01` - `step_01_sync_news`
- **Flags:** `--no-sync` (skip the tree sync), `--mirrors` (run `mirrorselect` first)
- **Managed files:** `/etc/portage/make.conf` (`GENTOO_MIRRORS`, only with `--mirrors`;
  backed up to `make.conf.gpi.bak`). The sync updates `/var/db/repos/gentoo` but writes
  no managed drop-in.

---
[← Previous: The base install (recap)](01-base-install.md) · [Handbook index](README.md) · [Next: Tuning make.conf →](03-make-conf.md)

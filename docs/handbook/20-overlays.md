# Overlays / repositories

> Add extra ebuild repositories (overlays) to Portage: enable an official one like
> `guru` or `pentoo` by name, or add your own from a git URL, then sync it. Mirrors the
> script's step 18 (`--overlay`).

## What the script automates

`step_18_repositories` makes sure `eselect-repository` is installed, then for each
overlay you name it either enables an official repository (looked up in Gentoo's
repository list) or adds a custom one from a `name=git-url` spec, and syncs it with
`emaint`. If `eix` is installed, it refreshes the eix index afterward. With no
`--overlay`, the step does nothing.

## Concepts

The main Gentoo ebuild repository (`::gentoo`) does not contain every package. Overlays
fill the gaps.

- **An overlay (or repository) is a second tree of ebuilds** that Portage reads
  alongside `::gentoo`. Each has a short name and a `::name` suffix you can use in
  atoms, for example `app-text/obsidian::r7l`.
- **`eselect-repository`** (`app-eselect/eselect-repository`) is the modern tool for
  managing them. It knows Gentoo's official **repository list** (so official overlays
  can be enabled by name) and writes its config to
  `/etc/portage/repos.conf/eselect-repo.conf`. It is the successor to the older
  `layman`.
- **Official vs custom.** Official overlays are curated and listed by Gentoo; you
  `enable` them by name. A custom overlay is any git repository you trust; you `add` it
  with an explicit name and URL.
- **Enabling is not syncing.** Enabling only registers the repository config. You must
  then **sync** (clone/pull) it before its ebuilds exist locally. The script uses
  `emaint sync -r <name>` to sync exactly the one repository it just added.
- **Popular overlays** (from the script's `--list-overlays`): `guru` (large community
  overlay), `steam-overlay` (Valve Steam, see `--steam`), `r7l` (Obsidian and other
  desktop apps), `pentoo` (security/pentesting tools), and `science`.

**Warning:** **An overlay is code you will run as root at build time.** Ebuilds execute arbitrary
shell during `emerge`, and overlays are not reviewed by the Gentoo security team the way
`::gentoo` is. Only enable overlays you trust, prefer official ones, and pin a specific
git URL you control for custom trees.

## Do it by hand

All steps are privileged (run as root).

### 1. Make sure eselect-repository is available

```bash
# root
eselect repository list >/dev/null 2>&1 || \
  emerge --ask=n app-eselect/eselect-repository dev-vcs/git
mkdir -p /etc/portage/repos.conf
```

The guard only installs when `eselect repository` does not already work, so re-running
is cheap. `dev-vcs/git` is needed because git-synced overlays are cloned with it, and
`/etc/portage/repos.conf` is where the config lands.

### 2a. Enable an official overlay by name

```bash
# root
eselect repository enable guru
```

This looks `guru` up in Gentoo's repository list and writes its config into
`/etc/portage/repos.conf/eselect-repo.conf`. The script first checks
`eselect repository list -i` (installed/enabled list) and skips the enable if the
overlay is already there, so it is idempotent. You can list a few at once; the script
accepts `--overlay guru,pentoo,science` and enables each in turn.

### 2b. Add a custom overlay from a git URL

For a repository not in the official list, add it explicitly as `name` plus `git` plus
URL (the script's `name=git-url` form):

```bash
# root
eselect repository add myoverlay git https://git.example.org/myoverlay.git
```

`add` registers a new repository named `myoverlay` whose sync type is `git` and whose
source is that URL. Pick a name that does not collide with an existing one.

### 3. Sync the overlay

Enabling or adding only writes config; sync pulls the ebuilds down:

```bash
# root
emaint sync -r guru          # sync just this one repository by name
```

`emaint sync -r <name>` syncs a single named repository, which is faster and clearer
than a full `emerge --sync` of everything. Repeat per overlay you enabled or added.

### 4. (Optional) refresh the eix index

If you use `eix` for fast searching, update its index so it sees the new ebuilds:

```bash
# root
eix-update
```

The script runs this automatically when `eix-update` is present.

## Verify

```bash
# root
eselect repository list -i                      # enabled repositories, your overlay listed
cat /etc/portage/repos.conf/eselect-repo.conf   # its [name], location, sync-uri
ls /var/db/repos/                                # the synced tree exists on disk
```

A quick end-to-end check: search for a package you know lives in the overlay and confirm
Portage sees the `::name` source, for example `emerge --search guru-only-package` or
`eix -R <name>`. If the tree is missing from `/var/db/repos/`, the sync did not run.

## Pitfalls and rollback

- **Enabled but no ebuilds** → you forgot to sync. Run `emaint sync -r <name>`.
- **`eselect repository enable <name>` fails** → the name is not in the official list.
  Check spelling against `eselect repository list`, or add it as a custom
  `name=git-url` instead.
- **Package masked / keyworded after adding an overlay** → overlay packages are often
  `~arch` or need extra `package.accept_keywords`/`package.license` entries. That is
  normal; add the keywords deliberately.
- **Too many overlays** → more trees mean slower syncs, more unreviewed ebuilds, and a
  higher chance of version conflicts with `::gentoo`. Enable only what you use.
- **Rollback:** this step is **not** touched by the script's `--rollback`. Remove an
  overlay by hand (this disables it and deletes its synced tree):
  ```bash
  # root
  eselect repository remove -f myoverlay
  ```
  `remove` deletes the config entry; `-f` also removes the on-disk tree under
  `/var/db/repos/`. Packages you already installed from the overlay stay installed until
  you unmerge or rebuild them.

## Script reference

- **Step:** `18` - `step_18_repositories` (+ `_enable_overlay`,
  `_ensure_eselect_repository`)
- **Flags:** `--overlay <list>` (comma list of official names and/or `name=git-url`
  specs; repeatable). Related: `--list-overlays` prints the popular set and exits.
- **Managed files:** `/etc/portage/repos.conf/eselect-repo.conf` (written by
  `eselect repository`), synced trees under `/var/db/repos/<name>/`.

---
[← Previous: GPU drivers](19-gpu-drivers.md) · [Handbook index](README.md) · [Next: Applications →](21-applications.md)

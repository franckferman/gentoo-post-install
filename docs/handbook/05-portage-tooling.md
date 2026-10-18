# Portage tooling

> Install the small set of utilities that make day-to-day Portage work bearable:
> querying what owns a file, fast package search, cleaning up, and timing builds.
> Mirrors the script's step 04 (no dedicated flag; part of the default run).

## What the script automates

`step_04_portage_tooling` installs five packages that every practical Gentoo system
wants (`gentoolkit`, `eix`, `portage-utils`, `genlop`, `mirrorselect`) and then, if
`eix-update` is present, builds the `eix` search index so `eix <pkg>` works
immediately. None of these change system behavior; they are the toolbox you reach for
in every later chapter.

## Concepts

Plain Portage (`emerge`, `equery` aside) can do everything, but it is slow to search
and gives you little visibility. These tools fill the gaps. Here is what each one is
for, so you install them deliberately rather than as a blob:

- **`app-portage/gentoolkit`** is the core maintenance suite. It gives you:
  - **`equery`**: ask questions about packages. `equery belongs <file>` finds which
    package owns a file, `equery uses <pkg>` shows a package's USE flags and which are
    on, `equery depends <pkg>` lists reverse dependencies.
  - **`eclean`**: reclaim disk space. `eclean distfiles` deletes downloaded source
    tarballs no longer needed; `eclean packages` prunes stale binary packages.
  - **`revdep-rebuild`**: find and rebuild packages whose shared libraries broke after
    an upgrade (reverse-dependency breakage), the classic fix for "cannot open shared
    object file" errors.
- **`app-portage/eix`** builds a compact binary index of the ebuild tree so searching
  is instant. `eix firefox` is far faster than `emerge --search`, and `eix -u` lists
  installed packages with pending updates. The index is refreshed with **`eix-update`**
  (and conveniently during **`eix-sync`**, which you saw in
  [Syncing Portage & reading news](02-portage-sync-news.md)).
- **`app-portage/portage-utils`** is a set of tiny, fast C utilities, the **`q*`**
  tools: `qlist -I` lists installed packages, `qlist <pkg>` lists a package's files,
  `qsize <pkg>` shows installed size, `qfile <file>` is a quick "what owns this",
  `qdepends` shows dependencies. They start instantly, which matters in scripts and on
  slow machines where the Python-based `equery` feels heavy.
- **`app-portage/genlop`** reads Portage's emerge log (`/var/log/emerge.log`) to show
  build **history and time estimates**: `genlop -t <pkg>` reports how long past builds
  took, `genlop -c` estimates time remaining on the current emerge, `genlop -l` prints
  the merge history.
- **`app-portage/mirrorselect`** benchmarks and picks fast `GENTOO_MIRRORS`. The sync
  chapter already uses it with `--mirrors`; installing it here keeps it available.

## Do it by hand

### 1. Install the toolbox

```bash
# root
emerge --ask=n \
  app-portage/gentoolkit \
  app-portage/eix \
  app-portage/portage-utils \
  app-portage/genlop \
  app-portage/mirrorselect
```

These are independent utilities, so install them in one emerge. They pull minimal
dependencies and do not touch your running services or config, which is why the script
installs them unconditionally as part of a normal run.

### 2. Build the eix index

`eix` needs an index before it can search. Generate it once now:

```bash
# root
eix-update
```

This scans the ebuild tree and writes the binary cache `eix` reads
(`/var/cache/eix/portage.eix`). From now on, `eix-sync` keeps it current every time you
sync, so you rarely run `eix-update` by hand again.

## Verify

```bash
# root
equery --version          # gentoolkit present
eix --version             # eix present
qlist -IC | head          # portage-utils: list a few installed packages
genlop --version          # genlop present
eix bash                  # should return results instantly from the index
```

`eix bash` returning matches (rather than "no index" or an empty result) confirms the
index built. `equery belongs /bin/bash` should name `app-shells/bash`, proving
`gentoolkit` can query ownership. If any command is "not found", that package failed to
install; re-run the emerge for it.

## Pitfalls and rollback

- **`eix` says the cache is missing or stale.** You skipped `eix-update`, or the tree
  changed since the last index. Run `eix-update` (or `eix-sync` to sync and reindex in
  one step).
- **`revdep-rebuild` wants to rebuild a lot.** After a big toolchain or library bump
  that is normal; let it run. It only rebuilds what actually links against changed
  libraries.
- **`eclean` is destructive to the cache, not the system.** `eclean distfiles` deletes
  source tarballs; that only means a future rebuild re-downloads them. Use
  `eclean -d distfiles` to be conservative (keep distfiles for installed versions).
- **Rollback.** These are ordinary packages and the script writes no config for this
  step, so there is nothing to revert. If you want them gone, unmerge them:
  ```bash
  # root
  emerge --deselect app-portage/gentoolkit app-portage/eix \
    app-portage/portage-utils app-portage/genlop app-portage/mirrorselect
  emerge --ask --depclean
  ```
  The script's `--rollback` does not touch this step (it uninstalls nothing).

## Script reference

- **Step:** `04` - `step_04_portage_tooling`
- **Flags:** none (runs as part of a default install; nothing to toggle)
- **Managed files:** none. Installs `app-portage/{gentoolkit,eix,portage-utils,genlop,mirrorselect}`
  and builds the `eix` cache at `/var/cache/eix/`.

---
[← Previous: Binary packages (binhost)](04-binary-packages.md) · [Handbook index](README.md) · [Next: Updating @world & cleanup →](06-world-update.md)

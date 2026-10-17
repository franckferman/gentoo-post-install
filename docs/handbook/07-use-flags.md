# USE flags & package.use

> USE flags are how you tell Portage which optional features to compile into your
> packages. This chapter mirrors the script's `step_06_use_flags`: it lays out the
> `/etc/portage/package.use`, `package.accept_keywords`, and `package.license`
> directories and seeds a profile-aware global USE baseline (step 06).

## What the script automates

`step_06_use_flags` creates the three per-package Portage config directories
(`package.use`, `package.accept_keywords`, `package.license`), then writes a single,
conservative global USE baseline into `package.use/10-baseline` as a `*/*` line chosen
from your `--profile` (desktop, server, hardened, minimal, or the default). It does
not touch the `USE=` line in your `make.conf`, and it reminds you that USE changes only
take effect on the next `@world` rebuild. Doing it by hand is the same: make the
directories, drop in a reviewable baseline file, and rebuild.

## Concepts

A **USE flag** is a named build-time switch. When an ebuild offers a flag like `X`,
`vulkan`, or `pulseaudio`, setting it decides whether that optional feature (and its
dependencies) gets compiled in. This is the core of a source-based distribution: you
build only the features you asked for, so the same package is lean on a server and
full-featured on a desktop.

Portage reads USE settings from several places and merges them, with later sources
overriding earlier ones:

- **The profile** (`eselect profile`) sets a sensible default USE for your system type.
- **`USE=` in `/etc/portage/make.conf`** is your *global* override: it applies to every
  package. Good for broad choices (`X wayland dbus`), bad for one-off needs.
- **`/etc/portage/package.use`** is your *per-package* override and takes precedence
  over global USE. This is where surgical changes live (enable `vaapi` only for Mesa,
  disable `systemd` only for one package).

`package.use`, `package.accept_keywords`, and `package.license` can each be a single
*file* or a *directory* of drop-in files. Gentoo has defaulted to the directory form
for years, and the script uses it. A directory lets you keep unrelated changes in
separate, self-documenting files (`00cpu-flags`, `10-baseline`, `20-installkernel`, ...)
instead of one sprawling file, and lets tooling add and remove its own drop-ins
cleanly. Files are read in filename order, which is why the numeric prefixes matter: a
later file can override an earlier one.

- **`package.use`**: per-package USE flags. An entry is an atom followed by flags:
  `media-libs/mesa vulkan vaapi`. The special atom `*/*` means "every package", which
  is how a global baseline is expressed here without editing `make.conf`.
- **`package.accept_keywords`**: lets specific packages come from the testing branch
  (`~amd64`) while the rest of the system stays stable. Empty by default; later
  chapters (GPU, applications) drop files in here only when a package needs it.
- **`package.license`**: accepts licenses that your `ACCEPT_LICENSE` policy would
  otherwise block (firmware blobs, the NVIDIA license, EULAs), per package.

The script writes the baseline to its own `10-baseline` file rather than into
`make.conf` on purpose: your hand-written `USE=` stays untouched and reviewable, and
reverting the baseline is a single `rm`.

## Do it by hand

### 1. Create the three config directories

```bash
# root
mkdir -p /etc/portage/package.use \
         /etc/portage/package.accept_keywords \
         /etc/portage/package.license
```

Why: these are the standard directory-form locations Portage reads. Creating them up
front means every later chapter can drop a file in without first checking whether a
plain file of the same name is in the way (you cannot have both `package.use` the file
and `package.use/` the directory).

### 2. Write a global USE baseline to `package.use/10-baseline`

Pick the line that matches your system type. The script selects it from `--profile`:

```bash
# root - choose ONE, then write it to package.use/10-baseline
# desktop:
cat > /etc/portage/package.use/10-baseline <<'EOF'
# Managed by gentoo-post-install (profile: desktop)
# Review and adjust; remove this file to revert.
*/* X wayland dbus policykit udev alsa pulseaudio pipewire networkmanager -kde
EOF
```

The other profiles use a narrower set:

```text
# server:   */* -X -gtk -gnome -kde -qt5 -qt6 ssl ipv6 threads
# hardened: */* -X -gtk -gnome -kde ssl ipv6
# minimal:  */* -X ssl ipv6
# default:  */* ssl ipv6 threads
```

Why these flags: a leading flag enables a feature for every package, a `-flag` force
disables it. The desktop line turns on the graphical and audio stack (`X wayland dbus`,
`alsa pulseaudio pipewire`) and `networkmanager`, while `-kde` keeps the heavy KDE
dependency out of packages that merely offer it. The server/minimal lines invert that:
`-X -gtk -gnome` strip graphical dependencies from headless boxes, keeping `ssl`,
`ipv6`, and `threads` which almost everything wants. The `*/*` atom is what makes this
*global* without editing `make.conf`.

**Warning:** A global `-flag` (for example `-kde`) force-disables that feature everywhere. If a
package genuinely needs it, you will get a blocked-dependency message at emerge time.
Re-enable it for just that package with a per-package line (step 3) rather than
loosening the global baseline.

### 3. Add per-package overrides when you need them

Per-package lines live in their own drop-in and override the global baseline because
`package.use` wins over `*/*`-style global USE. Use a numeric prefix so ordering is
predictable:

```bash
# root - enable extra Mesa features for just this one package
echo 'media-libs/mesa vulkan vaapi' > /etc/portage/package.use/40-gpu
```

Why a separate file with a higher number: files are read in filename order, so
`40-gpu` is applied after `10-baseline` and can turn a flag back on that the baseline
turned off. Keeping each concern in its own file is also what lets the script (and you)
add or remove one change without rewriting the whole configuration.

### 4. Accept a testing keyword or a license when a package requires it

These two directories start empty. Add to them only when Portage tells you a specific
package is masked by keyword or license:

```bash
# root - pull one package from the ~amd64 testing branch, stable elsewhere
echo 'games-util/steam-launcher ~amd64' > /etc/portage/package.accept_keywords/steam

# root - accept a specific license for a specific package
echo 'x11-drivers/nvidia-drivers NVIDIA-r2' > /etc/portage/package.license/gpi-gpu
```

Why per-package and not global: unmasking `~amd64` system-wide or setting
`ACCEPT_LICENSE="*"` pulls in far more than you intended. Scoping it to the one atom
that needs it keeps the rest of the system on stable, vetted packages. (The GPU and
applications chapters create exactly these kinds of drop-ins for you.)

### 5. Apply the changes with an `@world` rebuild

USE and license changes are build-time: nothing already installed changes until you
rebuild the packages affected by the new flags.

```bash
# root
emerge --ask --update --changed-use --deep --newuse @world
# same thing, short form (what the script prints):
emerge -uUDN @world
```

Why each flag:

- `--update` / `-u`: only rebuild packages that actually need it.
- `--deep` / `-D`: consider the whole dependency tree, not just top-level `@world`
  entries, so a flag change deep in a dependency is picked up.
- `--newuse` / `-N`: rebuild a package when its USE flags changed, including when the
  set of flags the ebuild offers changed.
- `--changed-use` / `-U`: the narrower companion to `--newuse`; it rebuilds on an
  actual enabled/disabled change but ignores purely cosmetic flag-set changes. Using
  both is harmless and matches what the script does.

## Verify

```bash
# root - see the effective global USE after profile + make.conf + package.use merge
emerge --info | grep '^USE='

# see the final USE for one package (what will actually be built)
emerge --pretend --verbose media-libs/mesa      # the [ebuild] line shows flags: +on -off

# confirm Portage reads your directories and what it resolved */* to
portageq envvar USE
```

`emerge --info` prints the merged global `USE=`; your baseline flags should appear in
it. The `emerge -pv <pkg>` line is the authoritative check for per-package work: a flag
you enabled shows as `flagname` (or `+flagname`) and a disabled one as `-flagname`. If
an override is not showing up, check the filename order in the directory.

## Pitfalls and rollback

- **Forgetting the rebuild.** Editing `package.use` changes nothing until you run
  `emerge -uUDN @world`. Already-installed packages keep their old flags.
- **Leaving out `--newuse`.** A plain `emerge -uD @world` will not rebuild a package
  just because you flipped a flag; always include `-N` after a USE change.
- **A global `-flag` that something needs.** You get a blocked dependency. Fix it with
  a per-package line that re-enables the flag, not by weakening the baseline.
- **Typos in an atom.** `media-libs/mesaa vulkan` is silently ignored (no such package)
  or warns on `emerge`; verify with `emerge -pv`.
- **A huge rebuild from one global flag.** Changing `*/*` can schedule hundreds of
  packages. Review the `emerge -pv @world` list before committing to it.
- **Rollback:** remove the baseline drop-in and rebuild. The script's `--rollback` does
  exactly this (it removes `package.use/10-baseline`):

  ```bash
  # root
  rm -f /etc/portage/package.use/10-baseline
  emerge -uUDN @world
  ```

  The empty `package.accept_keywords` and `package.license` directories are left in
  place; that is harmless. Any per-package files you added by hand are yours to remove.

## Script reference

- **Step:** `06` - `step_06_use_flags`
- **Flags:** none of its own; the baseline is selected by `--profile`
  `desktop|server|hardened|minimal|default`.
- **Managed files:** `/etc/portage/package.use/10-baseline` (the `*/*` global baseline),
  and the directories `/etc/portage/package.use`, `/etc/portage/package.accept_keywords`,
  `/etc/portage/package.license` (created if missing).

---
[← Previous: Updating @world & cleanup](06-world-update.md) · [Handbook index](README.md) · [Next: Kernel, microcode & Secure Boot →](08-kernel-microcode.md)

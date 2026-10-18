# Applications

> Install everyday applications by friendly name (`firefox`, `vlc`, ...) or by raw
> Portage atom, with per-package licenses, auto-enabled overlays, ready-made profiles,
> and native Steam. Mirrors the script's step 19 (`--apps`, `--apps-profile`, `--steam`).

## What the script automates

`step_19_apps` turns a list of friendly names (and/or raw `category/package` atoms) into
a single `emerge` run. For each name it looks up the real atom, auto-enables any overlay
that atom lives in, and records any non-free license the package needs. It can expand a
ready-made profile (`daily`, `dev`, `media`, `gaming`), and it installs native Steam via
the `steam-overlay`. Doing it by hand is the same sequence: resolve the name, enable the
overlay, accept the license, `emerge`.

## Concepts

Portage installs packages by their fully-qualified **atom** (`category/package`, for
example `www-client/firefox-bin`). The script keeps a small table that maps friendly
names to atoms so you do not have to memorize categories, but anything containing a `/`
is treated as a raw atom and passed straight through. An unknown name (no slash, not in
the table) is skipped with a warning rather than guessed at.

Three things can stand between you and a successful install:

- **Licenses.** Some packages (Google Chrome, Spotify, Steam) ship under licenses your
  `ACCEPT_LICENSE` policy does not accept by default. Portage refuses to merge them until
  you opt in, per package, with a `package.license` entry. See
  [Tuning make.conf](03-make-conf.md) for the global policy.
- **Overlays.** A few apps are not in the official `::gentoo` repository and live in a
  community overlay (for example Obsidian in `r7l`). The overlay must be enabled and
  synced first. See [Overlays / repositories](20-overlays.md).
- **Prebuilt vs source.** The table prefers `-bin` atoms (`firefox-bin`,
  `libreoffice-bin`, `thunderbird-bin`, `signal-desktop-bin`) where upstream ships
  official binaries, so you do not spend hours compiling a browser or an office suite.

The friendly-name table (from `_app_spec`):

| Name | Atom | Overlay | License |
| --- | --- | --- | --- |
| `firefox` | `www-client/firefox-bin` | | |
| `chromium` | `www-client/chromium` | | |
| `chrome` | `www-client/google-chrome` | | `google-chrome` |
| `vlc` | `media-video/vlc` | | |
| `mpv` | `media-video/mpv` | | |
| `obs` | `media-video/obs-studio` | | |
| `gimp` | `media-gfx/gimp` | | |
| `inkscape` | `media-gfx/inkscape` | | |
| `libreoffice` | `app-office/libreoffice-bin` | | |
| `thunderbird` | `mail-client/thunderbird-bin` | | |
| `keepassxc` | `app-admin/keepassxc` | | |
| `spotify` | `media-sound/spotify` | | `spotify` |
| `obsidian` | `app-text/obsidian` | `r7l` | |
| `discord` | `net-im/discord` | | |
| `signal` | `net-im/signal-desktop-bin` | | |

The profiles (from `_apps_profile_list`) are just shorthand for a set of names:

- `daily` → `firefox vlc keepassxc`
- `dev` → `firefox keepassxc obsidian`
- `media` → `vlc mpv obs gimp`
- `gaming` → `discord steam` (where `steam` routes to the native Steam installer)

A profile and an explicit `--apps` list combine: the profile names are installed
alongside whatever you pass.

## Do it by hand

### 1. Resolve names to atoms

Decide what you want and translate each friendly name to its atom using the table above.
For example `--apps firefox,obsidian,chrome` means:

```text
firefox   -> www-client/firefox-bin        (no overlay, no license)
obsidian  -> app-text/obsidian             (overlay: r7l)
chrome    -> www-client/google-chrome      (license: google-chrome)
```

A raw atom needs no lookup. These are equivalent, and the second form lets you install
anything, not just the names in the table:

```bash
# root
# friendly name:
#   --apps keepassxc
# raw atom (passed through untouched):
#   --apps app-admin/keepassxc
```

### 2. Enable any overlay the apps need

Obsidian lives in the `r7l` overlay, so enable and sync it before emerging. The script
does this automatically (deduplicated) via `eselect repository`:

```bash
# root
eselect repository enable r7l
emaint sync -r r7l
```

Why: Portage can only see a package after its repository is enabled and synced. Skipping
this gives you a "no ebuilds to satisfy" error. See [Overlays](20-overlays.md) for the
mechanics.

### 3. Accept per-package licenses

Chrome and Spotify need an explicit license opt-in. Write a `package.license` drop-in
(the script writes `package.license/gpi-apps`), one `atom license` per line:

```bash
# root
mkdir -p /etc/portage/package.license
cat > /etc/portage/package.license/gpi-apps <<'EOF'
# Managed by gentoo-post-install
www-client/google-chrome google-chrome
media-sound/spotify spotify
EOF
```

Why a drop-in rather than loosening the global `ACCEPT_LICENSE`: it keeps the exception
narrow (this package, this license) and documents exactly which proprietary software you
accepted and why.

### 4. Install

Merge all the atoms in one run. The script uses `--noreplace` so already-installed apps
are left alone (idempotent), and a non-interactive `--ask=n`:

```bash
# root
emerge --ask=n --noreplace --verbose www-client/firefox-bin app-text/obsidian \
  www-client/google-chrome
```

`--noreplace` means "install it if it is missing, otherwise do nothing", so re-running
the command is safe. If a package fails (usually a missing keyword or license), the rest
still install.

### 5. Native Steam (optional)

**Warning:** Native Steam pulls a large **32-bit (`abi_x86_32`)** dependency tree. It **requires a
multilib profile**; on a `no-multilib` profile it cannot work, and the first build is
long.

Check your profile and switch if needed:

```bash
# root
eselect profile list | grep -v no-multilib     # pick a multilib profile
# eselect profile set <n>
# emerge -e @world                              # rebuild for the new ABI, then continue
```

Then enable the overlay, accept the license, allow the overlay's keywords, and install.
This mirrors `_install_steam_native`:

```bash
# root
eselect repository enable steam-overlay
emaint sync -r steam-overlay

# Steam's EULA:
cat > /etc/portage/package.license/steam <<'EOF'
# Managed by gentoo-post-install
games-util/steam-launcher ValveSteamLicense
EOF

# Allow the overlay and its two unkeyworded helpers:
cat > /etc/portage/package.accept_keywords/steam <<'EOF'
# Managed by gentoo-post-install
*/*::steam-overlay
games-util/game-device-udev-rules
sys-libs/libudev-compat
EOF

# autounmask writes the abi_x86_32 USE deps as it goes:
emerge --ask=n --autounmask-write=y --autounmask-license=y --autounmask-continue=y \
  games-util/steam-launcher
```

If `emerge` stops with changes to review, run `dispatch-conf` to accept the written
USE/keyword files, then re-run the last command. Launch `steam` once afterward to finish
its first-run bootstrap.

## Verify

```bash
# root
qlist -I www-client/firefox-bin app-text/obsidian   # installed versions, or empty if not
equery list 'www-client/*' 'app-text/obsidian'      # same, via gentoolkit
```

`qlist -I <atom>` prints the installed version of each atom (nothing if it is not
installed). For Steam, `command -v steam` should resolve and
`emerge -pv games-util/steam-launcher` should show it as already merged with `abi_x86_32`
USE deps pulled in.

## Pitfalls and rollback

- **Unknown name skipped:** a friendly name with no slash that is not in the table is
  skipped with a warning. Pass the raw `category/atom` to force it.
- **"no ebuilds to satisfy" for an overlay app:** the overlay was not enabled/synced.
  Redo step 2.
- **License refusal:** Portage prints the required license token; add `atom token` to
  `package.license/gpi-apps`.
- **Steam on no-multilib:** switch profiles and `emerge -e @world` first; there is no
  way around the 32-bit requirement.
- **Rollback:** applications are ordinary packages. Remove them and the drop-ins:
  ```bash
  # root
  emerge --ask=n --deselect www-client/google-chrome media-sound/spotify
  emerge --ask=n --depclean
  rm -f /etc/portage/package.license/gpi-apps /etc/portage/package.license/steam \
        /etc/portage/package.accept_keywords/steam
  ```
  The script does not auto-uninstall apps on `--rollback`; remove them by hand as above.

## Script reference

- **Step:** `19` - `step_19_apps` (+ `_app_spec`, `_apps_profile_list`,
  `_install_steam_native`)
- **Flags:** `--apps <list>` (names and/or raw atoms, comma/space separated),
  `--apps-profile daily|dev|media|gaming`, `--steam`; `--list-apps` prints the table
- **Managed files:** `/etc/portage/package.license/gpi-apps`,
  `/etc/portage/package.license/steam`, `/etc/portage/package.accept_keywords/steam`,
  plus overlay enablement under `/etc/portage/repos.conf/`

---
[← Previous: Overlays / repositories](20-overlays.md) · [Handbook index](README.md) · [Next: Desktop environment & display manager →](22-desktop-environment.md)

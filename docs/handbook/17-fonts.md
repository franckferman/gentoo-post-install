# Fonts

> Install Nerd Fonts into your login user's font directory so Powerlevel10k, terminal
> icons, and programming ligatures render correctly, then refresh the font cache.
> Mirrors the script's step 16 (`--fonts`).

## What the script automates

`step_16_fonts` installs the font prerequisites (`fontconfig`, `unzip`, `curl`), then,
**as your real login user**, downloads each Nerd Font release zip, unpacks it into that
user's per-user font directory, and rebuilds the font cache with `fc-cache`. The default
set is `FiraCode`, `JetBrainsMono`, and `Hack`; `--nerd-fonts` replaces that list.

## Concepts

A font is only usable once fontconfig can find it and an application is told to use it.

- **Nerd Fonts** are popular monospace fonts (FiraCode, JetBrains Mono, Hack, ...)
  patched to include thousands of extra glyphs: powerline separators, file-type icons,
  and symbols. Powerlevel10k and most "fancy" terminal prompts draw with these glyphs,
  which is why this chapter pairs with [Shell & terminal](16-shell-terminal.md).
- **fontconfig** is the library that indexes fonts and answers "what font files exist?".
  `fc-list` queries the index; `fc-cache` rebuilds it after you add files.
- **Per-user vs system fonts.** Fonts in `~/.local/share/fonts` belong to one user and
  need no root. System-wide fonts live under `/usr/share/fonts` and need root. The
  script installs **per user**, into `~/.local/share/fonts/<FontName>/`, because the
  shell setup it complements is also per user. This is the deliberate reason the step
  runs as the target user, not root.
- **These come as release zips, not ebuilds.** Gentoo does package some Nerd Fonts, but
  the script pulls the upstream release zips directly so the exact set and versions are
  predictable. You download, unzip, and refresh the cache yourself.

## Do it by hand

Run the `emerge` as root; run the download, unzip, and cache steps **as your login
user** (shown with `su - youruser -c '...'` from root, which is what the script's
`user_do` does). Replace `youruser` with your username.

### 1. Install the prerequisites

```bash
# root
emerge --ask=n media-libs/fontconfig app-arch/unzip net-misc/curl
```

`fontconfig` provides `fc-cache`/`fc-list`, `unzip` extracts the release archives, and
`curl` downloads them.

### 2. Download and unpack each font into the user's font dir

For each font name, create a dedicated subdirectory, download the matching
`latest/download/<Name>.zip`, and unzip it there:

```bash
# as youruser
for font in FiraCode JetBrainsMono Hack; do
  d="$HOME/.local/share/fonts/$font"
  mkdir -p "$d"
  t="$(mktemp)"
  curl -fsSL \
    "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$font.zip" \
    -o "$t" && unzip -oq "$t" -d "$d" && rm -f "$t"
done
```

What each piece does:

- `~/.local/share/fonts/<font>/` is the standard per-user font location fontconfig
  scans; one subdirectory per font keeps them tidy and easy to remove.
- `curl -fsSL`: `-f` fails on HTTP errors (so a 404 does not leave a broken file), `-s`
  stays quiet, `-S` still shows real errors, and `-L` follows the redirect that
  `latest/download` issues.
- `unzip -oq`: `-o` overwrites on re-run (idempotent), `-q` is quiet.
- The `mktemp` + `rm` pair downloads to a scratch file and cleans it up, so no stray zip
  is left behind.

To install a different set, just change the names in the loop. That is exactly what the
script's `--nerd-fonts FiraCode,CascadiaCode` does (it splits the comma list into the
loop). The names must match the upstream release asset names.

### 3. Refresh the font cache

```bash
# as youruser
fc-cache -f
```

`-f` forces a rebuild of fontconfig's index so the just-added fonts are visible to
applications immediately, without waiting for the cache to expire.

## Verify

```bash
# as youruser
fc-list | grep -iE 'firacode|jetbrains|hack'   # lists the installed faces
ls ~/.local/share/fonts                        # one dir per font you installed
```

Seeing the font families listed by `fc-list` means fontconfig has indexed them. The
real test is visual: set your terminal emulator's font to one of them (for example
"FiraCode Nerd Font" or "JetBrainsMono Nerd Font"), reopen the terminal, and the
Powerlevel10k prompt icons from the previous chapter should now render as crisp glyphs
instead of empty boxes.

## Pitfalls and rollback

- **Fonts installed but still boxes in the prompt** → the font exists but your terminal
  is not using it. Pick the Nerd Font variant in the terminal's settings. fontconfig
  having the font does not force any app to select it.
- **`curl` 404 / zip is empty** → the font name does not match an upstream release
  asset. Check the names against the Nerd Fonts releases page; names are case-sensitive
  (`JetBrainsMono`, not `jetbrainsmono`).
- **Installed as root by mistake** → the files land in `/root/.local/share/fonts` and
  your user never sees them. Remove them there and redo as the user. This is why the
  step runs as the target user.
- **Rollback:** this step is **not** touched by the script's `--rollback`. Remove the
  fonts by hand and refresh the cache:
  ```bash
  # as youruser
  rm -rf ~/.local/share/fonts/FiraCode ~/.local/share/fonts/JetBrainsMono \
         ~/.local/share/fonts/Hack
  fc-cache -f
  ```

## Script reference

- **Step:** `16` - `step_16_fonts` (helpers `_resolve_target_user`, `user_do`)
- **Flags:** `--fonts`, `--no-fonts`, `--nerd-fonts <comma-list>` (default
  `FiraCode,JetBrainsMono,Hack`)
- **Managed files (in the target user's home):**
  `~/.local/share/fonts/<FontName>/` per installed font, plus the fontconfig cache
  refreshed by `fc-cache`.

---
[← Previous: Shell & terminal](16-shell-terminal.md) · [Handbook index](README.md) · [Next: Desktop stack →](18-desktop-stack.md)

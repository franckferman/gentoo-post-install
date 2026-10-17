# Desktop environment & display manager

> Install a full desktop (KDE, GNOME, Sway, Hyprland, or XFCE) and a display manager
> (sddm, gdm, lightdm, greetd), and enable the graphical login the right way on OpenRC
> and systemd. Mirrors the script's step 20 (`--de`, `--dm`).

## What the script automates

`step_20_desktop_environment` installs the meta-package for your chosen desktop, pulls
in the session/seat prerequisites (`dbus`, plus `elogind` on OpenRC), installs a display
manager (either one you name or a sensible default for that desktop), and enables the DM
service to start at boot. Doing it by hand is the same four moves: seat prerequisites,
desktop meta-package, display-manager package, enable the service.

## Concepts

A "desktop environment" on Gentoo is a **meta-package**: an ebuild that depends on all
the components (compositor/window manager, panels, settings, utilities) so one atom
drags in a working set. A **display manager (DM)** is the graphical login screen that
starts your session.

The desktop meta-packages (from `_de_package`):

| `--de` | Meta-package | Type |
| --- | --- | --- |
| `kde` | `kde-plasma/plasma-meta` | Wayland/X11 |
| `gnome` | `gnome-base/gnome` | Wayland |
| `sway` | `gui-wm/sway` | Wayland (wlroots) |
| `hyprland` | `gui-wm/hyprland` | Wayland (wlroots) |
| `xfce` | `xfce-base/xfce4-meta` | X11 |

The display managers (from `_dm_package`), and the default each desktop picks when you
pass `--dm auto` or omit `--dm` (from `_default_dm_for_de`):

| `--dm` | Package(s) | Default for |
| --- | --- | --- |
| `sddm` | `x11-misc/sddm` | `kde` |
| `gdm` | `gnome-base/gdm` | `gnome` |
| `lightdm` | `x11-misc/lightdm` + `x11-misc/lightdm-gtk-greeter` | `xfce` |
| `greetd` | `gui-libs/greetd` + `gui-apps/tuigreet` | `sway`, `hyprland` |
| `none` | (none) | start from a TTY |

**Seat management** matters on Wayland: a compositor needs a login/seat manager
(`systemd-logind` on systemd, `elogind` on OpenRC) to get access to the GPU and input
devices. On OpenRC the script installs `sys-auth/elogind` and adds it to the `boot`
runlevel; on systemd this is built in.

**Enabling the DM differs by init system.** systemd enables a specific
`<dm>.service`. OpenRC uses a generic `display-manager` service that reads which DM to
launch from the `DISPLAYMANAGER` variable in `/etc/conf.d/display-manager`. `greetd` is
the exception: it ships its own OpenRC service and is enabled directly.

## Do it by hand

The examples use KDE + SDDM; substitute your atoms from the tables above.

### 1. Install seat/session prerequisites

```bash
# root
emerge --ask=n --noreplace sys-apps/dbus
```

On **OpenRC** also install and enable `elogind` (systemd users skip this; `logind` is
built in):

```bash
# root  (OpenRC only)
emerge --ask=n --noreplace sys-auth/elogind
rc-update add elogind boot
```

`elogind` in the `boot` runlevel provides seat/session tracking before your graphical
services start.

### 2. Install the desktop meta-package

```bash
# root
emerge --ask=n --noreplace kde-plasma/plasma-meta
```

This is the long build. If it fails complaining about keywords or a profile, the desktop
usually needs a matching profile. For KDE or GNOME on OpenRC in particular, the right
profile pulls in the correct defaults:

```bash
# root
eselect profile list | grep -E 'kde(/|$)'      # or gnome, plasma, ...
# eselect profile set <n>    # then re-emerge
```

### 3. Install the display manager

```bash
# root
emerge --ask=n --noreplace x11-misc/sddm
```

For `lightdm` install the greeter too (`x11-misc/lightdm-gtk-greeter`); for `greetd`
install `gui-apps/tuigreet` alongside `gui-libs/greetd`.

If you prefer no DM (`--dm none`), skip this and start the desktop from a TTY instead,
for example `dbus-run-session sway`, or via `~/.xinitrc` with `startx` for X11 desktops.

### 4. Enable the DM at boot

On **systemd**, enable the service named after the DM:

```bash
# root  (systemd)
systemctl enable sddm.service
```

On **OpenRC**, use the generic `display-manager` service and tell it which DM to run.
First install the init glue, then set `DISPLAYMANAGER` and add the service:

```bash
# root  (OpenRC)
emerge --ask=n --noreplace gui-libs/display-manager-init

# Set DISPLAYMANAGER="sddm" in /etc/conf.d/display-manager
# (replace an existing line, or append one):
sed -i -E 's|^[[:space:]]*DISPLAYMANAGER=.*|DISPLAYMANAGER="sddm"|' \
  /etc/conf.d/display-manager \
  || printf 'DISPLAYMANAGER="sddm"\n' >> /etc/conf.d/display-manager

rc-update add display-manager default
```

`greetd` on OpenRC ships its own service, so it is the one case that does not use
`display-manager`:

```bash
# root  (OpenRC, greetd only)
rc-update add greetd default
```

## Verify

```bash
# systemd
systemctl is-enabled sddm.service         # -> enabled

# OpenRC
grep DISPLAYMANAGER /etc/conf.d/display-manager   # -> DISPLAYMANAGER="sddm"
rc-update show | grep -E 'display-manager|greetd'
rc-update show boot | grep elogind                # seat manager enabled
```

Reboot (or `rc-service display-manager start` / `systemctl start sddm`) and you should
land on a graphical login. After logging in, confirm the session type with
`echo "$XDG_SESSION_TYPE"` (`wayland` or `x11`).

## Pitfalls and rollback

- **Black screen / DM will not start:** on OpenRC this is almost always a missing
  `elogind` in `boot`, or `DISPLAYMANAGER` unset. Check both. Have a TTY
  (Ctrl+Alt+F2) ready before you reboot.
- **Wayland compositor exits immediately:** seat management is missing. Ensure
  `elogind` (OpenRC) or `logind` (systemd) is active.
- **KDE/GNOME keyword or profile errors:** switch to the matching Gentoo profile
  (step 2) and re-emerge.
- **Wrong default DM:** pass `--dm` explicitly instead of relying on the per-desktop
  default.
- **Rollback:** disable the service and (optionally) remove the packages:
  ```bash
  # systemd
  systemctl disable sddm.service
  # OpenRC
  rc-update del display-manager default    # or: rc-update del greetd default
  # then, to remove the software:
  emerge --ask=n --deselect kde-plasma/plasma-meta x11-misc/sddm
  emerge --ask=n --depclean
  ```
  Keep at least one way in (a TTY login or SSH) before removing a DM.

## Script reference

- **Step:** `20` - `step_20_desktop_environment` (+ `_de_package`, `_dm_package`,
  `_default_dm_for_de`, `_enable_display_manager`)
- **Flags:** `--de kde|gnome|sway|hyprland|xfce|none`,
  `--dm sddm|gdm|lightdm|greetd|none|auto`
- **Managed files:** `/etc/conf.d/display-manager` (`DISPLAYMANAGER=`, OpenRC only);
  services enabled via `systemctl` (systemd) or `rc-update` (OpenRC). Also installs
  `sys-apps/dbus` and, on OpenRC, `sys-auth/elogind` + `gui-libs/display-manager-init`.

---
[← Previous: Applications](21-applications.md) · [Handbook index](README.md) · [Next: Attack-surface minimization →](23-attack-surface.md)

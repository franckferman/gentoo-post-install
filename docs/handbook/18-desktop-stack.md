# Desktop stack

> The foundation a graphical session sits on: the `VIDEO_CARDS` and `INPUT_DEVICES`
> tokens, D-Bus (plus elogind on OpenRC), a display server (Xorg or Wayland), PipeWire
> audio, and NetworkManager. Mirrors the script's step 17 (`--desktop`).

## What the script automates

`step_17_desktop` autodetects your GPU with `lspci` and sets `VIDEO_CARDS` in
`make.conf` (unless you override it), sets `INPUT_DEVICES="libinput"`, installs D-Bus
(and, on OpenRC, elogind) and enables them, installs Xorg and/or notes Wayland, installs
PipeWire plus WirePlumber for audio, and installs and enables NetworkManager. It is the
plumbing layer; the actual GPU driver packages are the next chapter
([GPU drivers](19-gpu-drivers.md)), and the desktop environment is
[Desktop environment](22-desktop-environment.md).

## Concepts

A graphical login needs several independent pieces agreed on ahead of time:

- **`VIDEO_CARDS`** is a Portage USE-expand token in `make.conf` that tells Mesa and the
  X/Wayland drivers which GPUs to build support for (`intel`, `amdgpu radeonsi`,
  `nouveau`, or `nvidia`). Setting it here only records the choice; the driver packages
  and the `@world` rebuild to apply it are covered in chapter 19.
- **`INPUT_DEVICES="libinput"`** selects the modern unified input driver that handles
  mice, touchpads, and keyboards for both Xorg and Wayland. It replaced the old
  per-device `evdev`/`synaptics` drivers.
- **D-Bus** is the message bus desktop software uses to talk to itself and to system
  services. Almost nothing graphical works without it.
- **A session/login manager** tracks who is logged in on which seat and grants access to
  devices. On **systemd** this is `systemd-logind`, built in and always present. On
  **OpenRC** there is no built-in equivalent, so you install **elogind**, a standalone
  logind extracted from systemd.
- **Display server:** **Xorg** (`x11-base/xorg-server`) is the mature X11 server.
  **Wayland** is the newer protocol where the compositor *is* the display server, so you
  do not install a separate "wayland-server"; you install a compositor (sway, Hyprland,
  GNOME, KDE) which the script leaves to you.
- **PipeWire + WirePlumber:** PipeWire is the modern audio (and video) server;
  WirePlumber is its session/policy manager. Together they replace PulseAudio and JACK.
- **NetworkManager** manages wired and wireless connections with an interactive,
  desktop-friendly interface.

## Do it by hand

All steps are privileged (run as root).

### 1. Set `VIDEO_CARDS` (autodetect or override)

First detect the vendor. The script runs `lspci` and matches on word boundaries so a
bare `ati` does not match "VGA comp**ati**ble controller":

```bash
# root
emerge --ask=n sys-apps/pciutils           # provides lspci, if missing
lspci | grep -iE 'vga|3d|display'
```

Map the output to a token: Intel → `intel`, AMD/ATI/Radeon → `amdgpu radeonsi`, NVIDIA
→ `nouveau` (the FOSS default; the proprietary `nvidia` token is chosen in chapter 19).
Then set it in `make.conf` (this is the script's `make_conf_set`, which backs up
`make.conf` once to `make.conf.gpi.bak` before editing):

```bash
# root - example for an Intel iGPU:
grep -q '^VIDEO_CARDS=' /etc/portage/make.conf \
  && sed -i 's/^VIDEO_CARDS=.*/VIDEO_CARDS="intel"/' /etc/portage/make.conf \
  || echo 'VIDEO_CARDS="intel"' >> /etc/portage/make.conf
```

The script's `--video-cards "amdgpu radeonsi"` sets this value directly and skips
autodetection, which is what you want in a VM or when `lspci` cannot see the card.

### 2. Set `INPUT_DEVICES`

```bash
# root
grep -q '^INPUT_DEVICES=' /etc/portage/make.conf \
  && sed -i 's/^INPUT_DEVICES=.*/INPUT_DEVICES="libinput"/' /etc/portage/make.conf \
  || echo 'INPUT_DEVICES="libinput"' >> /etc/portage/make.conf
```

One token, `libinput`, covers keyboard, mouse, and touchpad for both display servers.

### 3. Install D-Bus, and elogind on OpenRC

```bash
# root
emerge --ask=n sys-apps/dbus
```

On **OpenRC**, also install elogind and enable both services. elogind goes in the
`boot` runlevel so a session is ready early:

```bash
# root - OpenRC only
emerge --ask=n sys-auth/elogind
rc-update add elogind boot
rc-service elogind start
rc-update add dbus default
rc-service dbus start
```

On **systemd**, `systemd-logind` is built in, and D-Bus is socket-activated, so there is
nothing to install beyond `dbus` and nothing to enable by hand for logind:

```bash
# root - systemd only
systemctl enable --now dbus
```

### 4. Install a display server

For Xorg (`--display x11`, the default, or `both`):

```bash
# root
emerge --ask=n x11-base/xorg-server
```

For Wayland (`--display wayland` or `both`), there is no standalone server to install:

```text
Install a compositor of your choice separately:
  gui-wm/sway, gui-wm/hyprland, or a full desktop (GNOME/KDE) that bundles one.
```

The script deliberately does not pick a compositor for you; it only prints this note.

### 5. Install PipeWire audio

Skip this with the script's `--no-audio`.

```bash
# root
emerge --ask=n media-video/pipewire media-video/wireplumber
```

PipeWire runs **per user**, not as a system service, so enable it inside your session:

```bash
# as youruser, systemd:
systemctl --user enable --now pipewire wireplumber
# OpenRC: start them from your session/compositor autostart instead.
```

### 6. Install NetworkManager

Skip this with the script's `--no-nm` (for example if you already use
`netifrc`/`systemd-networkd`).

**Warning:** Switching network managers can drop your current connection. If you are on SSH over
the very link you are about to hand to NetworkManager, have console access ready.

```bash
# root - systemd:
emerge --ask=n net-misc/networkmanager
systemctl enable --now NetworkManager
# root - OpenRC:
emerge --ask=n net-misc/networkmanager
rc-update add NetworkManager default
rc-service NetworkManager start
```

### 7. Rebuild for the new `VIDEO_CARDS`

Changing `VIDEO_CARDS` means the graphics packages must be rebuilt to pick up the
drivers. Do this after you install the actual driver stack in chapter 19:

```bash
# root
emerge --ask=n --update --deep --newuse @world
```

## Verify

```bash
# the tokens are recorded:
grep -E '^(VIDEO_CARDS|INPUT_DEVICES)=' /etc/portage/make.conf
# session services are up (pick your init):
rc-service dbus status; rc-service elogind status      # OpenRC
systemctl status dbus; loginctl                        # systemd
# network manager is managing links:
nmcli general status
```

`loginctl` listing your seat/session (systemd) or `rc-service elogind status` showing
`started` (OpenRC) confirms the session layer is live. `nmcli general status` showing
`connected` means NetworkManager owns the link. Audio is best checked inside a session
with `wpctl status` (WirePlumber).

## Pitfalls and rollback

- **No GPU detected** → in a VM or with an exotic card, `lspci` may match nothing. Set
  the token yourself with `--video-cards` or by editing `make.conf`.
- **OpenRC desktop with no elogind** → seat/device permissions break and the session
  manager cannot grant access. Make sure `elogind` is installed and in the `boot`
  runlevel.
- **Wayland "installed" but nothing launches** → you still need a compositor; Wayland is
  a protocol, not a package you start.
- **PipeWire silent** → it is a per-user service; enabling it as root (system-wide) does
  nothing for your session. Enable it as your user.
- **Rollback:** the script's `--rollback` restores `make.conf` from `make.conf.gpi.bak`,
  which reverts the `VIDEO_CARDS` and `INPUT_DEVICES` lines. It does **not** uninstall
  dbus/elogind/Xorg/PipeWire/NetworkManager or disable their services. To undo those by
  hand:
  ```bash
  # root - OpenRC example
  rc-service NetworkManager stop; rc-update del NetworkManager default
  emerge --ask=n --depclean net-misc/networkmanager   # only if nothing else needs it
  ```

## Script reference

- **Step:** `17` - `step_17_desktop` (+ `_detect_video_cards`)
- **Flags:** `--desktop`, `--display x11|wayland|both`, `--no-audio`, `--no-nm`,
  `--video-cards "<value>"`
- **Managed files:** `/etc/portage/make.conf` (`VIDEO_CARDS`, `INPUT_DEVICES`; backed up
  once to `make.conf.gpi.bak`). Services enabled: `dbus`, `elogind` (OpenRC),
  `NetworkManager`.

---
[← Previous: Fonts](17-fonts.md) · [Handbook index](README.md) · [Next: GPU drivers →](19-gpu-drivers.md)

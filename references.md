# References

Every Gentoo-specific decision in `gentoo-post-install.sh`, with the wiki/handbook
page it is based on. Consulted 2026-09; re-check against current pages before relying
on any value - Gentoo moves.

## Portage tuning (`make.conf`)
- **MAKEOPTS** `-j` = min(cores, RAM/2 GB), `-l` slightly above core count -
  [MAKEOPTS](https://wiki.gentoo.org/wiki/MAKEOPTS)
- **CPU_FLAGS_X86** computed with `app-portage/cpuid2cpuflags`, written to
  `package.use` - [CPU_FLAGS_X86](https://wiki.gentoo.org/wiki/CPU_FLAGS_X86)
- **USE flags** set per-package (incl. the `*/*` wildcard) is aligned with the wiki's
  "prefer `package.use` over `make.conf`" guidance - [USE flag](https://wiki.gentoo.org/wiki/USE_flag)
- **ACCEPT_LICENSE**: default `@FREE`; desktop uses `@FREE @BINARY-REDISTRIBUTABLE`
  (firmware), not a blanket `*` - [ACCEPT_LICENSE](https://wiki.gentoo.org/wiki/ACCEPT_LICENSE)

## Binary package host
- sync-uri `https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64/`
  (does **not** vary by profile or init system), `FEATURES="getbinpkg
  binpkg-request-signature"`, `verify-signature = true`, trust via `getuto`
  (Portage runs it automatically) -
  [Binary Host Quickstart](https://wiki.gentoo.org/wiki/Gentoo_Binary_Host_Quickstart) ·
  [Binary package guide](https://wiki.gentoo.org/wiki/Binary_package_guide)

## Distribution kernel
- `sys-kernel/gentoo-kernel-bin` + `sys-kernel/linux-firmware`; the initramfs +
  bootloader wiring comes from `sys-kernel/installkernel` USE flags (`dracut`,
  `grub` / `systemd-boot`, `systemd`) which must be set **before** it is built -
  [Installkernel](https://wiki.gentoo.org/wiki/Installkernel) ·
  [Distribution Kernel](https://wiki.gentoo.org/wiki/Distribution_Kernel) ·
  [Dracut](https://wiki.gentoo.org/wiki/Dracut)

## Hardening
- **Toolchain** (SSP `-fstack-protector-strong`, PIE, RELRO+BIND_NOW,
  `_FORTIFY_SOURCE=2`) is **on by default in 23.0 profiles** - it is *not* a USE
  flag. A hardened *profile* is selected with `eselect profile`, which triggers a
  full `emerge -e @world` - [Hardened/Toolchain](https://wiki.gentoo.org/wiki/Hardened/Toolchain) ·
  [Project:Hardened](https://wiki.gentoo.org/wiki/Project:Hardened)
- **hardened_malloc** is opt-in: `sys-libs/hardened_malloc` -
  [Hardened malloc](https://wiki.gentoo.org/wiki/Hardened_malloc)
- **nftables** persistence: OpenRC saves to `/var/lib/nftables/rules-save` via
  `rc-service nftables save` (`/etc/conf.d/nftables`, `SAVE_ON_STOP`); on systemd,
  `nftables-store` / `nftables-load` may be used - [Nftables](https://wiki.gentoo.org/wiki/Nftables)
- **sysctl** loaded from `/etc/sysctl.d/` (OpenRC via the `sysctl` service in the
  `boot` runlevel) - [Sysctl](https://wiki.gentoo.org/wiki/Sysctl) ·
  [Security Handbook](https://wiki.gentoo.org/wiki/Security_Handbook)

## Desktop / audio
- **PipeWire**: keep the `pulseaudio` USE flag enabled (libpulse compat layer);
  do **not** also run `media-sound/pulseaudio-daemon`; WirePlumber for session
  management - [PipeWire](https://wiki.gentoo.org/wiki/PipeWire)
- **VIDEO_CARDS** autodetected from `lspci` (intel / amdgpu+radeonsi / nouveau) -
  [Xorg/Guide](https://wiki.gentoo.org/wiki/Xorg/Guide)

## Desktop environments & display managers
- **KDE Plasma** `kde-plasma/plasma-meta` (+ `kde-apps/kde-apps-meta`); profile
  `desktop/plasma[/systemd]`; needs elogind (OpenRC) / systemd; SDDM is the default DM -
  [KDE](https://wiki.gentoo.org/wiki/KDE)
- **GNOME** `gnome-base/gnome` (or `-light`); profile `desktop/gnome[/systemd]`; GDM
  needs elogind on OpenRC - [GNOME/Guide](https://wiki.gentoo.org/wiki/GNOME/Guide)
- **Sway** `gui-wm/sway`, **Hyprland** `gui-wm/hyprland`: Wayland; need a seat manager
  (`sys-auth/elogind` in the `boot` runlevel, or `sys-auth/seatd`) - [Sway](https://wiki.gentoo.org/wiki/Sway)
- **XFCE** `xfce-base/xfce4-meta`.
- **Display managers**: SDDM `x11-misc/sddm`, GDM `gnome-base/gdm`, LightDM
  `x11-misc/lightdm` (+ greeter), greetd `gui-libs/greetd` (+ `gui-apps/tuigreet`).
  OpenRC uses the generic **display-manager** service (`gui-libs/display-manager-init`
  + `DISPLAYMANAGER=` in `/etc/conf.d/display-manager` + `rc-update add display-manager
  default`); greetd ships its own service. systemd: `systemctl enable <dm>.service`. -
  [Display manager](https://wiki.gentoo.org/wiki/Display_manager)

## Overlays / repositories
- Native overlays via **`app-eselect/eselect-repository`** (layman is deprecated):
  `eselect repository enable <name>` (official list), `eselect repository add <name>
  git <url>` (custom, needs `dev-vcs/git`), sync with `emaint sync -r <name>`; config
  lands in `/etc/portage/repos.conf/`. -
  [Eselect/Repository](https://wiki.gentoo.org/wiki/Eselect/Repository) ·
  [Overlay](https://wiki.gentoo.org/wiki/Overlay). Applications: in-tree atoms are preferred; Obsidian is app-text/obsidian via the **r7l** overlay; discord (net-im/discord), signal (net-im/signal-desktop-bin) and spotify (media-sound/spotify) are in the official ::gentoo tree - no overlay needed.

## Steam (native)
- `games-util/steam-launcher` from the **steam-overlay** (not in ::gentoo); requires a
  **multilib** profile, `package.license` `ValveSteamLicense`, `package.accept_keywords`
  for the overlay, and `abi_x86_32` deps (autounmask writes them). -
  [Steam](https://wiki.gentoo.org/wiki/Steam)

## Microcode / mirrors / config merge
- **Intel microcode** `sys-firmware/intel-microcode` with USE `initramfs split-ucode`
  and `MICROCODE_SIGNATURES="-S"` (current CPU); **AMD** microcode ships in
  `sys-kernel/linux-firmware`. -
  [Intel microcode](https://wiki.gentoo.org/wiki/Intel_microcode) ·
  [AMD microcode](https://wiki.gentoo.org/wiki/AMD_microcode)
- **INPUT_DEVICES**: `libinput` is the modern default for the desktop stack.
- **Fastest mirrors**: `app-portage/mirrorselect`, `mirrorselect -s3 -b10 -D`
  (writes GENTOO_MIRRORS to make.conf). - [Mirrorselect](https://wiki.gentoo.org/wiki/Mirrorselect)
- **Config merges**: `dispatch-conf` after updates. - [Handbook: Working/Portage](https://wiki.gentoo.org/wiki/Handbook:AMD64/Working/Portage)

## Kernel choice & hardening
- **Sources**: `gentoo-kernel-bin` (prebuilt), `gentoo-kernel` (source dist-kernel,
  reads `/etc/kernel/config.d/*.config`), `gentoo-sources` (manual), `vanilla-sources`.
- **KSPP hardening**: the single Gentoo toggle `CONFIG_GENTOO_KERNEL_SELF_PROTECTION=y`
  enables the recommended settings; plus `INIT_ON_ALLOC/FREE_DEFAULT_ON`,
  `RANDOMIZE_KSTACK_OFFSET_DEFAULT`, Yama/Landlock, `LEGACY_VSYSCALL_NONE`, no slab-merge.
  **Lockdown** (`SECURITY_LOCKDOWN_LSM[_EARLY]`, `LOCK_DOWN_KERNEL_FORCE_CONFIDENTIALITY`)
  ONLY with signed modules or a monolithic kernel. Boot cmdline mirrors these
  (`init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on slab_nomerge …`). -
  [KSPP on Gentoo](https://wiki.gentoo.org/wiki/User:Pietinger/Tutorials/Kernel_Hardening_with_KSPP) ·
  [KSPP settings](https://kspp.github.io/Recommended_Settings.html) ·
  [Kernel/Configuration](https://wiki.gentoo.org/wiki/Kernel/Configuration)
- **Secure Boot** (`--secure-boot`): `app-crypt/sbctl` creates keys and signs the
  bootloader + kernel; enrollment (`sbctl enroll-keys --microsoft`, firmware in Setup
  Mode) is left manual because it writes UEFI key stores. -
  [Secure Boot](https://wiki.gentoo.org/wiki/Secure_Boot) ·
  [sbctl](https://wiki.gentoo.org/wiki/Secure_Boot#Using_your_own_keys)

## Init systems
- OpenRC (`rc-update` / `rc-service`) and systemd (`systemctl`) are both supported -
  [OpenRC](https://wiki.gentoo.org/wiki/OpenRC) · [systemd](https://wiki.gentoo.org/wiki/Systemd)

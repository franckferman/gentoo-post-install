<div id="top" align="center">

<h3 align="center">🐧 gentoo-post-install</h3>

<p align="center">
    <em>Automated post-install setup for Gentoo Linux: Portage, hardening, kernel, and desktop.</em><br>
    From a bare stage3 to a hardened, personalized system.<br>
    <strong>Profile-based · idempotent · OpenRC <em>and</em> systemd · dry-run-first.</strong>
</p>

[![Lint][lint-shield]][lint-url]
![Shell](https://img.shields.io/badge/shell-bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Init](https://img.shields.io/badge/init-OpenRC%20%2B%20systemd-54487A?style=for-the-badge)

<sub>Related projects:
<a href="https://github.com/franckferman/debian-server-post-install">Debian Server</a> ·
<a href="https://github.com/franckferman/ubuntu-post-install">Ubuntu</a> ·
<a href="https://github.com/franckferman/win-postinstall">Windows</a></sub>

</div>

## Table of contents

<details open>
  <summary><strong>Click to expand / collapse</strong></summary>

- [Features](#features)
- [Quick Start](#quick-start)
- [Profiles](#profiles)
- [Steps](#steps)
- [Options](#options)
- [Applications & desktop](#applications--desktop)
- [Kernel, OPSEC & accounts](#kernel-opsec--accounts)
- [Undo](#undo)
- [Manual page](#manual-page)
- [Requirements](#requirements)
- [Development](#development)
- [References](#references)
- [License](#license)

</details>

> [!WARNING]
> This script changes system-level configuration (`make.conf`, USE flags, services).
> **Read it first**, run with `--dry-run`, and keep the automatic `make.conf` backup
> (`/etc/portage/make.conf.gpi.bak`). Gentoo is a moving target: review Portage news.

## Features

- **Profile-based** configuration: `default`, `desktop`, `server`, `hardened`, `minimal`, `opsec`
- **OpenRC and systemd**: auto-detected, both fully supported
- **Portage configuration**: auto `MAKEOPTS` (cores capped by RAM), `COMMON_FLAGS`,
  `EMERGE_DEFAULT_OPTS`, `FEATURES`, `CPU_FLAGS_X86` via `cpuid2cpuflags`
- **Binary package host** (opt-in): official Gentoo binhost for fast installs
- **World maintenance**: sync, `@world` update, preserved-rebuild, depclean, news
- **Tooling**: `gentoolkit`, `eix`, `portage-utils`, `genlop`, `mirrorselect`
- **USE-flag layout**: clean, reviewable `package.use` baseline per profile
- **Distribution kernel** (opt-in): `gentoo-kernel-bin` + firmware + `installkernel`
- **Safe by default**: idempotent, dry-run, automatic backups, `--steps` selection
- **Hardening**: sysctl network/kernel drop-in, default-deny firewall
  (nftables/iptables/ufw, SSH-safe), hardened OpenSSH (validated with `sshd -t`)
- **Monitoring & MAC**: audit + system logging, fail2ban (sshd jail),
  USBGuard (opt-in), AppArmor (opt-in)
- **Shell & terminal**: zsh + oh-my-zsh + powerlevel10k + plugins, vim/neovim,
  a `.zshrc` with Portage-aware aliases, configured for your real (non-root) user
- **Desktop**: Nerd Fonts, `VIDEO_CARDS`/`INPUT_DEVICES` autodetection, Xorg/Wayland,
  dbus/elogind, PipeWire, NetworkManager
- **Applications & DE** (native, no Flatpak): overlays via eselect-repository, apps by
  name (overlay auto-enabled), native Steam, and a desktop-environment + display-manager
  chooser (KDE/GNOME/Sway/Hyprland/XFCE)
- **CPU microcode** (Intel/AMD), fastest-mirror selection, guided `dispatch-conf`
- **Kernel chooser**: source (`bin/dist/source/vanilla`) x config
  (`standard/hardened/minimal/performance`), KSPP hardening, lockdown, cmdline, auto or manual
- **OPSEC**: attack-surface minimization, multi-level log minimization, an `opsec` profile
- **Sysops**: users/groups/sudo and root password/lock, passwords via `chpasswd` stdin

## Quick Start

```bash
# Download
curl -O https://raw.githubusercontent.com/franckferman/gentoo-post-install/stable/gentoo-post-install.sh
chmod +x gentoo-post-install.sh

# Safe defaults, interactive
sudo ./gentoo-post-install.sh

# Preview any run first: prints every action, changes nothing
sudo ./gentoo-post-install.sh --dry-run

# Desktop workstation, non-interactive, binhost to speed things up
sudo ./gentoo-post-install.sh --profile desktop --binhost -y

# Only configure make.conf + install tooling
sudo ./gentoo-post-install.sh --steps 2,4
```

## Profiles

Pick a profile with `--profile <name>`. A profile sets **defaults**; every individual
flag then **overrides** it (defaults are applied first, your flags win).

| Setting | `default` | `desktop` | `server` | `hardened` | `minimal` | `opsec` |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| `-march=native` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| ACCEPT_LICENSE | `@FREE` | `+@BINARY-REDISTRIBUTABLE` | `@FREE` | `@FREE` | `@FREE` | `@FREE` |
| Firewall | - | - | nftables | nftables | - | nftables |
| sysctl hardening | - | - | ✓ | ✓ (+IPv6) | - | ✓ (+IPv6) |
| SSH hardening | - | - | ✓ | ✓ (key-only) | - | ✓ (key-only) |
| audit + logs | - | - | ✓ | ✓ | - | ✓ |
| fail2ban | - | - | ✓ | ✓ | - | ✓ |
| AppArmor | - | - | - | ✓ | - | ✓ |
| surface + log minimization | - | - | - | - | - | ✓ |
| shell + fonts + desktop | - | ✓ | - | - | - | - |

**Desktop and the firewall.** The `desktop` profile ships **without** a firewall by
default, because the strict default-deny ruleset would block local-network discovery
(mDNS/avahi, KDE Connect, printers, casting). Firewall strictness is decoupled from the
profile, so a desktop user who wants one just adds it, at either level:

```bash
# Desktop with a strict, server-grade firewall (hardening)
sudo ./gentoo-post-install.sh --profile desktop --firewall nftables

# Desktop with a LAN-friendly firewall (keeps mDNS / KDE Connect / printers working)
sudo ./gentoo-post-install.sh --profile desktop --firewall nftables --firewall-lan
```

**Hardened vs freer** is just a profile choice, and you can fine-tune either way:

```bash
# Maximum lockdown
sudo ./gentoo-post-install.sh --profile hardened

# Hardened, but keep password SSH and drop fail2ban, and use iptables
sudo ./gentoo-post-install.sh --profile hardened --firewall iptables --no-fail2ban

# As free/permissive as it gets: only Portage touched, all licenses accepted
sudo ./gentoo-post-install.sh --profile default --accept-license all
```

## Steps

Run any subset with `--steps` (e.g. `--steps 1-4`, `--steps 2,6`). List them with `--list-steps`.

| # | Step | What it does |
|---|------|--------------|
| 01 | Sync & news | `emerge --sync` (or `eix-sync` / webrsync fallback) + read Portage news |
| 02 | Portage config | `MAKEOPTS`, `COMMON_FLAGS`, `EMERGE_DEFAULT_OPTS`, `FEATURES`, CPU flags |
| 03 | Binhost | Configure Gentoo binary package host (opt-in via `--binhost`) |
| 04 | Tooling | `gentoolkit`, `eix`, `portage-utils`, `genlop`, `mirrorselect` |
| 05 | World update | `emerge -uUDN @world`, `@preserved-rebuild`, `--depclean` |
| 06 | USE flags | Write a reviewable global USE baseline for the chosen profile |
| 07 | Kernel | Install a distribution kernel + firmware (opt-in via `--install-kernel`) |
| 08 | sysctl hardening | Network/kernel `sysctl.d` drop-in (opt-in via `--sysctl-harden`) |
| 09 | Firewall | Default-deny firewall: nftables / iptables / ufw (`--firewall`) |
| 10 | SSH hardening | Hardened `sshd_config.d` drop-in, validated with `sshd -t` (`--ssh-harden`) |
| 11 | Audit & logging | `sys-process/audit` + a system logger (`--audit`; journald-aware) |
| 12 | fail2ban | fail2ban with an sshd jail (`--fail2ban`) |
| 13 | USBGuard | USBGuard + policy from connected devices (opt-in `--usbguard`) |
| 14 | AppArmor | Install + enable AppArmor, LSM guidance (opt-in `--apparmor`) |
| 15 | Shell & terminal | zsh + oh-my-zsh + powerlevel10k + plugins, vim/neovim, `.zshrc` w/ Portage aliases (`--shell`) |
| 16 | Nerd Fonts | Install patched Nerd Fonts for your user + `fc-cache` (`--fonts`) |
| 17 | Desktop stack | `VIDEO_CARDS` + `INPUT_DEVICES` autodetect, Xorg/Wayland, dbus/elogind, PipeWire, NetworkManager (`--desktop`) |
| 18 | Overlays | Enable ebuild repositories via eselect-repository (`--overlay guru,...`) |
| 19 | Applications | Native apps by name + overlay auto-enable, native Steam (`--apps`, `--apps-profile`, `--steam`) |
| 20 | Desktop environment | KDE/GNOME/Sway/Hyprland/XFCE + display manager (`--de`, `--dm`) |
| 21 | Surface minimization | Blacklist risky modules, kexec/coredumps off, tighten sysctl (`--minimize-surface`) |
| 22 | Log minimization | journald volatile/retention, shell history off, dmesg (`--logs reduce\|ephemeral`) |
| 23 | Accounts | Users/groups/sudo + root password/lock, passwords via `chpasswd` stdin (`--user`, `--group`, `--root-password`, `--disable-root`) |

## Options

See `./gentoo-post-install.sh --help` for the full list. Highlights:

```
--profile <name>        default | desktop | server | hardened | minimal | opsec
--dry-run, -n           Print actions without executing them
--yes, -y               Non-interactive
--steps <list>          Run only selected steps (1,2,5 or 1-4)
--log-file <path>       Tee a timestamped transcript to a file
--rollback              Revert managed changes (make.conf backup + drop-ins)
--binhost[-uri <uri>]   Enable / point the binary package host
--march native|none     CPU baseline (default: native)
--jobs <N>              Force MAKEOPTS -jN
--accept-license <m>    default | free | all
--install-kernel        Install gentoo-kernel-bin
--bootloader <b>        grub | systemd-boot | none  (installkernel USE)
--initramfs <i>         dracut | none               (installkernel USE)
--sysctl-harden         Apply sysctl network/kernel hardening
--hardened-malloc       Install sys-libs/hardened_malloc (opt-in)
--firewall <backend>    nftables | iptables | ufw | none
--firewall-lan          Also allow local discovery (mDNS/SSDP/KDE Connect)
--ssh-harden            Hardened sshd_config.d drop-in (validated first)
--ssh-key-only          sshd: PasswordAuthentication no (need a key!)
--audit / --fail2ban    Install audit+logging / fail2ban (sshd jail)
--usbguard / --apparmor Opt-in USBGuard / AppArmor
--shell                 zsh + powerlevel10k + editors (for your real user)
--editor <choice>       vim | neovim | both | none
--fonts                 Install Nerd Fonts
--desktop               Xorg/Wayland + dbus/elogind + PipeWire + NetworkManager
--video-cards <value>   Override VIDEO_CARDS (skip autodetect)
--overlay <list>        Enable overlays (guru,pentoo,...) or add name=git-url
--apps <list>           Install apps (firefox,vlc,obsidian,...), overlay auto-enabled
--apps-profile <p>      daily | dev | media | gaming
--steam                 Native Steam (steam-overlay + multilib)
--de <choice>           kde | gnome | sway | hyprland | xfce | none
--dm <choice>           sddm | gdm | lightdm | greetd | none | auto
--microcode             CPU microcode (Intel/AMD, vendor-detected)
--mirrors               Pick fastest GENTOO_MIRRORS (mirrorselect)
--merge-config          Run dispatch-conf at the end
--list-apps / --list-overlays   List known apps / popular overlays
--kernel-source <s>     bin | dist | source | vanilla
--kernel-config <c>     standard | hardened | minimal | performance
--kernel-lockdown / --kernel-cmdline-harden / --kernel-manual / --microcode
--minimize-surface      Attack-surface reduction (modules, kexec, sysctl, services)
--logs <level>          off | reduce | ephemeral
--root-password / --disable-root
--group <name>          Create a group (repeatable)
--user <spec>           name[:sudo][:nopasswd][:groups=a,b][:shell=/bin/bash] (repeatable)
--allow-root            Run directly as root (fresh installs)
```

## Applications & desktop

No Flatpak by default: apps come from **Portage and overlays** (enabled with
[`eselect-repository`](https://wiki.gentoo.org/wiki/Eselect/Repository)). Obsidian comes
from the **r7l** overlay (auto-enabled); Discord and Signal are in the main Gentoo tree;
**Steam** is native via the `steam-overlay` (needs a multilib profile).

```bash
# From a fresh Gentoo to a usable KDE desktop with apps
sudo ./gentoo-post-install.sh --profile desktop --de kde --dm sddm \
     --apps firefox,vlc,obsidian,keepassxc

# A tiling Wayland setup + a ready-made app set
sudo ./gentoo-post-install.sh --de sway --apps-profile daily

# Gaming box: native Steam + Discord
sudo ./gentoo-post-install.sh --apps-profile gaming --steam

# Just add an overlay and one app
sudo ./gentoo-post-install.sh --overlay guru --apps obsidian

# Discover what's available
./gentoo-post-install.sh --list-apps
./gentoo-post-install.sh --list-overlays
```

## Kernel, OPSEC & accounts

**Kernel: pick your source and config** (default `bin`, so nothing breaks):

```bash
# Hardened distribution kernel (KSPP), built from source
sudo ./gentoo-post-install.sh --install-kernel --kernel-source dist --kernel-config hardened
# add --kernel-lockdown (signed modules / monolithic only) and --kernel-cmdline-harden
```

Sources: `bin` (gentoo-kernel-bin), `dist` (gentoo-kernel), `source` (gentoo-sources,
`--kernel-manual` / `localmodconfig`), `vanilla`. Configs: `standard | hardened | minimal
| performance`. Config fragments land in `/etc/kernel/config.d/`; hardened uses the Gentoo
KSPP toggle. A custom config **can fail to boot**, so the previous kernel is always kept.

**OPSEC & hardening**:

- `--minimize-surface`: module blacklist, kexec/coredumps off, `ptrace_scope=2`, BPF hardening, mask extra services.
- `--logs off|reduce|ephemeral`: reduce/volatile journald, shell history off + cleared, `dmesg_restrict`. A privacy/footprint choice; you also lose debuggability and intrusion signals.
- `--profile opsec`: bundles firewall + sysctl/IPv6 + SSH key-only + audit + fail2ban + AppArmor + hardened-malloc + `--minimize-surface` + `--logs reduce`.

**Accounts & sysops**: passwords are always read from a masked prompt and applied via
`chpasswd` on **stdin**, never in argv.

```bash
# Create an admin user (wheel + sudo) and lock root
sudo ./gentoo-post-install.sh --user 'admin:sudo' --disable-root

# A power user with groups and a shell; a service group; a passwordless-sudo user
sudo ./gentoo-post-install.sh --group devs \
     --user 'alice:sudo:groups=devs,audio:shell=/bin/zsh' \
     --user 'ci:sudo:nopasswd'
```

`--disable-root` is refused unless a **non-root wheel member** exists (no lock-out). Every
sudoers drop-in is validated with `visudo -c`. `:nopasswd` grants passwordless sudo and is
warned about.

## Undo

Every managed file carries a `gentoo-post-install` marker and `make.conf` is backed up
to `make.conf.gpi.bak` before editing. To revert:

```bash
sudo ./gentoo-post-install.sh --rollback
```

This restores `make.conf` and removes the managed drop-ins (CPU flags, USE baseline,
sysctl, binhost, fail2ban jail, SSH drop-in) and the sudoers grants it created. It
intentionally does **not** uninstall packages, disable services, delete accounts, or touch
`/etc/nftables.conf`; review those by hand.

## Manual page

A man page is included:

```bash
man ./gentoo-post-install.1
# or install it:  sudo cp gentoo-post-install.1 /usr/share/man/man1/ && sudo mandb
```

## Requirements

- A Gentoo system with Portage (`emerge`) available
- Root (via `sudo`/`doas`, or `--allow-root`)
- Network access for sync and package installs

## Development

The script is a single Bash file kept **`shellcheck`-clean** and syntax-checked. A
`Makefile` runs the whole gate in one command:

```bash
make check                              # bash -n + shellcheck + unit + integration + profiles + smoke + man
make lint SHELLCHECK=/path/to/shellcheck  # override the binary (e.g. a local build)
make test                               # 72 unit checks (pure functions, mocked)
make integration                        # 30 fake-root checks (real writes to a temp tree)
make profiles                           # dry-run every profile, expect rc=0
make smoke                              # 9 dry-run flag-combo invocations, expect rc=0
./gentoo-post-install.sh --dry-run -y   # preview the full run, no changes
```

An optional **QEMU/KVM boot-test** (`make boot-test`, or `tests/boot-test.sh`) goes one
step further than the suites: it boots a real kernel image headless with a tiny
static-init initramfs and the exact **KSPP hardened command line** the tool applies
(`lockdown=confidentiality init_on_alloc=1 pti=on ...`) and asserts the kernel reaches
userspace, proving those params do not brick boot. It needs `qemu` + `gcc` (KVM if
available), touches nothing on the host, and is kept out of `make check` (CI has no KVM).

The **unit** suite (`tests/test.sh`) sources the script as a library and checks pure
functions with every external command mocked. The **integration** suite
(`tests/integration.sh`) runs selected steps *for real* against a throwaway temp tree
(Portage paths redirected, no sudo, no host writes) and asserts the files they produce,
including a whole-tree idempotency check that re-runs every writer and requires a
byte-identical result. The **smoke** matrix (`tests/smoke.sh`) drives representative full
flag combinations end-to-end through `main()` in `--dry-run`, each expecting rc=0.

Bash completion lives in `contrib/gentoo-post-install.bash`. CI runs the same gate on
every push and pull request. `.shellcheckrc` disables only **SC2317** (a false positive:
step functions are dispatched indirectly by name from the step registry, which
ShellCheck's static analysis cannot follow).

## References

Every Gentoo-specific choice (make.conf configuration, binhost, USE conventions, toolchain
hardening, PipeWire, the kernel/`installkernel` wiring) is sourced against the Gentoo wiki
and handbook in **[references.md](references.md)**. Note in particular:

- Toolchain hardening (SSP/PIE/RELRO/`_FORTIFY_SOURCE`) is **on by default** on 23.0
  profiles; it is not a USE flag, and a hardened *profile* is set with `eselect profile`.
- With PipeWire, the `pulseaudio` USE flag stays **enabled** (libpulse compat).

## License

[AGPL-3.0](LICENSE) © Franck FERMAN

<!-- Shield definitions -->
[lint-shield]: https://img.shields.io/github/actions/workflow/status/franckferman/gentoo-post-install/lint.yml?branch=stable&style=for-the-badge&label=lint
[lint-url]: https://github.com/franckferman/gentoo-post-install/actions/workflows/lint.yml

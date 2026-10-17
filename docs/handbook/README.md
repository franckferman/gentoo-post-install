# The Gentoo Post-Install Handbook

A step-by-step, *do-it-by-hand* companion to [`gentoo-post-install.sh`](../../gentoo-post-install.sh).

The script automates post-install configuration, hardening, and tooling for Gentoo.
This handbook teaches you to perform **every one of those actions manually**, so you
understand what the automation does and why. Each chapter maps to one step of the
script: it explains the concepts, walks the commands with their reasoning, shows how
to verify the result, and how to roll it back.

> **This is a learning companion, not a replacement for the official
> [Gentoo Handbook](https://wiki.gentoo.org/wiki/Handbook:Main_Page).** It assumes a
> working base install (stage3 + chroot already done) and picks up from there, exactly
> where `gentoo-post-install.sh` does. Where the two overlap (base install), we point
> you to the official Handbook rather than duplicate it.

## How to use this

- Read top to bottom for a full post-install + hardening walkthrough, or jump to the
  chapter for the task you want to learn.
- Every chapter ends with a **Script reference** box: the `step_NN` it mirrors, the
  `--flags` that drive it, and the exact files the script writes, so you can compare
  your manual result against the automated one.
- Prefer to see it before you run it? The script's `--dry-run` prints every action
  without touching the system; use it alongside the matching chapter.

## Conventions

- `# command` = run as root (post-install work is done as root, or with `sudo`).
- `$ command` = run as your normal user.
- **OpenRC and systemd** are both covered; where they differ, both are shown.
- A bold **Warning:** marker flags steps that can lock you out (SSH, firewall, USBGuard, root). Read them first.

## Chapters

| # | Chapter | Script step | Flag(s) |
|---|---------|-------------|---------|
| 00 | [Prerequisites & philosophy](00-prerequisites.md) | - | - |
| 01 | [The base install (recap)](01-base-install.md) | - | - |
| 02 | [Syncing Portage & reading news](02-portage-sync-news.md) | 01 | `--no-sync`, `--mirrors` |
| 03 | [Tuning `make.conf`](03-make-conf.md) | 02 | `--no-tune`, `--march`, `--jobs`, `--accept-license` |
| 04 | [Binary packages (binhost)](04-binary-packages.md) | 03 | `--binhost`, `--binhost-uri` |
| 05 | [Portage tooling](05-portage-tooling.md) | 04 | - |
| 06 | [Updating @world & cleanup](06-world-update.md) | 05 | `--no-world-update`, `--no-depclean` |
| 07 | [USE flags & package.use](07-use-flags.md) | 06 | - |
| 08 | [Kernel, microcode & Secure Boot](08-kernel-microcode.md) | 07 | `--install-kernel`, `--kernel-*`, `--microcode`, `--secure-boot` |
| 09 | [sysctl hardening](09-sysctl-hardening.md) | 08 | `--sysctl-harden`, `--harden-ipv6` |
| 10 | [Firewall](10-firewall.md) | 09 | `--firewall`, `--firewall-lan`, `--no-ssh-rule` |
| 11 | [SSH hardening](11-ssh-hardening.md) | 10 | `--ssh-harden`, `--ssh-port`, `--ssh-no-root`, `--ssh-key-only` |
| 12 | [Audit & logging](12-audit-logging.md) | 11 | `--audit` |
| 13 | [fail2ban](13-fail2ban.md) | 12 | `--fail2ban` |
| 14 | [USBGuard](14-usbguard.md) | 13 | `--usbguard` |
| 15 | [AppArmor](15-apparmor.md) | 14 | `--apparmor` |
| 16 | [Shell & terminal](16-shell-terminal.md) | 15 | `--shell`, `--editor`, `--shell-user` |
| 17 | [Fonts](17-fonts.md) | 16 | `--fonts`, `--nerd-fonts` |
| 18 | [Desktop stack](18-desktop-stack.md) | 17 | `--desktop`, `--display`, `--no-audio`, `--no-nm` |
| 19 | [GPU drivers](19-gpu-drivers.md) | 24 | `--gpu`, `--gpu-vendor`, `--gpu-compute` |
| 20 | [Overlays / repositories](20-overlays.md) | 18 | `--overlay` |
| 21 | [Applications](21-applications.md) | 19 | `--apps`, `--apps-profile`, `--steam` |
| 22 | [Desktop environment & display manager](22-desktop-environment.md) | 20 | `--de`, `--dm` |
| 23 | [Attack-surface minimization](23-attack-surface.md) | 21 | `--minimize-surface` |
| 24 | [Log-footprint minimization](24-log-minimization.md) | 22 | `--logs` |
| 25 | [Users, groups & sudo](25-accounts.md) | 23 | `--user`, `--group`, `--root-password`, `--disable-root` |
| 99 | [Appendix: profiles, rollback, troubleshooting, references](99-appendix.md) | - | `--profile`, `--rollback` |

> Chapter numbers are *reading order*; the "Script step" column maps each to the
> `step_NN_*` function in `gentoo-post-install.sh`. GPU (step 24 in the script) is
> placed next to the desktop stack here because that is where it belongs when learning.

## Contributing

New chapters follow [`TEMPLATE.md`](TEMPLATE.md) and mirror the matching `step_NN_*`
function exactly. Keep manual steps in sync with the script when it changes.

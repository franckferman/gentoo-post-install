# Prerequisites & philosophy

> What this handbook is, who it is for, and what you need before chapter 02.

## Why learn the manual way

[`gentoo-post-install.sh`](../../gentoo-post-install.sh) automates post-install setup,
hardening, and tooling. Automation is convenient, but on Gentoo the real value is
*understanding your system*: every file the script writes, you could have written
yourself, and knowing why makes you able to debug, adapt, and trust it.

This handbook walks each action by hand. Read it with the script open: run the script
with `--dry-run` to see exactly what it would do, then follow the matching chapter to
do (or understand) it yourself.

## The Gentoo mindset

- **Source-based by default.** You compile most packages, so build configuration
  (`make.conf`, USE flags) is a first-class concern, not an afterthought.
- **Explicit over implicit.** Nothing is enabled behind your back. You choose your
  init system, your drivers (`VIDEO_CARDS`), your features (USE flags), your kernel.
- **Composable config.** A *drop-in* is a small, single-purpose config file placed in a
  `.d/` directory that the system reads alongside (and after) the main config, so each
  change is isolated and reversible by deleting one file. Portage works this way under
  `/etc/portage/` (`package.use/`, `package.accept_keywords/`, `package.license/`), and
  so do `sysctl.d/`, `sshd_config.d/` and `jail.d/` later in this handbook. The script,
  and this handbook, prefer dedicated, commented drop-ins over one giant file, so each
  change documents itself and is easy to revert.
- **The wiki is authoritative.** When in doubt, the
  [Gentoo Wiki](https://wiki.gentoo.org/) and the
  [Handbook](https://wiki.gentoo.org/wiki/Handbook:Main_Page) are the source of truth.
  This companion never contradicts them; it connects them to one concrete workflow.

## What you need before starting

- A **working Gentoo base install**: a booted system from a stage3, with Portage
  present (`emerge` works). If you are not there yet, see the next chapter,
  [The base install (recap)](01-base-install.md).
- **Root access** (you run post-install work as root, or via `sudo`/`doas`).
- A **network connection** (syncing the tree and building packages need it).
- Knowing your **init system** (OpenRC or systemd) and whether your profile is
  **multilib** (needed for 32-bit software like Steam). Check:
  ```bash
  # root
  eselect profile show          # shows your profile (look for "systemd" / "no-multilib")
  [ -d /run/systemd/system ] && echo systemd || echo openrc
  ```

## Conventions used throughout

- `# command` runs as **root**; `$ command` runs as your **normal user**.
- Where **OpenRC and systemd** differ, both are shown. As a rule:
  - OpenRC: `rc-update add <svc> default` then `rc-service <svc> start`.
  - systemd: `systemctl enable --now <svc>`.
- A **Warning:** marks a step that can **lock you out** (SSH, firewall, USBGuard, root, kernel
  lockdown). Read those before running them, and keep a console/TTY available.
- Each chapter's **Script reference** box lists the matching `step_NN`, its flags, and
  the exact files it manages, so you can compare your result against the automation.

## Safety: preview before you change

The single most useful habit: preview. The script's `--dry-run` prints every command
it would run and every file it would write, changing nothing:

```bash
# any user
./gentoo-post-install.sh --profile hardened --dry-run
```

Doing it by hand, the equivalents are: back up a file before editing it, use
`emerge --pretend` (`-p`) / `--ask` before a big merge, and validate configs
(`sshd -t`, `nft -c`, `sysctl` dry checks) before you reload a service.

---
[Handbook index](README.md) · [Next: The base install (recap) →](01-base-install.md)

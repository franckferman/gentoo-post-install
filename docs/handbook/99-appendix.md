# Appendix: profiles, rollback, troubleshooting & references

> Cross-cutting topics that are not a single step: the `--profile` presets, running a
> subset of steps, previewing, undoing changes, and where to go when something breaks.

## Profiles (`--profile`)

A profile is a bundle of sane defaults you can still override with explicit flags
(flags always win). The script applies the profile first, then your flags.

| Profile | What it turns on |
|---------|------------------|
| `default` | Balanced baseline: tune `make.conf`, tooling, `@world` update. |
| `desktop` | `default` + `-march=native`, license policy `redist` (lets firmware in), shell, fonts, desktop stack. |
| `server` | `default` + firewall, sysctl hardening, SSH hardening, audit + logging, fail2ban. |
| `hardened` | `server` + IPv6 hardening, SSH key-only, AppArmor. |
| `minimal` | Lean: tooling, CPU flags, `-march=native`, preserved-rebuild; nothing extra. |
| `opsec` | Everything in `hardened` + hardened_malloc + attack-surface minimization + reduced logging. |

Think of profiles as starting points for the chapters: a `server` profile is chapters
09 to 13 pre-selected; `opsec` adds 23 and 24. Read the matching chapters to learn
what each switch actually does.

## Running only some steps (`--steps`)

Every chapter maps to a `step_NN`. To do just a few, pass a list or range:

```bash
./gentoo-post-install.sh --steps 2,6,8        # make.conf, USE flags, sysctl
./gentoo-post-install.sh --steps 1-6          # the Portage basics, in order
./gentoo-post-install.sh --list-steps         # show every step and its number
```

By hand, this is simply choosing which chapters to follow. The step numbers are listed
by `--list-steps` and in the [index](README.md) table.

## Preview everything (`--dry-run`)

`--dry-run` prints every command and every file write without changing anything. Use
it to read the plan before committing, and to learn by example:

```bash
./gentoo-post-install.sh --profile hardened --dry-run
```

## Undoing changes (`--rollback`)

`--rollback` restores `make.conf` from its automatic backup and removes the managed
drop-in files (only if they still carry the `# Managed by gentoo-post-install` marker,
so it never deletes a file you hand-edited). It does **not** uninstall packages,
disable services, or touch `/etc/nftables.conf`; those you revert manually.

Files it restores/removes (useful to know for manual rollback too):

```
/etc/portage/make.conf                         <- restored from make.conf.gpi.bak
/etc/portage/package.use/00cpu-flags
/etc/portage/package.use/10-baseline
/etc/portage/package.use/20-installkernel
/etc/portage/package.use/30-microcode
/etc/portage/package.use/40-gpu
/etc/portage/package.license/gpi-apps
/etc/portage/package.license/gpi-gpu
/etc/portage/package.license/steam
/etc/portage/package.accept_keywords/steam
/etc/kernel/config.d/90-gpi-hardening.config
/etc/kernel/config.d/90-gpi-performance.config
/etc/sysctl.d/99-gentoo-post-install.conf
/etc/sysctl.d/99-gpi-opsec.conf
/etc/sysctl.d/99-gpi-logs.conf
/etc/modprobe.d/gpi-blacklist.conf
/etc/modprobe.d/gpi-nvidia.conf
/etc/security/limits.d/gpi-coredump.conf
/etc/systemd/journald.conf.d/gpi-logs.conf
/etc/profile.d/gpi-nohistory.sh
/etc/portage/binrepos.conf/gentoobinhost.conf
/etc/fail2ban/jail.d/99-gentoo-post-install.local
/etc/ssh/sshd_config.d/99-gentoo-post-install.conf
/etc/sudoers.d/00-gpi-wheel  and  /etc/sudoers.d/10-gpi-*
```

Things rollback deliberately leaves alone (revert by hand if needed): the firewall
ruleset (`/etc/nftables.conf`, with a `.gpi.bak` if you made one), KSPP kernel cmdline
params in the bootloader config, the `Include .../sshd_config.d/*.conf` line, the
OpenRC `DISPLAYMANAGER` setting, installed packages, and enabled services.

## Logging a run (`--log-file`)

```bash
./gentoo-post-install.sh --profile server --log-file /var/log/gpi-$(date +%F).log
```

Tees a timestamped transcript so you can audit exactly what happened.

## Troubleshooting

- **Portage wrote config updates.** After `@world` changes, merge them:
  `dispatch-conf` (or `etc-update`). Review diffs; do not blindly accept.
- **An emerge failed mid-run.** With `--keep-going` the rest continues; re-run the
  same command to retry the failed package, and read the build log it points to.
- **Autounmask changes needed** (new USE/keyword/license). Portage prints a block to
  accept; apply with `dispatch-conf`, or re-run with `--autounmask-write`.
- **Broken shared libraries after an update.** `revdep-rebuild` (from gentoolkit) or
  `emerge @preserved-rebuild`.
- **Reclaim space / clean up.** `eclean-dist` and `eclean-pkg` (gentoolkit),
  `emerge --depclean -p` (always `-p` first to see what would go).
- **A service will not start.** OpenRC: `rc-service <svc> status` and
  `/var/log/rc.log`; systemd: `systemctl status <svc>` and `journalctl -u <svc>`.
- **Locked out after hardening.** Boot a live medium, chroot in (chapter 01, move 5),
  and remove the offending drop-in or restore `make.conf.gpi.bak`.

## References

- [Gentoo Handbook](https://wiki.gentoo.org/wiki/Handbook:Main_Page) - the base install.
- [Gentoo Wiki](https://wiki.gentoo.org/) - per-topic authority (Portage, USE, nftables, AppArmor, GPU...).
- [`references.md`](../../references.md) in this repo - sources cited by the script.
- `./gentoo-post-install.sh --help` - the full, current flag list.

---
[← Previous: Users, groups & sudo](25-accounts.md) · [Handbook index](README.md)

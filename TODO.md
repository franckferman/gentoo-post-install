# Roadmap

`gentoo-post-install` is feature-complete: 23 steps covering Portage,
hardening, kernel, OPSEC, desktop, applications, and account management, with a full
test gate (unit + integration + smoke + an optional QEMU boot-test; see the README).

The items below are optional future enhancements, not blockers. Ideas and contributions
are welcome via issues.

## Planned / ideas

- [ ] Screenshots and an asciinema demo in the README
- [ ] Firewall extras: opt-in SSH rate-limiting and logging of dropped packets
- [ ] SSH: refine `sshd_config.d` Include ordering (first-match-wins) for pre-existing configs
- [ ] Shell: ship a ready-made `.p10k.zsh` and an XDG-compliant prompt preset
- [ ] Fonts: prefer the Portage `media-fonts/nerd-fonts` packages where USE-scoping fits
- [ ] Post-update maintenance: optional `@module-rebuild` / `revdep-rebuild`
- [ ] End-to-end full-install validation in a throwaway VM (beyond the QEMU boot-test)

## Non-goals

- Flatpak/Snap as the default app source: this tool stays native Portage + overlays
- Running on non-Gentoo systems: a real run refuses, while `--dry-run` previews anywhere

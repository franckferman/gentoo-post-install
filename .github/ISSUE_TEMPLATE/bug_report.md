---
name: Bug report
about: Something the script did wrong (a bad atom, a failed step, an unexpected change)
title: "[bug] "
labels: bug
---

**Do not paste secrets** (passwords, keys). Prefer `--dry-run` output where possible.

### What happened
A clear description of the problem.

### Command
```
# the exact invocation, e.g.:
./gentoo-post-install.sh --dry-run --profile hardened ...
```

### Expected vs actual
- Expected:
- Actual:

### Environment
- Script version (`./gentoo-post-install.sh --version`):
- Init system: OpenRC / systemd
- Profile used: default / desktop / server / hardened / minimal / opsec
- Gentoo profile (`eselect profile show`):
- Relevant step number(s) (`--list-steps`):

### Output
```
# paste the relevant log lines (a --dry-run run is ideal)
```

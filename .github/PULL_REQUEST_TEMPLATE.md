### Summary
What does this change and why?

### Gentoo verification
- [ ] Atoms / USE flags / service names verified against the Gentoo wiki or
      packages.gentoo.org (link them in `references.md` where relevant).

### Checklist
- [ ] `make check` passes (bash -n + shellcheck + unit + integration + dry-run profiles + mandoc)
- [ ] New/changed behavior is covered by a test (`tests/test.sh` or `tests/integration.sh`)
- [ ] `--help` and the man page (`gentoo-post-install.1`) updated if flags changed
- [ ] Version bumped consistently where relevant (script, header, man page, README, docs)
- [ ] Idempotent and `--dry-run`-safe; no secrets in argv

### Notes for reviewers
Anything non-obvious, trade-offs, or follow-ups.

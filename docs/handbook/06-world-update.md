# Updating @world & cleanup

> Bring every installed package and its dependencies up to date, rebuild anything left
> inconsistent, optionally remove orphans, and merge any config files Portage staged.
> Mirrors the script's step 05 (`--no-world-update`, `--no-depclean`).

## What the script automates

`step_05_world_update` runs the full upgrade of the `@world` set with
`emerge --update --deep --newuse --with-bdeps=y --keep-going=y --ask=n @world`, then
runs `emerge @preserved-rebuild` to fix packages still linking old libraries, then
(after a confirmation prompt) `emerge --depclean` to drop orphans, and finally reminds
you to merge staged config updates with `dispatch-conf`. The end state is a fully
updated, internally consistent system.

## Concepts

The **`@world` set** is the list of packages you explicitly asked for plus the system
set. Updating `@world` is how you upgrade the whole machine, not just one package. The
letters on the upgrade command each widen or harden what the update does:

- **`-u` / `--update`**: upgrade the named packages to the best available version.
  Alone it only touches the packages you list.
- **`-D` / `--deep`**: consider the *entire* dependency tree, not just the top-level
  `@world` members, so out-of-date dependencies get upgraded too. Without it, a stale
  library two levels down is left behind.
- **`-N` / `--newuse`**: rebuild a package when its USE flags have changed, *including*
  when the ebuild added or removed a flag. This is what makes a USE change (see
  [USE flags & package.use](07-use-flags.md)) actually take effect.
- **`-U` / `--changed-use`**: the narrower sibling of `-N`. It rebuilds only when the
  *enabled or disabled* flags that affect a package changed, and ignores flags merely
  added to or removed from the ebuild that are off anyway. You will see the combined
  form `emerge -uUDN @world` on the wiki; `-N` already covers the `-U` cases plus more,
  so the script uses `--newuse` and accepts the few extra rebuilds in exchange for not
  missing one.
- **`--with-bdeps=y`**: also pull and keep build-time dependencies, so later
  `--depclean` does not mistake a needed build tool for an orphan.
- **`--keep-going=y`**: if one package in a large set fails to build, skip it and keep
  going with the rest instead of aborting the whole update. You fix the failures
  afterward rather than losing the entire run to the first error.

Two cleanup concepts follow the upgrade:

- **`@preserved-rebuild`** is a Portage set of packages that still link against an old
  shared library Portage had to *preserve* because something was still using it. When a
  library's version bumps, Portage keeps the old `.so` around until everything that
  needs it is rebuilt; this set rebuilds exactly those packages so the old library can
  finally go.
- **`--depclean`** removes packages nothing in `@world` depends on any more (orphans).
  It reclaims space and shrinks your attack surface, but it is the one dangerous step in
  this chapter, so you always preview it first.

- **Staged config.** When a package ships a new default config file and you have edited
  the old one, Portage does not overwrite yours; it stages the new file as a
  `._cfg0000_<name>` sibling and leaves you to merge. **`dispatch-conf`** (or
  `etc-update`) is how you review and apply those, keeping a backup of each change.

## Do it by hand

### 1. Update the @world set

```bash
# root
emerge --update --deep --newuse --with-bdeps=y --keep-going=y --ask @world
```

This is the core upgrade, exactly as described above: upgrade everything (`-u`), across
the full dependency tree (`-D`), rebuilding on USE changes (`-N`), keeping build deps
(`--with-bdeps=y`) and not aborting on a single failure (`--keep-going=y`). Keep `--ask`
when running by hand so you see the plan before it builds (the script uses `--ask=n`
because it is non-interactive). Read the plan: a surprising number of packages, a
profile change, or blockers mean you should stop and investigate.

### 2. Rebuild preserved-library consumers

```bash
# root
emerge @preserved-rebuild
```

Run this right after the upgrade. If `emerge --info` or the end of the update mentioned
preserved libraries, this rebuilds the packages still using them so the old library can
be dropped. If nothing is preserved, it is a no-op and returns immediately.

### 3. (Optional, careful) Remove orphans with depclean

**Warning:** **`--depclean` removes packages.** It occasionally wants to remove something you
actually use, especially right after installing but before adding a package to
`@world`, or when a USE change dropped a dependency. **Always run the pretend/preview
first and read the list before committing.**

```bash
# root
emerge --pretend --depclean          # preview ONLY: nothing is removed
emerge --ask --depclean              # then, if the list is safe, remove them
```

The preview (`-p`/`--pretend`) prints exactly what would be unmerged without touching
anything. Only when every line in that list is something you genuinely do not need
should you run the second command. The script wraps this in a yes/no confirmation for
the same reason. If you see a package you want to keep, add it to `@world` first with
`emerge --noreplace <pkg>` so depclean stops considering it an orphan.

### 4. Merge staged config updates

```bash
# root
dispatch-conf
```

`dispatch-conf` walks you through each `._cfg*` file Portage staged, showing a diff and
letting you keep yours, take theirs, merge, or edit. It archives every change so you can
revert. `etc-update` does the same job with a simpler interface; use whichever you
prefer, but do not ignore the staged files: a skipped config migration can silently
break a service on its next restart.

## Verify

```bash
# root
emerge --update --deep --newuse --pretend @world   # should report nothing (or only trivial) to do
emerge @preserved-rebuild --pretend                # should find nothing to rebuild
find /etc -name '._cfg*' 2>/dev/null               # should print nothing after dispatch-conf
```

An up-to-date system shows an empty or near-empty upgrade plan on the pretend run, no
preserved rebuilds pending, and no leftover `._cfg*` files. `qlist -IC | wc -l` (from
[Portage tooling](05-portage-tooling.md)) before and after `--depclean` shows how many
orphans you removed.

## Pitfalls and rollback

- **Warning:** **Running `--depclean` without previewing.** This is the classic way to remove a
  package you needed. Always `emerge --pretend --depclean` first, and add wanted
  packages to `@world` with `--noreplace` beforehand.
- **A single package fails mid-update.** With `--keep-going=y` the rest still upgraded;
  fix the one failure separately (`emerge <pkg>` and read its error), then re-run the
  `@world` update to confirm it is clean.
- **Skipping `dispatch-conf`.** Staged `._cfg*` files pile up and a service keeps using
  an old config until you merge. Run it after every update that touched `/etc`.
- **A bad update broke something.** Portage keeps old versions until depclean removes
  them, so before depcleaning you can usually downgrade with
  `emerge --oneshot =category/package-oldversion`. There is no single "undo" for an
  `@world` upgrade; this is why you read the plan in step 1.
- **Rollback.** This step writes no managed config files, so the script's `--rollback`
  does not touch it. Recovery is the normal Portage downgrade/rebuild above.

## Script reference

- **Step:** `05` - `step_05_world_update`
- **Flags:** `--no-world-update` (skip the `@world` upgrade), `--no-depclean` (skip
  orphan removal). `@preserved-rebuild` always runs after a successful update.
- **Managed files:** none. The step upgrades installed packages; `dispatch-conf`
  reconciles any `/etc/._cfg*` files Portage staged.

---
[← Previous: Portage tooling](05-portage-tooling.md) · [Handbook index](README.md) · [Next: USE flags & package.use →](07-use-flags.md)

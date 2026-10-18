# Binary packages (binhost)

> Point Portage at Gentoo's official prebuilt binary package server so big packages
> install in seconds instead of compiling locally, with signatures verified end to end.
> Mirrors the script's step 03 (`--binhost`, `--binhost-uri`).

## What the script automates

`step_03_binhost` (only when you pass `--binhost`) writes a binary repository
definition to `/etc/portage/binrepos.conf/gentoobinhost.conf` pointing at the official
amd64 23.0 binhost, installs `app-portage/getuto` and runs it to set up the trust
anchors for signed packages, then appends `getbinpkg binpkg-request-signature` to
`FEATURES` in `make.conf`. After this, `emerge` prefers a verified prebuilt binary
whenever one matches your USE flags, and compiles only what does not.

## Concepts

Gentoo is source-based, but you do not have to compile everything. Gentoo publishes a
**binhost**: a server of prebuilt `.gpkg` binary packages built against the standard
23.0 profile. When a binary there matches what you asked for, Portage downloads and
installs it instead of building from source.

- **Why you want it.** A from-scratch build of Rust, LLVM, Chromium, or a browser can
  take hours. A prebuilt binary installs in the time it takes to download, which makes
  the first `@world` update dramatically faster on modest hardware.
- **The catch: USE flags must match.** A binary is built with the binhost's USE flags,
  `CFLAGS`, and profile. If your package's USE differs, Portage cannot use the binary
  and falls back to compiling from source. So the binhost helps most when your config
  is close to the Gentoo defaults, and less when you have heavily customized USE.
- **`binrepos.conf`.** Binary repositories are configured under
  `/etc/portage/binrepos.conf/`, one `.conf` file per repo, mirroring how `repos.conf`
  configures the ebuild tree. Each has a `sync-uri` (where to fetch), a `priority`
  (higher wins when several repos offer the same package), and
  `verify-signature = true`.
- **Signatures.** Prebuilt binaries are a code-execution path, so you verify they came
  from Gentoo. `binpkg-request-signature` in `FEATURES` tells Portage to *refuse* any
  binary that is not signed, and `verify-signature = true` on the repo enforces it per
  repo. The signatures are checked against trust anchors that `getuto` installs: it
  imports the Gentoo release keys into a dedicated Portage keyring
  (`/etc/portage/gnupg`) so Portage can validate binpkgs without touching your personal
  GnuPG setup.

## Do it by hand

### 1. Create the binrepos.conf directory

```bash
# root
mkdir -p /etc/portage/binrepos.conf
```

Portage reads every `.conf` file in this directory. Keeping the binhost in its own file
means you can disable it later by deleting one file.

### 2. Define the official binhost

Write the repository definition. The URI is Gentoo's amd64 binhost for the 23.0
profile:

```bash
# root
cat > /etc/portage/binrepos.conf/gentoobinhost.conf <<'EOF'
[binhost]
priority = 9999
sync-uri = https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64
verify-signature = true
EOF
```

- `[binhost]`: the repo's internal name (any label works).
- `priority = 9999`: a high priority so, when a package is available both prebuilt and
  from this repo's perspective, this binhost is preferred.
- `sync-uri`: the official amd64 23.0 binary package tree. If you run a different
  arch or profile, use the matching path (this is exactly what `--binhost-uri` overrides
  in the script).
- `verify-signature = true`: never install an unsigned or badly signed binary from
  this repo.

### 3. Install the trust anchors with getuto

```bash
# root
emerge --ask=n app-portage/getuto
getuto
```

`getuto` creates and populates Portage's dedicated binpkg keyring under
`/etc/portage/gnupg` with the Gentoo release keys. Run it once now (and again if Gentoo
rotates keys); without it, signature verification has nothing to verify against and
every binary install fails.

### 4. Turn on binary packages in FEATURES

Append the two feature tokens to your existing `FEATURES` in `make.conf` (do not drop
the values you set in [Tuning make.conf](03-make-conf.md)):

```bash
# root - edit make.conf so FEATURES includes both tokens, e.g.:
FEATURES="candy parallel-fetch parallel-install getbinpkg binpkg-request-signature"
```

- `getbinpkg`: fetch and use remote binary packages when available.
- `binpkg-request-signature`: require a valid signature on every binary package, so a
  tampered or unsigned binary is rejected rather than installed.

## Verify

```bash
# root
emerge --info | grep -E '^FEATURES=' | grep -o 'getbinpkg\|binpkg-request-signature'
emerge -p --getbinpkg app-shells/bash
```

The first command confirms both features are active. In the `emerge -p` (pretend)
output, a package that will come from the binhost is tagged with a **binary** marker
(Portage prints `[binary]` next to it), while packages with no matching binary still
show the normal source build. Seeing at least one `[binary]` line proves the binhost is
reachable and signatures validate. A real install then downloads instead of compiling.

## Pitfalls and rollback

- **Everything still compiles from source.** Almost always a USE-flag mismatch: your
  package's flags differ from the binhost's, so no binary matches. That is expected and
  safe; the binhost is a best-effort speedup, not a guarantee.
- **Warning:** **Signature/trust errors** (`!!! Binary package ... has no valid signature`)
  usually mean `getuto` was never run or the keys are stale. Re-run `getuto`. Do **not**
  "fix" this by removing `binpkg-request-signature`: that disables the protection that
  stops you installing a tampered binary.
- **Profile/arch mismatch.** The URI is amd64 23.0. On another profile the binaries do
  not match your system; set the correct `sync-uri` (the script's `--binhost-uri`).
- **Rollback.** Remove the repo definition and drop the two `FEATURES` tokens:
  ```bash
  # root
  rm -f /etc/portage/binrepos.conf/gentoobinhost.conf
  # edit make.conf: remove 'getbinpkg binpkg-request-signature' from FEATURES
  ```
  The script's `--rollback` deletes `binrepos.conf/gentoobinhost.conf` and restores
  `make.conf` from `make.conf.gpi.bak` (which reverts the `FEATURES` change). It does
  not remove the `getuto` keyring, which is harmless to leave in place.

## Script reference

- **Step:** `03` - `step_03_binhost`
- **Flags:** `--binhost` (enable), `--binhost-uri <uri>` (override the `sync-uri`)
- **Managed files:** `/etc/portage/binrepos.conf/gentoobinhost.conf`, and
  `/etc/portage/make.conf` (`FEATURES` gains `getbinpkg binpkg-request-signature`;
  backed up to `make.conf.gpi.bak`). `getuto` populates `/etc/portage/gnupg`.

---
[← Previous: Tuning make.conf](03-make-conf.md) · [Handbook index](README.md) · [Next: Portage tooling →](05-portage-tooling.md)

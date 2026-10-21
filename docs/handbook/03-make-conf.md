# Tuning `make.conf`

> `/etc/portage/make.conf` is the control panel for how Portage builds your system:
> compiler flags, parallelism, licenses, and emerge defaults. This mirrors the
> script's `--profile`-aware tuning (step 02).

## What the script automates

`step_02_portage_tuning` backs up `make.conf` once, then sets a sane baseline:
`MAKEOPTS` (build parallelism), `COMMON_FLAGS` (compiler optimization), a resilient
`EMERGE_DEFAULT_OPTS`, useful `FEATURES`, an `ACCEPT_LICENSE` policy, and your CPU's
`CPU_FLAGS_X86`. You can reproduce all of it by hand, and understand each knob.

## Concepts

On a source-based distribution, **you compile most packages locally**, so `make.conf`
directly decides how fast builds run and how optimized the result is.

- **`MAKEOPTS`** controls how many compile jobs run in parallel (`-jN`). More jobs use
  more RAM; a heavy C++ package (LLVM, WebKit, Chromium) can use well over 2 GB per
  job, so parallelism is bounded by RAM, not just cores.
- **`COMMON_FLAGS`** feeds the compiler. `-march=native` tells GCC to target *this
  exact CPU* (enabling its instruction sets); `-O2 -pipe` is the safe, standard
  optimization level. `-O3` is not recommended on Gentoo: it produces larger code, is
  sometimes slower, and occasionally miscompiles packages that upstream only tests at `-O2`.
- **`FEATURES`** toggles Portage behaviors (parallel fetch/install, build candy, binary
  packages, sandboxing).
- **`ACCEPT_LICENSE`** decides which software licenses Portage will install without
  complaint: free-only, free plus redistributable firmware, or everything.
- **`CPU_FLAGS_X86`** is a Gentoo-specific USE expansion that lets packages pick
  hand-optimized code paths (AES-NI, AVX2, SHA, ...) for your CPU.

## Do it by hand

### 1. Back up the file first

Always keep a pristine copy before editing. The script does this once, into a
`.gpi.bak` sibling; do the same.

```bash
# root
cp -a /etc/portage/make.conf /etc/portage/make.conf.bak
```

Why: `make.conf` mistakes (a bad flag, an unquoted value) can break every subsequent
`emerge`. A backup makes rollback a one-line `cp`.

### 2. Set build parallelism (`MAKEOPTS`)

A good heuristic: one job per core, but capped at roughly one job per 2 GB of RAM, and
a load limit of `cores + 1` so the machine stays responsive.

```bash
# root
nproc                                   # number of logical cores, e.g. 8
awk '/MemTotal/{printf "%d\n",$2/1024/1024}' /proc/meminfo   # RAM in GB, e.g. 16
```

With, say, 8 cores and 16 GB RAM: `16 / 2 = 8` RAM-bound jobs, which does not drop
below the 8 cores, so use `-j8`. On 8 cores with only 8 GB you would cap at `-j4`.

```bash
# root - edit make.conf and set:
MAKEOPTS="-j8 -l9"
```

Why `-l9` (load average limit = cores + 1): it throttles new jobs when the system is
already saturated, which keeps an interactive session usable during a long `@world`
rebuild.

### 3. Set compiler flags (`COMMON_FLAGS`)

```bash
# root - in make.conf:
COMMON_FLAGS="-march=native -O2 -pipe"
```

`-march=native` optimizes for the current CPU. Use it when you build on the same
machine you run on. If you build on one CPU and run on another (or want portable
binaries), drop it and use `COMMON_FLAGS="-O2 -pipe"` instead (the script's
`--march none`). `-pipe` uses pipes instead of temp files between compiler stages
(faster, costs a little RAM). `CFLAGS`, `CXXFLAGS`, etc. normally inherit
`COMMON_FLAGS`, so a stage3 already wires them with `${COMMON_FLAGS}`.

### 4. Make emerge resilient and quiet (`EMERGE_DEFAULT_OPTS`)

```bash
# root - in make.conf:
EMERGE_DEFAULT_OPTS="--verbose --quiet-build=y --with-bdeps=y --complete-graph=y --keep-going=y --ask=n"
```

- `--keep-going=y`: if one package in a big set fails, skip it and continue instead of
  aborting the whole run.
- `--with-bdeps=y` / `--complete-graph=y`: pull and consider build-time dependencies so
  the dependency graph is complete (fewer surprises on `--depclean`).
- `--quiet-build=y`: hide verbose build chatter but keep errors.
- `--ask=n`: do not prompt (you are scripting intent, not babysitting prompts).

### 5. Set Portage features (`FEATURES`)

```bash
# root - in make.conf:
FEATURES="candy parallel-fetch parallel-install"
```

`parallel-fetch` downloads sources while another package builds; `parallel-install`
merges independent packages concurrently; `candy` is a nicer progress UI. (Binary
packages add `getbinpkg` here; see [Binary packages](04-binary-packages.md).)

### 6. Choose a license policy (`ACCEPT_LICENSE`)

Pick one line depending on how strict you want to be:

```bash
# Free software only (strictest):
ACCEPT_LICENSE="-* @FREE"
# Free + binary-redistributable (lets firmware/microcode in) - good for real hardware:
ACCEPT_LICENSE="@FREE @BINARY-REDISTRIBUTABLE"
# Everything (accepts EULAs/proprietary blobs automatically - least strict):
ACCEPT_LICENSE="*"
```

If you set nothing, you keep the Gentoo profile default (which already allows most
free licenses and will prompt for the rest). The script calls these `free`, `redist`,
and `all`; `default` leaves it untouched.

### 7. Compute your CPU flags (`CPU_FLAGS_X86`)

Let a tool detect them rather than guessing:

```bash
# root
emerge --ask=n app-portage/cpuid2cpuflags
cpuid2cpuflags                          # prints: CPU_FLAGS_X86: aes avx avx2 f16c ...
```

Write them to a clear, dedicated `package.use` drop-in (the script writes
`package.use/00cpu-flags`), applied to every package with `*/*`:

```bash
# root
mkdir -p /etc/portage/package.use
printf '# CPU instruction sets for this machine\n*/* %s\n' \
  "$(cpuid2cpuflags)" \
  > /etc/portage/package.use/00cpu-flags
```

Keep the `CPU_FLAGS_X86:` label that `cpuid2cpuflags` prints: in `package.use` it is the
USE_EXPAND group name that assigns those tokens to `CPU_FLAGS_X86`. Strip it and the tokens
become ordinary (mostly non-existent) USE flags and the group is never set.

Why a `package.use` drop-in rather than a line in `make.conf`: it keeps the (long,
machine-specific) list isolated and easy to regenerate, and documents its origin.

## Verify

```bash
# root
emerge --info | grep -E '^(MAKEOPTS|CFLAGS|CXXFLAGS|FEATURES|ACCEPT_LICENSE|CPU_FLAGS_X86)='
```

`emerge --info` prints the *effective* configuration after Portage merges `make.conf`,
the profile, and your `package.use`. Confirm each value matches what you set. A quick
build (e.g. re-emerging a small package) should now show your `-jN` in action.

## Pitfalls and rollback

- **Too-high `MAKEOPTS` on low RAM** → OOM-killed builds mid-compile. Lower `-jN`.
- **`-march=native` then moving the disk to a different CPU** → illegal-instruction
  crashes. Rebuild with a portable `-march`, or `-O2 -pipe` only.
- **`ACCEPT_LICENSE="*"`** silently accepts proprietary EULAs; use it deliberately.
- **Rollback:** restore your backup and you are back to the previous state:
  ```bash
  # root
  cp -a /etc/portage/make.conf.bak /etc/portage/make.conf
  rm -f /etc/portage/package.use/00cpu-flags
  ```
  The script's `--rollback` does exactly this (restores `make.conf.gpi.bak`, removes
  `package.use/00cpu-flags`).

## Script reference

- **Step:** `02` - `step_02_portage_tuning`
- **Flags:** `--no-tune`, `--march native|none`, `--jobs <N>`, `--accept-license default|free|redist|all`, `--no-cpu-flags`
- **Managed files:** `/etc/portage/make.conf` (backed up to `make.conf.gpi.bak`),
  `/etc/portage/package.use/00cpu-flags`

---
[← Previous: Syncing Portage & reading news](02-portage-sync-news.md) · [Handbook index](README.md) · [Next: Binary packages (binhost) →](04-binary-packages.md)

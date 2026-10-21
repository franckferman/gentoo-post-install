# Kernel, microcode & Secure Boot

> Install a Linux kernel the way Gentoo wants you to: a distribution kernel wired to
> your bootloader and initramfs through `installkernel`, optional KSPP hardening or a
> performance config, CPU microcode, and (opt-in) Secure Boot signing with `sbctl`.
> Mirrors the script's `step_07_kernel` plus its microcode and Secure Boot helpers
> (step 07, `--install-kernel` / `--microcode` / `--secure-boot`).

## What the script automates

`step_07_kernel` installs `sys-kernel/linux-firmware` and a kernel package chosen by
`--kernel-source` (`bin` → `gentoo-kernel-bin`, `dist` → `gentoo-kernel`, `source` →
`gentoo-sources`, `vanilla` → `vanilla-sources`). Before building, it sets the USE
flags on `sys-kernel/installkernel` so that installing a kernel automatically builds
the initramfs and updates your bootloader, and (for source-built kernels) it drops
KSPP hardening or performance config fragments into `/etc/kernel/config.d`. Optionally
it adds KSPP parameters to the kernel command line, installs CPU microcode (Intel via
`intel-microcode`, AMD via `linux-firmware`), and signs your bootloader and kernels
for Secure Boot with `sbctl`. Key creation and signing are automated; UEFI key
*enrollment* is deliberately left as a guided manual step because it can brick a
machine.

## Concepts

Gentoo gives you three broad ways to get a kernel. The script exposes them through
`--kernel-source`:

- **Distribution kernel, prebuilt (`bin` = `gentoo-kernel-bin`).** A ready-compiled
  kernel plus modules. Nothing to configure, fastest to install, and the safe default.
  Because it is already built, custom config fragments do **not** apply to it.
- **Distribution kernel, source-built (`dist` = `gentoo-kernel`).** Portage builds it
  from source using a sane default config, *and* it reads any fragments you put in
  `/etc/kernel/config.d`. This is the one to pick if you want the script's hardening or
  performance tweaks compiled in without a full manual kernel.
- **Manual sources (`source` = `gentoo-sources`, `vanilla` = `vanilla-sources`).** You
  get the tree under `/usr/src/linux` and configure and build it yourself. `vanilla` is
  the untouched upstream tree with no Gentoo patches.

Two more packages matter for every install:

- **`sys-kernel/linux-firmware`** ships the firmware blobs many drivers need (Wi-Fi,
  GPU, and AMD CPU microcode). The script installs it unconditionally.
- **`sys-kernel/installkernel`** is the glue. When a kernel image is installed, it runs
  the hooks that build an initramfs and register the kernel with your bootloader. Its
  USE flags decide *which* initramfs generator and *which* bootloader are wired up, so
  the flags must be set **before** `installkernel` is built. The script controls them
  with `--initramfs` (`dracut`) and `--bootloader` (`grub` / `systemd-boot`), and adds
  `systemd` when you are on a systemd system.

The config modes (`--kernel-config`) only have teeth on a source-built kernel:

- **`standard`**: leave the default config alone (no fragment written).
- **`hardened`**: write a KSPP (Kernel Self-Protection Project) fragment that flips on
  Gentoo's self-protection bundle and related options.
- **`performance`**: write a latency/throughput fragment (1000 Hz, tickless idle,
  preemption, native CPU tuning).
- **`minimal`**: build a hardware-only kernel with `make localmodconfig`; needs
  `--kernel-source source` or `vanilla`.

Finally, **CPU microcode** patches errata and security issues in your processor at
boot, and **Secure Boot** makes the firmware refuse to run any boot binary that is not
signed by a key it trusts. Both are covered below.

## Do it by hand

### 1. Install firmware

```bash
# root
emerge --ask sys-kernel/linux-firmware
```

Why first: modern GPUs and Wi-Fi chips will not initialize without their blobs, and on
AMD this package also carries the CPU microcode. The script installs it no matter which
kernel you choose.

### 2. Set `installkernel` USE flags, then install it

Decide your initramfs and bootloader, write the flags to a `package.use` drop-in, then
emerge `installkernel`. The flags must be in place first so the right hooks are built.

```bash
# root - example: dracut initramfs + GRUB (the defaults)
cat > /etc/portage/package.use/20-installkernel <<'EOF'
# Managed by gentoo-post-install
sys-kernel/installkernel dracut grub
EOF
emerge --ask sys-kernel/installkernel
```

Build the flag list to match your system:

- `dracut`: enable if `--initramfs dracut` (the default). Pulls in and drives
  `sys-kernel/dracut` to generate an initramfs on each kernel install. Omit for
  `--initramfs none`.
- `grub` **or** `systemd-boot`: one bootloader flag, matching `--bootloader`. With
  `--bootloader none`, add neither and you must point your bootloader at the kernel
  yourself.
- `systemd`: add this on a systemd system (the script adds it when the init system is
  systemd), so the install hooks integrate with `kernel-install` the systemd way.

Why a drop-in and not `make.conf`: the choice is package-specific and easy to revert,
and it keeps the "why this flag" comment next to the flag.

### 3. (Source-built kernels) write the config fragment

Skip this for `--kernel-config standard`. For `hardened` or `performance`, drop a
fragment into `/etc/kernel/config.d`; a source-built `gentoo-kernel` merges these at
build time.

Hardened (KSPP). This is exactly what the script writes:

```bash
# root
mkdir -p /etc/kernel/config.d
cat > /etc/kernel/config.d/90-gpi-hardening.config <<'EOF'
# Managed by gentoo-post-install - KSPP hardening
CONFIG_GENTOO_KERNEL_SELF_PROTECTION=y
CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y
CONFIG_INIT_ON_FREE_DEFAULT_ON=y
CONFIG_RANDOMIZE_KSTACK_OFFSET_DEFAULT=y
CONFIG_SECURITY_YAMA=y
CONFIG_SECURITY_LANDLOCK=y
CONFIG_LEGACY_VSYSCALL_NONE=y
# CONFIG_SLAB_MERGE_DEFAULT is not set
EOF
```

Why these: `CONFIG_GENTOO_KERNEL_SELF_PROTECTION` is Gentoo's single toggle that pulls
in the bulk of the KSPP recommendations. The rest zero memory on allocation and free
(`INIT_ON_ALLOC`/`INIT_ON_FREE`), randomize the kernel stack offset per syscall, enable
the Yama and Landlock LSMs, disable the legacy vsyscall interface, and stop the
allocator from merging slab caches (which makes some heap exploits easier). These are
upstream-documented hardening options, not Gentoo inventions.

Performance:

```bash
# root
cat > /etc/kernel/config.d/90-gpi-performance.config <<'EOF'
# Managed by gentoo-post-install - performance
CONFIG_HZ_1000=y
CONFIG_NO_HZ_IDLE=y
CONFIG_PREEMPT=y
EOF
# then add ONE line matching your CPU vendor:
#   Intel:  CONFIG_MNATIVE_INTEL=y
#   AMD:    CONFIG_MNATIVE_AMD=y
```

Why: a 1000 Hz tick with a tickless idle and full preemption favors interactive
latency; `MNATIVE_*` tells the kernel build to optimize for your exact CPU family. The
script appends the right `MNATIVE_*` line automatically from `/proc/cpuinfo`.

**Warning:** A source-built hardened or minimal kernel can fail to boot on your specific hardware.
Keep the currently working kernel installed, and verify the new one boots before you
rely on it. For `--kernel-source bin` the fragments are ignored (the binary is already
compiled); the script warns about this, and you should use `--kernel-source dist` to
actually compile the options in.

### 4. (Optional) enable the lockdown LSM

Lockdown restricts even root from modifying the running kernel (loading unsigned
modules, writing `/dev/mem`, kexec, certain hibernation paths). The script's
`--kernel-lockdown` adds three options to the hardening fragment:

```text
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y
CONFIG_LOCK_DOWN_KERNEL_FORCE_CONFIDENTIALITY=y
```

**Warning:** Lockdown in confidentiality mode is safe **only** with a monolithic kernel or signed
modules. Otherwise it breaks loading of unsigned modules (the proprietary NVIDIA driver
included), and it interferes with hibernation. Enable this deliberately, and pair it
with Secure Boot (step 7) so modules are signed. If X or your GPU driver stops loading
after this, lockdown is the first suspect.

### 5. Install the kernel

```bash
# root - pick the package matching --kernel-source:
emerge --ask sys-kernel/gentoo-kernel-bin     # bin  (prebuilt, safe default)
# emerge --ask sys-kernel/gentoo-kernel       # dist (source-built, reads config.d)
# emerge --ask sys-kernel/gentoo-sources      # source (manual configure/build)
# emerge --ask sys-kernel/vanilla-sources     # vanilla (upstream, manual build)
```

For `bin` and `dist`, `installkernel` runs its hooks during the merge: it builds the
initramfs and updates your bootloader, so after the emerge you just confirm `/boot` and
your bootloader entry look right.

For `source` / `vanilla`, only the tree is installed; you configure and build it:

```bash
# root - standard manual build
cd /usr/src/linux
make defconfig && make menuconfig      # or start from your own config
make && make modules_install && make install
# minimal (hardware-only) build instead:
#   make localmodconfig && make && make modules_install && make install
```

**Warning:** Verify the new kernel boots before removing the current one. `make localmodconfig`
builds support only for hardware currently in use, so a module you need later (a USB
device, a filesystem) may be missing; regenerate the config if that happens. (With
`--kernel-manual` the script stops after `make menuconfig` and does not auto-build.)

### 6. (Optional) harden the kernel command line

Compiled-in defaults cover most KSPP options, but a few are command-line switches. The
script's `--kernel-cmdline-harden` appends them to your bootloader config.

```bash
# root - the KSPP cmdline the script adds:
#   init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on slab_nomerge
#   page_table_check=on vsyscall=none pti=on page_alloc.shuffle=1
# (with --kernel-lockdown it also appends: lockdown=confidentiality)
```

For GRUB, add them to `GRUB_CMDLINE_LINUX` and regenerate the config:

```bash
# root
sed -i -E 's|^(GRUB_CMDLINE_LINUX=")(.*)(")|\1\2 init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on slab_nomerge page_table_check=on vsyscall=none pti=on page_alloc.shuffle=1\3|' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
```

For systemd-boot (or any non-GRUB setup), the parameters go in `/etc/kernel/cmdline`,
which `installkernel`/`kernel-install` folds into the boot entry; rebuild afterward:

```bash
# root
echo 'init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on slab_nomerge page_table_check=on vsyscall=none pti=on page_alloc.shuffle=1' >> /etc/kernel/cmdline
# then regenerate the entry, e.g. by reinstalling the kernel or running dracut/kernel-install
```

Why: these enforce the zeroing, stack randomization, no-slab-merge, page-table checks,
disabled vsyscall, forced page-table isolation, and freelist shuffling at runtime.
**Warning:** These lines are *appended* to shared files, so `--rollback` does not remove them;
edit `/etc/default/grub` or `/etc/kernel/cmdline` by hand to undo.

### 7. Install CPU microcode

Find your vendor first:

```bash
# root
grep -m1 vendor_id /proc/cpuinfo      # GenuineIntel or AuthenticAMD
```

**Intel.** Install `sys-firmware/intel-microcode`. The script sets
`MICROCODE_SIGNATURES="-S"` in `make.conf` (keep only the microcode for the CPU in this
machine, not every Intel CPU) and writes a USE drop-in:

```bash
# root
grep -q '^MICROCODE_SIGNATURES=' /etc/portage/make.conf \
  && sed -i 's/^MICROCODE_SIGNATURES=.*/MICROCODE_SIGNATURES="-S"/' /etc/portage/make.conf \
  || echo 'MICROCODE_SIGNATURES="-S"' >> /etc/portage/make.conf

cat > /etc/portage/package.use/30-microcode <<'EOF'
# Managed by gentoo-post-install
sys-firmware/intel-microcode initramfs split-ucode
EOF

emerge --ask sys-firmware/intel-microcode
```

Why those USE flags: `split-ucode` installs the microcode as individual files so an
initramfs generator (dracut) can assemble an *early* microcode image, and `initramfs`
has the package itself produce an early-load cpio archive. Early loading means the
microcode is applied before the kernel brings the CPU fully up, which is what you want.
After installing, regenerate the initramfs and confirm early load with
`dmesg | grep -i microcode`.

**AMD.** AMD microcode ships inside `sys-kernel/linux-firmware` (already installed in
step 1) and is loaded by the initramfs or kernel. There is no separate package:

```bash
# root
emerge --ask sys-kernel/linux-firmware     # no-op if already installed
```

### 8. (Optional) Secure Boot with `sbctl`

**Warning:** Secure Boot can make a machine unbootable if the firmware rejects your keys. Have a
rescue USB ready, and do **not** enroll keys blindly. The script automates key creation
and signing but leaves enrollment as a manual, guided step for this reason.

Install the tool and let it create your own key set:

```bash
# root
emerge --ask app-crypt/sbctl
sbctl status                  # shows setup mode, whether sbctl keys are installed
sbctl create-keys             # create your signing keys (if none exist yet)
```

Sign the bootloader and every kernel image. The script probes the EFI System Partition
(via `bootctl -p`, else `/efi`, `/boot/efi`, `/boot`) and signs what it finds:

```bash
# root - sign each existing EFI binary (-s saves it to the sbctl database for re-signing)
sbctl sign -s /boot/EFI/gentoo/grubx64.efi            # GRUB (path varies)
sbctl sign -s /boot/EFI/systemd/systemd-bootx64.efi   # systemd-boot
sbctl sign -s /boot/vmlinuz-*                          # kernel image(s)
sbctl verify                                          # list signed vs unsigned
```

Then enroll the keys **manually**, which is the step that writes UEFI NVRAM:

```bash
# root
# 1) In firmware setup, clear the existing Secure Boot keys ("Setup Mode").
# 2) Enroll your keys, keeping Microsoft's so option ROMs / other OSes still boot:
sbctl enroll-keys --microsoft
# 3) Re-enable Secure Boot in firmware, reboot, then confirm:
sbctl status
# After every kernel update, re-sign:
sbctl sign-all
```

Why keep the Microsoft keys (`--microsoft`): many GPUs and other option ROMs are signed
only by Microsoft's keys, and dropping them can leave a device (or a dual-boot OS)
unbootable. Why re-sign after updates: a new kernel image is unsigned until you sign
it, and Secure Boot will refuse to load it.

What this does not cover is the initramfs. `sbctl` here signs the loader and the kernel,
but a separate initramfs is loaded unverified, so with GRUB the measured chain stops at
the kernel and an attacker who can rewrite the initramfs is not caught. The clean way to
close that gap is a Unified Kernel Image (UKI): the kernel, the initramfs, and the kernel
command line are bundled into one PE binary that you sign as a whole and boot directly
with systemd-boot or the EFI stub. If you need Secure Boot to attest the initramfs too,
build a UKI (on the installer side the `installkernel` plus `uki` USE flags wire this)
rather than signing a kernel next to a loose initramfs.

## Verify

```bash
# root
uname -r                                  # running kernel version
ls /boot/vmlinuz-* /boot/initramfs-*      # kernel image + initramfs present
eselect kernel list                       # (for /usr/src symlink-based setups)

# microcode applied early at boot:
dmesg | grep -i microcode                 # Intel: "microcode updated early to revision ..."
grep -c . /sys/devices/system/cpu/cpu0/microcode/version 2>/dev/null

# hardening options compiled in (adjust path to your kernel):
zcat /proc/config.gz | grep -E 'INIT_ON_ALLOC_DEFAULT_ON|RANDOMIZE_KSTACK|LANDLOCK|LOCKDOWN'
# KSPP cmdline params actually active:
cat /proc/cmdline

# Secure Boot state:
sbctl status                              # "Secure Boot: enabled" and your keys enrolled
bootctl status | grep -i 'secure boot'    # systemd-boot systems
```

You want `uname -r` to match the kernel you just installed, an initramfs next to it in
`/boot`, `dmesg` to confirm microcode loaded early, and the hardening `CONFIG_*` lines
to read `=y`. For Secure Boot, `sbctl status` should report it enabled with your keys.

## Pitfalls and rollback

- **`installkernel` USE set too late.** If the `dracut`/`grub`/`systemd-boot` flags were
  not present when `installkernel` was built, no initramfs or bootloader entry is
  generated. Fix the drop-in and re-emerge `sys-kernel/installkernel`, then reinstall
  the kernel.
- **Config fragments with `gentoo-kernel-bin`.** They are ignored; the binary is
  prebuilt. Switch to `--kernel-source dist` (`gentoo-kernel`) to compile them in.
- **Hardened/minimal kernel will not boot.** Pick the previous kernel from the
  bootloader menu; it is kept. Then relax the config and rebuild.
- **Lockdown broke module loading / NVIDIA / hibernation.** Expected without signed
  modules. Remove the lockdown lines from the fragment (and `lockdown=confidentiality`
  from the cmdline), rebuild, or set up Secure Boot module signing.
- **Secure Boot: machine will not boot after enrolling.** Boot the rescue USB, or clear
  Secure Boot keys / disable Secure Boot in firmware, then re-sign and re-enroll
  carefully. This is why enrollment is manual.
- **Rollback:** the script's `--rollback` removes the managed drop-ins and config
  fragments:
  ```bash
  # root
  rm -f /etc/portage/package.use/20-installkernel \
        /etc/portage/package.use/30-microcode \
        /etc/kernel/config.d/90-gpi-hardening.config \
        /etc/kernel/config.d/90-gpi-performance.config
  ```
  It restores `make.conf` from `make.conf.gpi.bak` (undoing `MICROCODE_SIGNATURES`).
  It does **not** uninstall kernel/microcode packages, and it does **not** strip the
  KSPP params it appended to `/etc/default/grub` or `/etc/kernel/cmdline` (edit those by
  hand), nor does it un-enroll Secure Boot keys.

## Script reference

- **Step:** `07` - `step_07_kernel` (+ helpers `_kernel_hardening_fragment`,
  `_kernel_performance_fragment`, `_apply_kernel_config`, `_kernel_harden_cmdline`,
  `_install_microcode`, `_secure_boot_setup`, `_find_esp`)
- **Flags:** `--install-kernel`, `--kernel-pkg <atom>`,
  `--kernel-source bin|dist|source|vanilla`,
  `--kernel-config standard|hardened|minimal|performance`, `--kernel-lockdown`,
  `--kernel-cmdline-harden`, `--kernel-manual`, `--bootloader grub|systemd-boot|none`,
  `--initramfs dracut|none`, `--microcode`, `--secure-boot`
- **Managed files:** `/etc/portage/package.use/20-installkernel`,
  `/etc/portage/package.use/30-microcode`,
  `/etc/kernel/config.d/90-gpi-hardening.config`,
  `/etc/kernel/config.d/90-gpi-performance.config`, `MICROCODE_SIGNATURES` in
  `/etc/portage/make.conf`; *appends* (not auto-reverted) to `/etc/default/grub`
  (`GRUB_CMDLINE_LINUX`) or `/etc/kernel/cmdline`; Secure Boot keys/signatures managed
  by `sbctl` (not reverted by the script).

---
[← Previous: USE flags & package.use](07-use-flags.md) · [Handbook index](README.md) · [Next: sysctl hardening →](09-sysctl-hardening.md)

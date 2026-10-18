# AppArmor

> Install AppArmor and enable its service, so per-program security profiles can confine
> what each application is allowed to touch. Mirrors the script's step 14 (`--apparmor`),
> which is opt-in because it only works once the kernel LSM is turned on.

> **Warning:** **AppArmor does nothing until the kernel LSM is enabled.** It requires
> `CONFIG_SECURITY_APPARMOR=y` in your kernel *and* AppArmor listed in the active LSM
> set on the boot command line, followed by a reboot. Installing the package and
> enabling the service is only half the job; without the kernel side, `aa-status` will
> report that AppArmor is not loaded. Edit your bootloader carefully and keep a known-good
> boot entry so a bad kernel cmdline does not leave you unable to boot.

## What the script automates

`step_14_apparmor` is opt-in. It installs `sys-apps/apparmor` and
`sys-apps/apparmor-utils`, then *enables the `apparmor` service at boot* (it does not
start it immediately, because AppArmor cannot load profiles until the kernel LSM is
active and the machine has rebooted). It then prints the two things you must do
yourself: confirm kernel support and add `apparmor` to the `lsm=` kernel command line.
It writes no config files; the profile and LSM work is left to you and the kernel.

## Concepts

AppArmor is a **Linux Security Module (LSM)**: mandatory access control that confines
programs by *path*. Each confined program gets a **profile** listing exactly which
files, capabilities, and network operations it may use; anything outside the profile is
denied by the kernel regardless of Unix permissions. Compared with SELinux (label-based,
system-wide), AppArmor is path-based and profile-at-a-time, which is easier to reason
about per application.

Key vocabulary:

- **LSM stack.** Modern kernels load several LSMs at once. The active set is chosen by
  the `lsm=` boot parameter (or a kernel default). AppArmor must appear in that list, or
  its hooks are never registered and the daemon has nothing to load into.
- **Profile.** A file in `/etc/apparmor.d/` describing one program's allowed accesses.
  The `apparmor` service loads these profiles into the kernel at boot.
- **Enforce vs complain.** A profile in **enforce** mode blocks disallowed accesses and
  logs them. A profile in **complain** (learning) mode *allows* them but logs each one,
  so you can develop or debug a profile without breaking the program. You move profiles
  between modes with `aa-enforce` and `aa-complain`.
- **The service** (`apparmor`) is just the loader: on boot it parses `/etc/apparmor.d/`
  and pushes the profiles into the kernel. It is pointless until the LSM is active, which
  is why the script enables it but leaves starting it for after your reboot.

## Do it by hand

### 1. Install AppArmor and its tools

```bash
# root
emerge --ask=n --noreplace sys-apps/apparmor sys-apps/apparmor-utils
```

`sys-apps/apparmor` provides the base profiles and the `apparmor` init script/unit;
`sys-apps/apparmor-utils` provides the management tools (`aa-status`, `aa-enforce`,
`aa-complain`, `aa-genprof`, `aa-logprof`). `--noreplace` keeps the install idempotent,
matching the script's `emerge_install` helper.

### 2. Confirm kernel support

AppArmor needs `CONFIG_SECURITY_APPARMOR=y` compiled in. Most Gentoo dist-kernels enable
it; check your running config:

```bash
# root
zgrep -E 'CONFIG_SECURITY_APPARMOR|CONFIG_LSM' /proc/config.gz 2>/dev/null \
  || grep -E 'CONFIG_SECURITY_APPARMOR|CONFIG_LSM' /boot/config-"$(uname -r)"
```

If `CONFIG_SECURITY_APPARMOR` is not `y`, you must rebuild your kernel with it enabled
(see [kernel & microcode](08-kernel-microcode.md)) before AppArmor can do anything.

### 3. Enable the service (do not expect it to work yet)

The script enables `apparmor` at boot but deliberately does *not* start it now, because
it cannot load profiles until the LSM is active after a reboot:

```bash
# root - systemd
systemctl enable apparmor

# root - OpenRC (boot runlevel, so profiles load early)
rc-update add apparmor boot
```

Note this differs from most services in the handbook: there is no "start now" here. The
OpenRC runlevel is `boot` (not `default`) so profiles are loaded before normal services
come up.

### 4. **Warning:** Add AppArmor to the kernel command line

AppArmor only registers its hooks if it is in the active LSM list. Add it to your
bootloader's kernel cmdline. The script recommends this full, ordered set:

```text
lsm=landlock,lockdown,yama,integrity,apparmor,bpf
```

For **GRUB**, add it to `GRUB_CMDLINE_LINUX` in `/etc/default/grub`, then regenerate:

```bash
# root - example; edit the line, keeping any existing parameters
# GRUB_CMDLINE_LINUX="... lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
grub-mkconfig -o /boot/grub/grub.cfg
```

For **systemd-boot**, append the same `lsm=...` token to the `options` line of your
entry in `/boot/loader/entries/*.conf`. Order in the `lsm=` list is the load order; keep
`apparmor` in it alongside the other modules your system already uses so you do not
accidentally drop one.

### 5. Reboot, then start enforcing

```bash
# root
reboot
# after reboot, the enabled service loads profiles automatically; or start it once:
systemctl start apparmor      # systemd
rc-service apparmor start     # OpenRC
```

New profiles usually start in enforce mode. To develop or debug one without breaking the
program, switch it to complain mode first, exercise the program, then enforce:

```bash
# root
aa-complain /etc/apparmor.d/usr.bin.someprogram   # learning mode (logs, allows)
aa-enforce  /etc/apparmor.d/usr.bin.someprogram   # enforce mode (blocks + logs)
```

## Verify

```bash
# root
aa-status
```

A working setup reports `apparmor module is loaded` and lists how many profiles are
loaded, in enforce mode, and in complain mode. If it instead says AppArmor is *not*
loaded, the LSM is not active: recheck step 4 and confirm the running cmdline:

```bash
# root
cat /proc/cmdline        # should contain your lsm=...,apparmor,... token
```

Service state:

```bash
# systemd
systemctl is-enabled apparmor
# OpenRC
rc-update show | grep apparmor
```

## Pitfalls and rollback

- **Warning:** **Enabled but never loaded.** The commonest mistake: package installed, service
  enabled, but `apparmor` missing from `lsm=` (or no kernel support), so `aa-status`
  shows nothing loaded. Fix the cmdline and reboot.
- **Dropping other LSMs.** Setting `lsm=apparmor` alone silently disables `yama`,
  `lockdown`, etc. Include the full set your system expects, as shown.
- **A profile breaks an app.** Switch that profile to `aa-complain`, reproduce the
  issue, and use `aa-logprof` to refine it, rather than disabling AppArmor wholesale.
- **Bad kernel cmdline → unbootable.** A typo in the bootloader options can stop the
  machine booting. Keep a previous/known-good boot entry and test before relying on it.
- **Rollback:** AppArmor is not in the script's `--rollback` managed-file list, so
  rollback leaves it alone. To undo by hand, remove it from the kernel cmdline (reverse
  step 4 and regenerate the bootloader config), then disable the service:
  ```bash
  # systemd
  systemctl disable apparmor
  # OpenRC
  rc-update del apparmor boot
  # optional: remove the packages
  emerge --ask=n --depclean sys-apps/apparmor sys-apps/apparmor-utils
  ```
  Removing `apparmor` from `lsm=` and rebooting is what actually turns enforcement off;
  disabling the service and unmerging are cleanup.

## Script reference

- **Step:** `14` - `step_14_apparmor` (opt-in)
- **Flags:** `--apparmor`
- **Managed files:** none (the step installs packages and enables the `apparmor`
  service; the `lsm=` kernel cmdline and the profiles in `/etc/apparmor.d/` are left to
  you)

---
[← Previous: USBGuard](14-usbguard.md) · [Handbook index](README.md) · [Next: Shell & terminal →](16-shell-terminal.md)

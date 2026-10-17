# The base install (recap)

> A condensed map of the base install that happens *before* this handbook and the
> script begin. The official Gentoo Handbook is the authoritative source; this is
> orientation, not a replacement.

## Where the script picks up

`gentoo-post-install.sh` is a **post**-install tool. It assumes you already have a
booted Gentoo system with a working Portage. Everything from chapter 02 onward tunes,
hardens, and furnishes that system. This chapter recaps how you got there so the
handbook reads end to end, but for the real, maintained, hardware-specific steps,
follow the official
[Handbook:AMD64](https://wiki.gentoo.org/wiki/Handbook:AMD64) (or your architecture).

**Warning:** Partitioning and bootloader steps **erase data and decide whether the machine
boots**. Do them from the official Handbook with your exact disk layout in front of
you. The commands below are illustrative, not copy-paste-for-your-machine.

## The base install in ten moves

1. **Boot the install medium** (the Gentoo minimal ISO or any live Linux) and get
   network up (`ping gentoo.org`). Wired DHCP usually just works; for Wi-Fi use
   `iwctl` / `wpa_supplicant`.

2. **Partition the disk.** On UEFI you need a GPT disk with an EFI System Partition
   (FAT32, ~512 MiB, mounted at `/efi` or `/boot`), plus root (and optionally swap).
   Tools: `fdisk`, `gdisk`, `parted`. Decide on a filesystem (ext4 is the safe
   default; btrfs/xfs/ZFS are options).

3. **Create and mount filesystems.**
   ```bash
   mkfs.vfat -F32 /dev/sdXP   # EFI partition
   mkfs.ext4 /dev/sdXR        # root
   mount /dev/sdXR /mnt/gentoo
   ```

4. **Unpack a stage3 tarball** into the root. Download the current stage3 (choose
   OpenRC or systemd here; this is a lasting decision), verify it, then:
   ```bash
   tar xpvf stage3-*.tar.xz --xattrs-numeric-owner -C /mnt/gentoo
   ```

5. **Prepare and enter the chroot.** Copy DNS info, mount the kernel pseudo-filesystems
   (`/proc`, `/sys`, `/dev`, `/run`), then `chroot`:
   ```bash
   cp -L /etc/resolv.conf /mnt/gentoo/etc/
   mount --types proc /proc /mnt/gentoo/proc
   mount --rbind /sys /mnt/gentoo/sys && mount --make-rslave /mnt/gentoo/sys
   mount --rbind /dev /mnt/gentoo/dev && mount --make-rslave /mnt/gentoo/dev
   chroot /mnt/gentoo /bin/bash && source /etc/profile
   ```
   From here on you are "inside" the new system. This is the point the script and the
   rest of this handbook consider "installed".

6. **Sync Portage and pick a profile.** `emerge-webrsync` (or `emerge --sync`), then
   `eselect profile list` / `set`. See [Syncing Portage](02-portage-sync-news.md).

7. **Configure `make.conf`** (timezone, locale, and the build settings). The handbook
   covers the build settings in detail in [Tuning make.conf](03-make-conf.md). Set
   your timezone (`/etc/timezone` + `emerge --config sys-libs/timezone-data`) and
   locale (`/etc/locale.gen` + `locale-gen` + `eselect locale`).

8. **Install a kernel.** The quickest path is a distribution kernel
   (`sys-kernel/gentoo-kernel-bin`); building from source is also covered later. This
   is exactly what the script's step 07 automates, detailed in
   [Kernel, microcode & Secure Boot](08-kernel-microcode.md).

9. **Write `/etc/fstab`**, set the **root password** (`passwd`), set the **hostname**,
   and configure **networking** for the installed system (e.g. `dhcpcd`, or
   NetworkManager if you will run a desktop).

10. **Install a bootloader** (GRUB or systemd-boot) and generate its config, then
    exit the chroot, unmount, and reboot into the new system:
    ```bash
    # GRUB on UEFI (example)
    emerge sys-boot/grub
    grub-install --target=x86_64-efi --efi-directory=/efi
    grub-mkconfig -o /boot/grub/grub.cfg
    ```

## After the reboot

You now have a minimal but booting Gentoo. That is where
[`gentoo-post-install.sh`](../../gentoo-post-install.sh) and chapter 02 of this
handbook take over: syncing, tuning `make.conf`, updating `@world`, adding tooling,
hardening, and (optionally) building a desktop.

## Script reference

This chapter maps to no single step; it is the state the script expects to find. The
script verifies it with `detect_distribution` (checks `/etc/gentoo-release` and that
`emerge` exists) before doing anything.

---
[← Previous: Prerequisites & philosophy](00-prerequisites.md) · [Handbook index](README.md) · [Next: Syncing Portage & reading news →](02-portage-sync-news.md)

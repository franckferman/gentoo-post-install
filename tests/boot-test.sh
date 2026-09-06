#!/usr/bin/env bash
#
# Local QEMU/KVM kernel boot-test for gentoo-post-install.
#
# Boots a kernel image headless with a tiny static-init initramfs and a chosen
# kernel command line, and asserts that the kernel reaches USERSPACE (a sentinel
# printed by PID 1) within a timeout. A panic, hang, or missing sentinel fails.
#
# This is the piece the unit/integration suites cannot cover: it proves that the
# hardened KSPP *command line* (lockdown=, init_on_alloc=, pti=on, ...) does not
# prevent a real kernel from booting. Testing a hardened *.config* still requires
# building gentoo-kernel from source with the config.d fragment (see README).
#
# It touches nothing on the host: everything is staged under a throwaway temp dir,
# no root is needed (the init mounts devtmpfs itself instead of using device nodes),
# and QEMU runs with -no-reboot so the guest exits on its own.
#
# Usage:
#   tests/boot-test.sh [--kernel PATH] [--cmdline "PARAMS"] [--timeout SEC]
#                      [--mem MB] [--no-kvm]
# Defaults: kernel = /boot/vmlinuz-$(uname -r) (or the newest /boot/vmlinuz-*),
#           cmdline = the gentoo-post-install KSPP hardening params + lockdown.
#
set -u

KERNEL=""
TIMEOUT=60
MEM=512
USE_KVM=auto
# The exact hardened command line gentoo-post-install would apply (_kernel_harden_cmdline).
HARDEN_CMDLINE="init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on slab_nomerge page_table_check=on vsyscall=none pti=on page_alloc.shuffle=1 lockdown=confidentiality"
EXTRA_CMDLINE="$HARDEN_CMDLINE"

while [ $# -gt 0 ]; do
    case "$1" in
        --kernel)  KERNEL="$2"; shift 2 ;;
        --cmdline) EXTRA_CMDLINE="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --mem)     MEM="$2"; shift 2 ;;
        --no-kvm)  USE_KVM=no; shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

command -v qemu-system-x86_64 >/dev/null || { echo "qemu-system-x86_64 not found" >&2; exit 3; }
command -v gcc  >/dev/null || { echo "gcc not found (needed for the static init)" >&2; exit 3; }
command -v cpio >/dev/null || { echo "cpio not found" >&2; exit 3; }

if [ -z "$KERNEL" ]; then
    KERNEL="/boot/vmlinuz-$(uname -r)"
    [ -f "$KERNEL" ] || KERNEL="$(find /boot -maxdepth 1 -name 'vmlinuz-*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)"
fi
[ -f "$KERNEL" ] || { echo "kernel image not found: $KERNEL" >&2; exit 3; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- tiny PID 1: mount devtmpfs, grab the console, print the sentinel, reboot ---
cat > "$WORK/init.c" <<'EOF'
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
int main(void) {
    mkdir("/dev", 0755);
    mount("devtmpfs", "/dev", "devtmpfs", 0, "");
    int fd = open("/dev/console", O_RDWR);
    if (fd >= 0) { dup2(fd, 0); dup2(fd, 1); dup2(fd, 2); }
    static const char msg[] = "GPI_BOOT_OK userspace reached as PID1\n";
    write(1, msg, sizeof(msg) - 1);
    sync();
    reboot(RB_AUTOBOOT);   /* QEMU -no-reboot makes the guest exit here */
    for (;;) pause();
    return 0;
}
EOF

echo "==> building static /init"
gcc -static -Os -s -o "$WORK/init" "$WORK/init.c" || { echo "static build failed" >&2; exit 4; }

echo "==> packing initramfs"
mkdir -p "$WORK/root/dev"
cp "$WORK/init" "$WORK/root/init"
( cd "$WORK/root" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -9 ) > "$WORK/initramfs.gz"

KVM_ARGS=()
if [ "$USE_KVM" != no ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_ARGS=(-enable-kvm -cpu host)
    echo "==> acceleration: KVM"
else
    echo "==> acceleration: TCG (no KVM access) - slower"
fi

APPEND="console=ttyS0 panic=1 rdinit=/init ${EXTRA_CMDLINE}"
echo "==> kernel : $KERNEL"
echo "==> cmdline: $APPEND"
echo "==> booting (timeout ${TIMEOUT}s)..."
echo "---------------------------------------------------------------"
OUT="$WORK/serial.log"
timeout --foreground "$TIMEOUT" \
    qemu-system-x86_64 "${KVM_ARGS[@]}" \
        -no-reboot -nographic -m "$MEM" \
        -kernel "$KERNEL" -initrd "$WORK/initramfs.gz" \
        -append "$APPEND" 2>&1 | tee "$OUT"
echo "---------------------------------------------------------------"

if grep -q 'GPI_BOOT_OK userspace reached' "$OUT"; then
    echo "RESULT: PASS - kernel booted to userspace with this command line."
    exit 0
else
    echo "RESULT: FAIL - sentinel not seen (panic, hang, or console issue)."
    echo "Last serial lines:"; tail -n 15 "$OUT" | sed 's/^/  /'
    exit 1
fi

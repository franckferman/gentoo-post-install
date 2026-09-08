#!/usr/bin/env bash
#
# Dry-run smoke matrix for gentoo-post-install.
# Exercises representative full flag combinations END TO END in --dry-run (which
# makes no changes and must succeed on any host). Each invocation must exit 0.
# Complements the pure-function unit tests and the fake-root integration suite by
# driving the real main() through the kernel, accounts, desktop, and opsec paths.
#
# Usage: bash tests/smoke.sh
#
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/../gentoo-post-install.sh"

# Each entry: a label, then the args. All run with --dry-run --yes --no-banner.
RUNS=(
  "kernel-hardened|--install-kernel --kernel-source dist --kernel-config hardened --kernel-lockdown --kernel-cmdline-harden --bootloader grub --initramfs dracut --microcode --secure-boot"
  "kernel-bin-perf|--install-kernel --kernel-source bin --kernel-config performance --bootloader systemd-boot"
  "kernel-source-minimal|--install-kernel --kernel-source source --kernel-config minimal --kernel-manual"
  "accounts|--user alice:sudo:groups=audio,video:shell=/bin/zsh --user bob:sudo:nopasswd --group devs --root-password --disable-root"
  "desktop-kde|--de kde --dm sddm --display wayland --apps firefox,vlc,discord --steam --overlay guru --nerd-fonts JetBrainsMono"
  "desktop-sway|--de sway --dm greetd --display wayland --editor neovim --shell"
  "opsec-full|--profile opsec --minimize-surface --logs ephemeral --firewall nftables --ssh-harden --ssh-key-only --ssh-port 2222 --usbguard --apparmor"
  "server-iptables|--profile server --firewall iptables --binhost --no-sync --hardened-malloc"
  "desktop-fw-lan|--profile desktop --firewall nftables --firewall-lan --de kde --dm sddm"
  "steps-subset|--steps 2,6,8,21 --sysctl-harden --harden-ipv6"
)

PASS=0; FAIL=0
for entry in "${RUNS[@]}"; do
    label="${entry%%|*}"; args="${entry#*|}"
    # shellcheck disable=SC2086  # args is an intentional word-split flag string
    if bash "$SCRIPT" --dry-run --yes --no-banner $args >/dev/null 2>&1; then
        printf '  ok   %-22s\n' "$label"; PASS=$((PASS+1))
    else
        rc=$?
        printf '  FAIL %-22s (rc=%s)\n' "$label" "$rc"; FAIL=$((FAIL+1))
        # Re-run showing the tail so a CI failure is diagnosable.
        # shellcheck disable=SC2086
        bash "$SCRIPT" --dry-run --yes --no-banner $args 2>&1 | tail -4 | sed 's/^/       /'
    fi
done

echo
if [ "$FAIL" -eq 0 ]; then
    echo "All ${PASS} smoke invocations passed."; exit 0
else
    echo "${FAIL}/$((PASS+FAIL)) smoke invocations FAILED."; exit 1
fi

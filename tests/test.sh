#!/usr/bin/env bash
#
# Test suite for gentoo-post-install.
# Sources the script as a library (GPI_LIB=1, so main() does not run) and checks
# the pure/config functions with all external commands mocked. Runs as a normal
# user; makes no real system changes.
#
# Usage: bash tests/test.sh
#
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/../gentoo-post-install.sh"

# ---------------------------------------------------------------------------
# Mock external commands on PATH so nothing touches the real system.
# ---------------------------------------------------------------------------
MOCKBIN="$(mktemp -d)"
trap 'rm -rf "$MOCKBIN"' EXIT
for c in emerge systemctl rc-update rc-service chsh sudo doas getuto eix-update \
         eselect nft iptables ufw sysctl fc-cache; do
    printf '#!/bin/sh\nexit 0\n' > "${MOCKBIN}/${c}"
    chmod +x "${MOCKBIN}/${c}"
done
# Deterministic hybrid-GPU lspci for _detect_video_cards.
cat > "${MOCKBIN}/lspci" <<'EOF'
#!/bin/sh
echo "00:02.0 VGA compatible controller: Intel Corporation Iris Xe Graphics"
echo "01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi"
EOF
chmod +x "${MOCKBIN}/lspci"
export PATH="${MOCKBIN}:${PATH}"

# ---------------------------------------------------------------------------
# Load the script as a library.
# ---------------------------------------------------------------------------
# shellcheck source=/dev/null
GPI_LIB=1 source "$SCRIPT"

# ---------------------------------------------------------------------------
# Tiny harness.
# ---------------------------------------------------------------------------
TESTS=0
FAILS=0
check_eq() { # desc expected actual
    TESTS=$((TESTS + 1))
    if [ "$2" = "$3" ]; then
        printf '  ok   %s\n' "$1"
    else
        FAILS=$((FAILS + 1))
        printf '  FAIL %s\n         expected: [%s]\n           actual: [%s]\n' "$1" "$2" "$3"
    fi
}
check_rc() { # desc expected_rc actual_rc
    TESTS=$((TESTS + 1))
    if [ "$2" = "$3" ]; then
        printf '  ok   %s\n' "$1"
    else
        FAILS=$((FAILS + 1))
        printf '  FAIL %s (expected rc %s, got %s)\n' "$1" "$2" "$3"
    fi
}

echo "== parse_args =="
check_eq "profile server"        server   "$( parse_args --profile server  >/dev/null 2>&1; echo "$SYSTEM_PROFILE" )"
check_eq "binhost flag"          true     "$( parse_args --binhost          >/dev/null 2>&1; echo "$ENABLE_BINHOST" )"
check_eq "firewall iptables"     iptables "$( parse_args --firewall iptables>/dev/null 2>&1; echo "$FIREWALL" )"
check_eq "jobs number"           4        "$( parse_args --jobs 4           >/dev/null 2>&1; echo "$MAKEOPTS_JOBS" )"
check_eq "dry-run short flag"    true     "$( parse_args -n                 >/dev/null 2>&1; echo "$DRY_RUN" )"
check_eq "ssh-key-only sets both" "true true" "$( parse_args --ssh-key-only >/dev/null 2>&1; echo "$SSH_KEY_ONLY $HARDEN_SSH" )"
check_eq "editor choice"         neovim   "$( parse_args --editor neovim    >/dev/null 2>&1; echo "$EDITOR_CHOICE" )"
check_eq "bootloader systemd-boot" systemd-boot "$( parse_args --bootloader systemd-boot >/dev/null 2>&1; echo "$BOOTLOADER" )"
check_eq "initramfs none"        none     "$( parse_args --initramfs none   >/dev/null 2>&1; echo "$INITRAMFS" )"
check_eq "accept-license redist" redist   "$( parse_args --accept-license redist >/dev/null 2>&1; echo "$ACCEPT_LICENSE_MODE" )"
( parse_args --bootloader bad ) >/dev/null 2>&1; check_rc "bad --bootloader exits 2" 2 "$?"
( parse_args --nope )      >/dev/null 2>&1; check_rc "unknown option exits 2" 2 "$?"
( parse_args --march bad ) >/dev/null 2>&1; check_rc "bad --march exits 2"    2 "$?"

echo "== profile defaults + flag override (apply-then-parse order) =="
check_eq "hardened sets apparmor"          true  "$( SYSTEM_PROFILE=hardened; _apply_profile >/dev/null 2>&1; parse_args >/dev/null 2>&1; echo "$INSTALL_APPARMOR" )"
check_eq "flag overrides profile default"  false "$( SYSTEM_PROFILE=hardened; _apply_profile >/dev/null 2>&1; parse_args --no-fail2ban >/dev/null 2>&1; echo "$INSTALL_FAIL2BAN" )"
check_eq "desktop profile => shell on"     true  "$( SYSTEM_PROFILE=desktop;  _apply_profile >/dev/null 2>&1; parse_args >/dev/null 2>&1; echo "$INSTALL_SHELL" )"

echo "== parse_step_selection =="
check_eq "range + list" "01 03 04 05 07 " "$( parse_step_selection "1,3-5,7" >/dev/null 2>&1; echo "$SELECTED_STEPS" )"
check_eq "single step"  "05 "             "$( parse_step_selection "5"        >/dev/null 2>&1; echo "$SELECTED_STEPS" )"
check_eq "dedup + sort" "01 02 "          "$( parse_step_selection "2,1,2,1"  >/dev/null 2>&1; echo "$SELECTED_STEPS" )"
( parse_step_selection "x" ) >/dev/null 2>&1; check_rc "invalid selection exits 2" 2 "$?"
( parse_step_selection "99" )    >/dev/null 2>&1; check_rc "step above range exits 2"   2 "$?"
( parse_step_selection "0" )     >/dev/null 2>&1; check_rc "step zero exits 2"          2 "$?"
( parse_step_selection "24" )    >/dev/null 2>&1; check_rc "one past last step exits 2" 2 "$?"
( parse_step_selection "20-99" ) >/dev/null 2>&1; check_rc "range past end exits 2"     2 "$?"
check_eq "zero-padded 08 not octal" "08 " "$( parse_step_selection "08" >/dev/null 2>&1; echo "$SELECTED_STEPS" )"

echo "== make_conf_set (idempotent) =="
tmp="$(mktemp)"
# These globals are consumed by the sourced library functions (make_conf_set / run_priv);
# ShellCheck cannot see across the dynamic `source`, hence the disables.
# shellcheck disable=SC2034
MAKE_CONF="$tmp"
DRY_RUN=false
# shellcheck disable=SC2034
PRIV=""
: > "$tmp"
make_conf_set MAKEOPTS "-j4" >/dev/null 2>&1
check_eq "append new key"        'MAKEOPTS="-j4"' "$(grep MAKEOPTS "$tmp")"
make_conf_set MAKEOPTS "-j8" >/dev/null 2>&1
check_eq "replace existing key"  'MAKEOPTS="-j8"' "$(grep MAKEOPTS "$tmp")"
check_eq "no duplicate lines"    1                "$(grep -c MAKEOPTS "$tmp")"
rm -f "$tmp" "${tmp}.gpi.bak"

echo "== app mapping =="
check_eq "firefox -> atom"        "www-client/firefox-bin||" "$(_app_spec firefox)"
check_eq "chrome -> license"      "www-client/google-chrome||google-chrome" "$(_app_spec chrome)"
check_eq "obsidian -> r7l"        "app-text/obsidian|r7l|" "$(_app_spec obsidian)"
check_eq "discord -> in-tree"     "net-im/discord||" "$(_app_spec discord)"
check_eq "signal -> in-tree"      "net-im/signal-desktop-bin||" "$(_app_spec signal)"
check_eq "raw atom passthrough"   "media-video/vlc||" "$(_app_spec media-video/vlc)"
check_eq "unknown app -> empty"   "" "$(_app_spec definitely-not-an-app)"
check_eq "apps-profile daily"     "firefox vlc keepassxc" "$(_apps_profile_list daily)"
check_eq "apps-profile gaming has steam" "discord steam" "$(_apps_profile_list gaming)"
check_eq "apps-profile unknown"   "" "$(_apps_profile_list nope)"

echo "== desktop environment / display manager maps =="
check_eq "kde -> plasma-meta"     "kde-plasma/plasma-meta" "$(_de_package kde)"
check_eq "sway -> gui-wm/sway"    "gui-wm/sway" "$(_de_package sway)"
check_eq "kde default dm sddm"    "sddm" "$(_default_dm_for_de kde)"
check_eq "sway default dm greetd" "greetd" "$(_default_dm_for_de sway)"
check_eq "gdm package"            "gnome-base/gdm" "$(_dm_package gdm)"
check_eq "greetd package set"     "gui-libs/greetd gui-apps/tuigreet" "$(_dm_package greetd)"

echo "== list_apps / list_overlays =="
check_eq "list_apps has firefox"   1 "$(list_apps | grep -c 'firefox')"
check_eq "list_apps has steam"     1 "$(list_apps | grep -c 'steam-overlay')"
check_eq "list_overlays has guru"  1 "$(list_overlays | grep -c '^  guru ')"

echo "== kernel source map =="
check_eq "bin -> gentoo-kernel-bin" "sys-kernel/gentoo-kernel-bin" "$(_kernel_pkg_for_source bin)"
check_eq "dist -> gentoo-kernel"    "sys-kernel/gentoo-kernel" "$(_kernel_pkg_for_source dist)"
check_eq "source -> gentoo-sources" "sys-kernel/gentoo-sources" "$(_kernel_pkg_for_source source)"
check_eq "vanilla -> vanilla-sources" "sys-kernel/vanilla-sources" "$(_kernel_pkg_for_source vanilla)"

echo "== kernel hardening fragment =="
check_eq "KSPP toggle present"     1 "$( KERNEL_LOCKDOWN=false; _kernel_hardening_fragment | grep -c 'CONFIG_GENTOO_KERNEL_SELF_PROTECTION=y' )"
check_eq "no lockdown by default"  0 "$( KERNEL_LOCKDOWN=false; _kernel_hardening_fragment | grep -c 'LOCKDOWN' )"
# KERNEL_LOCKDOWN is consumed by the sourced _kernel_hardening_fragment.
# shellcheck disable=SC2034
check_eq "lockdown when opted in"  1 "$( KERNEL_LOCKDOWN=true;  _kernel_hardening_fragment | grep -c 'CONFIG_SECURITY_LOCKDOWN_LSM=y' )"

echo "== _parse_user_spec =="
check_eq "full spec"      "alice|true|false|audio,video|/bin/zsh" "$(_parse_user_spec 'alice:sudo:groups=audio,video:shell=/bin/zsh')"
check_eq "bare name"      "bob|false|false||/bin/bash" "$(_parse_user_spec 'bob')"
check_eq "sudo+nopasswd"  "carol|true|true||/bin/bash" "$(_parse_user_spec 'carol:sudo:nopasswd')"


echo "== account safety guards =="
# _set_password must NOT block or set an empty password when stdin is not a tty.
DRY_RUN=false
out="$( _set_password bob "password for bob" </dev/null 2>&1 )"; rc=$?
check_rc "non-tty _set_password returns 0 (skips, no hang)" 0 "$rc"
check_eq "non-tty _set_password warns to set it later" 1 "$(grep -c 'passwd bob' <<< "$out")"
# _disable_root refuses when wheel has no non-root member (lock-out guard).
getent() { echo "wheel:x:10:root"; }   # only root in wheel
( _disable_root >/dev/null 2>&1 ); check_rc "_disable_root refuses with no non-root wheel member" 1 "$?"
getent() { echo "wheel:x:10:root,alice"; }  # a real admin exists
check_rc "_disable_root proceeds (dry-run) with a non-root wheel member" 0 "$( DRY_RUN=true; _disable_root >/dev/null 2>&1; echo $? )"
unset -f getent
DRY_RUN=false


echo "== rollback removes managed sudoers grants only =="
sdir="$(mktemp -d)"
# shellcheck disable=SC2034  # consumed by the sourced _rollback_sudoers
SUDOERS_DIR="$sdir"
printf '# Managed by gentoo-post-install\n%%wheel ALL=(ALL:ALL) ALL\n'        > "$sdir/00-gpi-wheel"
printf '# Managed by gentoo-post-install\nalice ALL=(ALL:ALL) NOPASSWD: ALL\n' > "$sdir/10-gpi-alice"
printf '# hand-written, not ours\nbob ALL=(ALL) ALL\n'                         > "$sdir/99-custom"
DRY_RUN=false
_rollback_sudoers >/dev/null 2>&1
_present() { [ -e "$1" ] && echo present || echo absent; }
check_eq "managed wheel grant removed"    absent  "$(_present "$sdir/00-gpi-wheel")"
check_eq "managed nopasswd grant removed" absent  "$(_present "$sdir/10-gpi-alice")"
check_eq "unmanaged sudoers file kept"    present "$(_present "$sdir/99-custom")"
rm -rf "$sdir"
# shellcheck disable=SC2034
SUDOERS_DIR=/etc/sudoers.d

echo "== _write_zshrc reflects --editor choice =="
zhome="$(mktemp -d)"
# TARGET_USER/TARGET_HOME/EDITOR_CHOICE are consumed by the sourced _write_zshrc.
# shellcheck disable=SC2034
{ TARGET_USER="$(id -un)"; TARGET_HOME="$zhome"; DRY_RUN=false; }
EDITOR_CHOICE=neovim; _write_zshrc >/dev/null 2>&1
check_eq "neovim -> EDITOR=nvim" "export EDITOR='nvim'" "$(grep '^export EDITOR=' "${zhome}/.zshrc")"
EDITOR_CHOICE=vim;    _write_zshrc >/dev/null 2>&1
check_eq "vim -> EDITOR=vim"     "export EDITOR='vim'"  "$(grep '^export EDITOR=' "${zhome}/.zshrc")"
rm -rf "$zhome"


echo "== nftables ruleset + --firewall-lan =="
# ALLOW_SSH/SSH_PORT are consumed by the sourced _nftables_ruleset.
# shellcheck disable=SC2034
{ ALLOW_SSH=true; SSH_PORT=22; }
# Prefix-assign FIREWALL_LAN per call (visible to the function, shellcheck-clean).
_nft() { FIREWALL_LAN="$1" _nftables_ruleset; }
check_eq "strict: ssh rule present"      1 "$(_nft false | grep -c 'tcp dport 22 accept')"
check_eq "strict: no mDNS"               0 "$(_nft false | grep -c 'dport 5353')"
check_eq "lan: mDNS present"             1 "$(_nft true  | grep -c 'udp dport 5353')"
check_eq "lan: SSDP present"             1 "$(_nft true  | grep -c 'udp dport 1900')"
check_eq "lan: KDE Connect (tcp+udp)"    2 "$(_nft true  | grep -c '1714-1764')"
check_eq "lan: input still default-deny" 1 "$(_nft true  | grep -c 'hook input priority filter; policy drop')"


echo "== detect_multilib =="
# DISTRO_PROFILE is consumed by the sourced detect_multilib; ShellCheck can't see across it.
# shellcheck disable=SC2034
check_eq "no-multilib profile -> no" no  "$( DISTRO_PROFILE='default/linux/amd64/23.0/no-multilib'; detect_multilib; echo "$MULTILIB" )"
# shellcheck disable=SC2034
check_eq "desktop profile -> yes"    yes "$( DISTRO_PROFILE='default/linux/amd64/23.0/desktop'; detect_multilib; echo "$MULTILIB" )"

echo "== _detect_video_cards =="
check_eq "intel + amd detected" "intel amdgpu radeonsi" "$(_detect_video_cards)"

echo "== documentation guard (every parse_args flag is in --help AND the man page) =="
help_text="$(show_help 2>/dev/null)"
# Unescape mdoc hyphens (\-) and drop font codes (\fB \fR ...) so flags match literally.
man_text="$(sed 's/\\-/-/g; s/\\f[A-Z]//g' "${HERE}/../gentoo-post-install.1" 2>/dev/null)"
undoc_help=""; undoc_man=""
# The flag pattern allows digits (e.g. --fail2ban, --harden-ipv6); each flag must be
# followed by a non-flag char so a prefix (--shell) is not satisfied by a longer one
# (--shell-user).
while IFS= read -r f; do
    [ -z "$f" ] && continue
    grep -qE -- "${f}([^a-z0-9-]|\$)" <<< "$help_text" || undoc_help="${undoc_help} ${f}"
    grep -qE -- "${f}([^a-z0-9-]|\$)" <<< "$man_text"  || undoc_man="${undoc_man} ${f}"
done < <(grep -oE '[-][-][a-z][a-z0-9-]+\)' "$SCRIPT" | sed 's/)//' | sort -u)
check_eq "no flags missing from --help"   "" "${undoc_help# }"
check_eq "no flags missing from man page" "" "${undoc_man# }"

echo
echo "== full dry-run works with no privileges and no Portage (CI / non-Gentoo) =="
# Reproduces the CI runner (and any non-Gentoo host): a --dry-run makes no changes and
# must preview anywhere, so it must not require root/sudo/doas or emerge. Runs the real
# script end-to-end as a subprocess under a minimal PATH and asserts rc=0.
nogentoo="$(mktemp -d)"
for _t in bash sh cat grep sed awk sort uniq head tail tr cut printf echo env mktemp id uname \
          nproc tee mkdir rm cp mv ln find wc date dirname basename getent free lscpu true false \
          sleep chmod stat readlink realpath tput column comm paste xargs; do
    _p="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_p" "${nogentoo}/${_t}"
done
env -i PATH="$nogentoo" HOME="$HOME" TERM=dumb bash "$SCRIPT" --dry-run --yes --no-banner --profile hardened >/dev/null 2>&1
check_rc "dry-run rc=0 with no sudo/emerge on PATH" 0 "$?"
rm -rf "$nogentoo"

if [ "$FAILS" -eq 0 ]; then
    echo "All ${TESTS} tests passed."
    exit 0
else
    echo "${FAILS}/${TESTS} tests FAILED."
    exit 1
fi

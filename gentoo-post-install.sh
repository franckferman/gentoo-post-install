#!/bin/bash

: '
Gentoo Post-Installation Script

Automates post-install configuration, Portage configuration, hardening, and tooling
setup for Gentoo Linux with profile-based defaults. Supports both OpenRC and
systemd, source and binary (binhost) package flows.

Companion projects:
  - Debian Server : github.com/franckferman/debian-server-post-install
  - Ubuntu Desktop: github.com/franckferman/ubuntu-post-install
  - Windows       : github.com/franckferman/win-postinstall

Author  : Franck FERMAN
Created : 04/09/2026
Updated : 04/09/2026
Version : 1.0.0
'

set -o pipefail

# ==============================================
# CONSTANTS
# ==============================================
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="Gentoo Post-Installation Script"

readonly EXIT_SUCCESS=0
readonly EXIT_FAILURE=1
readonly EXIT_USAGE=2

# Paths (env-overridable, e.g. for tests or a chroot target)
MAKE_CONF="${MAKE_CONF:-/etc/portage/make.conf}"
PKG_USE_DIR="${PKG_USE_DIR:-/etc/portage/package.use}"
PKG_ACCEPT_DIR="${PKG_ACCEPT_DIR:-/etc/portage/package.accept_keywords}"
PKG_LICENSE_DIR="${PKG_LICENSE_DIR:-/etc/portage/package.license}"
BINREPOS_DIR="${BINREPOS_DIR:-/etc/portage/binrepos.conf}"
# Optional prefix for the absolute-path drop-ins written by write_root_file (sysctl.d,
# modprobe.d, kernel config.d, ssh, ...). Empty in a normal run; the integration tests
# set it to redirect those writes under a temp tree so their content can be asserted
# without touching the host. It does not cover the make.conf/package.* paths above
# (those have their own overrides) nor the few tee -a appends, so it is a staging hook,
# not a complete chroot installer.
GPI_SYSROOT="${GPI_SYSROOT:-}"
SUDOERS_DIR="${SUDOERS_DIR:-/etc/sudoers.d}"

# ----------------------------------------------
# URLs
# ----------------------------------------------
URL_POWERLEVEL10K="https://github.com/romkatv/powerlevel10k.git"
URL_PLUGIN_AUTOSUGGESTIONS="https://github.com/zsh-users/zsh-autosuggestions"
URL_PLUGIN_SYNTAX_HIGHLIGHTING="https://github.com/zsh-users/zsh-syntax-highlighting"
URL_PLUGIN_COMPLETIONS="https://github.com/zsh-users/zsh-completions"
# Official Gentoo binary package host (amd64, 23.0 profile). Overridable via --binhost-uri.
URL_GENTOO_BINHOST="https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64"

# ==============================================
# GLOBAL CONFIGURATION (defaults; overridden by profile + flags)
# ==============================================
USE_EMOJIS=true
ICON_INFO=""
ICON_OK=""
ICON_SKIP=""
ICON_WARN=""
ICON_ERR=""
SEPARATOR="-----------------------------"

SELECTED_STEPS=""
ASSUME_YES=false
DRY_RUN=false
ALLOW_ROOT=false
NO_BANNER=false
LOG_FILE=""                 # when set, tee a timestamped transcript here
ROLLBACK=false             # --rollback: revert managed changes and exit

# Detected at runtime
DISTRO=""
DISTRO_PROFILE=""
MULTILIB="unknown"          # yes | no - 32-bit ABI availability (needed for Steam)
INIT_SYSTEM="unknown"       # openrc | systemd | unknown
PRIV=""                     # "" when already root, "sudo" otherwise
NPROC=1
RAM_GB=0

# Profile
SYSTEM_PROFILE="default"    # default | desktop | server | hardened | minimal | opsec

# Portage configuration
TUNE_MAKECONF=true
SET_MARCH_NATIVE=true
SET_CPU_FLAGS=true
SET_MAKEOPTS=true
MAKEOPTS_JOBS=""            # empty => auto
ACCEPT_LICENSE_MODE="default"  # default | free | all
EMERGE_QUIET=true

# Binary packages
ENABLE_BINHOST=false
BINHOST_URI="$URL_GENTOO_BINHOST"

# World / maintenance
DO_SYNC=true
DO_WORLD_UPDATE=true
DO_DEPCLEAN=true
RUN_MIRRORSELECT=false        # --mirrors: pick fastest GENTOO_MIRRORS
MERGE_CONFIG=false            # --merge-config: run dispatch-conf at the end (interactive)
DO_PRESERVED_REBUILD=true

# Tooling
INSTALL_TOOLING=true

# Kernel
INSTALL_KERNEL=false
KERNEL_SOURCE="bin"          # bin | dist | source | vanilla  (default bin: nothing breaks)
KERNEL_PKG=""                # explicit override; empty => derived from KERNEL_SOURCE
KERNEL_CONFIG="standard"     # standard | hardened | minimal | performance
KERNEL_LOCKDOWN=false        # opt-in: lockdown LSM (needs signed modules or monolithic)
KERNEL_CMDLINE_HARDEN=false  # opt-in: add KSPP params to the bootloader cmdline
KERNEL_MANUAL=false          # opt-in: leave configuration to menuconfig (no auto-build)
BOOTLOADER="grub"            # grub | systemd-boot | none  (sets installkernel USE)
INITRAMFS="dracut"           # dracut | none              (sets installkernel USE)
INSTALL_MICROCODE=false      # CPU microcode (Intel: intel-microcode; AMD: linux-firmware)

# Firewall
CONFIGURE_FIREWALL=false
FIREWALL="nftables"          # nftables | iptables | ufw | none
ALLOW_SSH=true               # keep an SSH allow rule so remote boxes don't lock out

# sysctl / kernel hardening
HARDEN_SYSCTL=false
HARDEN_IPV6=false            # when true, also apply IPv6 network hardening knobs

# SSH hardening
HARDEN_SSH=false
SSH_PORT=22
SSH_DISABLE_ROOT=false       # PermitRootLogin no  (careful on root-only boxes)
SSH_KEY_ONLY=false           # PasswordAuthentication no  (need a working key first!)

# Services & monitoring
INSTALL_AUDIT=false
INSTALL_SYSLOG=false
INSTALL_FAIL2BAN=false
INSTALL_USBGUARD=false        # opt-in only (can lock out USB input devices)
INSTALL_APPARMOR=false        # opt-in / hardened (needs kernel LSM support)
INSTALL_HARDENED_MALLOC=false # opt-in: sys-libs/hardened_malloc
MINIMIZE_SURFACE=false        # opt-in: blacklist risky modules, disable kexec/coredumps, mask extra services
LOGS_LEVEL="off"              # off | reduce | ephemeral  (log-footprint minimization)

# Accounts / sysops (passwords ALWAYS via chpasswd on stdin, never argv)
ROOT_PASSWORD=false           # --root-password: set root's password (masked prompt)
DISABLE_ROOT=false            # --disable-root: lock root (guarded: needs a wheel member)
NEW_GROUPS=""                 # --group (space list)
NEW_USERS=""                  # --user specs (newline-separated)

# Shell & terminal
INSTALL_SHELL=false
SHELL_USER=""                 # empty => auto (SUDO_USER, else current user)
EDITOR_CHOICE="both"          # vim | neovim | both | none
SET_DEFAULT_SHELL=true
TARGET_USER=""                # resolved at runtime
TARGET_HOME=""

# Extra clone URLs (shell)
URL_OHMYZSH_REPO="https://github.com/ohmyzsh/ohmyzsh.git"
URL_LAZYVIM="https://github.com/LazyVim/starter"

# Fonts
INSTALL_FONTS=false
NERD_FONTS_LIST="FiraCode JetBrainsMono Hack"
URL_NERD_FONTS_DL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"

# Desktop stack
INSTALL_DESKTOP=false
DESKTOP_DISPLAY="x11"          # x11 | wayland | both
DESKTOP_AUDIO=true             # PipeWire
DESKTOP_NM=true                # NetworkManager
VIDEO_CARDS_OVERRIDE=""        # manual VIDEO_CARDS value (skips autodetect)

# Overlays / repositories (native Gentoo way, via eselect-repository)
OVERLAYS=""                    # space/comma list: "guru" (official) or "name=git-url" (custom)

# Applications (native Portage; some need an overlay auto-enabled)
APPS=""                        # friendly names and/or raw cat/atom, space/comma list
APPS_PROFILE=""                # daily | dev | media | gaming
INSTALL_STEAM=false            # native Steam (steam-overlay + multilib + abi_x86_32)

# Desktop environment / display manager (fresh-install "make it graphical")
DE=""                          # kde | gnome | sway | hyprland | xfce | none
DM=""                          # sddm | gdm | lightdm | greetd | none | auto (default: per-DE)

# ==============================================
# LOGGING HELPERS
# ==============================================
_init_symbols() {
    if $USE_EMOJIS; then
        ICON_INFO="ℹ️ "
        ICON_OK="✅"
        ICON_SKIP="➡️ "
        ICON_WARN="⚠️ "
        ICON_ERR="❌"
    else
        ICON_INFO="[*]"
        ICON_OK="[+]"
        ICON_SKIP="[=]"
        ICON_WARN="[!]"
        ICON_ERR="[x]"
    fi
}

log_section() {
    echo ""
    echo "$SEPARATOR"
    echo "${ICON_INFO} $1"
    echo "$SEPARATOR"
}

log_info() { echo "${ICON_INFO} $*"; }
log_ok()   { echo "${ICON_OK} $*"; }
log_skip() { echo "${ICON_SKIP} $*"; }
log_warn() { echo "${ICON_WARN} $*" >&2; }
log_err()  { echo "${ICON_ERR} $*" >&2; }

die() {
    log_err "$1"
    exit "${2:-$EXIT_FAILURE}"
}

confirm() {
    # confirm "Question?" -> 0 yes / 1 no. Honors --yes.
    local prompt="$1"
    if $ASSUME_YES; then
        return 0
    fi
    local reply
    read -r -p "${ICON_WARN} ${prompt} [y/N] " reply
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ==============================================
# PRIVILEGE / EXECUTION HELPERS
# ==============================================
run_priv() {
    # Run a command with root privileges (transparently no-op prefix when root).
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] ${PRIV:+sudo }$*"
        return 0
    fi
    # shellcheck disable=SC2086
    ${PRIV} "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

# ==============================================
# BANNER
# ==============================================
show_banner() {
    $NO_BANNER && return 0
    local P='\033[0;35m'   # Gentoo purple
    local NC='\033[0m'
    if [[ "${TERM:-}" != "dumb" ]] && have tput && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
        echo -e "${P}"
    fi
    cat << "EOF"
                 -/oyddmNNMMMMMNmhys+:-
             -odm/````omMMMMMMMMMMMMMMmhs+-
           -sNMs```````+MMMMMMMMMMMMMMMMMMmy/
          /mMMMy````````yMMMMMMMMMMMMMMMMMMMMd/
         oNMMMMs`````````dMMMMMMMMMMMMMMMMMMMMMd
        :NMMMMMd``````````mMMMMMMMMMMMMMMMMMMMMMm
        yMMMMMMh``````````+MMMMMMMMMMMMMMMMMMMMMM-
        oMMMMMMs```````````yMMMMMMMMMMMMMMMMMMNs`
         yMMMMMy````````````sNMMMMMMMMMMMMNmy+`
          sMMMMh`````````````-ohmNMMMMNmho:`
           yMMMd``````````````````-::-`
            +NMh````````````````````
              +hs````````````````
                 -/osssso+:```
EOF
    if [[ "${TERM:-}" != "dumb" ]] && have tput && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
        echo -e "${NC}"
    fi
    echo "    ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo "    Portage configuration, hardening & tooling for Gentoo (OpenRC + systemd)"
    echo ""
}

# ==============================================
# HELP
# ==============================================
show_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Post-install automation for Gentoo Linux: Portage configuration, binhost, world
update, tooling, and (progressively) hardening & desktop/shell setup.
Supports both OpenRC and systemd.

USAGE:
    ./gentoo-post-install.sh [OPTIONS]
    sudo ./gentoo-post-install.sh --profile desktop

PROFILES:
    --profile <name>        default | desktop | server | hardened | minimal | opsec

GENERAL:
    -h, --help              Show this help and exit
    -v, --version           Show version and exit
    -y, --yes               Assume "yes" to all prompts (non-interactive)
    -n, --dry-run           Print actions without executing them
    --allow-root            Permit running directly as root without sudo
    --no-banner             Do not print the ASCII banner
    --no-emoji              Use ASCII status markers instead of emojis
    --log-file <path>       Tee a timestamped transcript to this file
    --steps <list>          Run only these steps (e.g. --steps 1,2,5 or 1-4)
    --list-steps            List all available steps and exit
    --list-apps             List known application names (for --apps) and exit
    --list-overlays         List popular overlays (for --overlay) and exit
    --rollback              Revert managed changes (restore make.conf, remove drop-ins)

PORTAGE CONFIGURATION:
    --no-tune               Do not modify ${MAKE_CONF}
    --march <mode>          native | none    (CPU baseline; default: native)
    --jobs <N>              Force MAKEOPTS -jN (default: auto from cores/RAM)
    --accept-license <m>    default | free | redist | all
    --no-cpu-flags          Do not compute CPU_FLAGS_X86 via cpuid2cpuflags

BINARY PACKAGES:
    --binhost               Enable Gentoo binary package host (getbinpkg)
    --binhost-uri <uri>     Override the binhost sync-uri

MAINTENANCE:
    --no-sync               Skip Portage tree sync
    --no-world-update       Skip 'emerge -uUDN @world'
    --no-depclean           Skip 'emerge --depclean'
    --mirrors               Pick the fastest GENTOO_MIRRORS (mirrorselect) before sync
    --merge-config          Run 'dispatch-conf' at the end (merge pending config updates)

KERNEL:
    --install-kernel        Install a kernel (default source: bin / gentoo-kernel-bin)
    --kernel-source <s>     bin | dist | source | vanilla
                            (gentoo-kernel-bin | gentoo-kernel | gentoo-sources | vanilla-sources)
    --kernel-pkg <atom>     Override the kernel package atom explicitly
    --kernel-config <c>     standard | hardened | minimal | performance
                            (hardened = KSPP; minimal = localmodconfig on source)
    --kernel-lockdown       Enable lockdown LSM (needs signed modules / monolithic!)
    --kernel-cmdline-harden Add KSPP parameters to the bootloader kernel cmdline
    --kernel-manual         Leave configuration to menuconfig (no auto-build)
    --bootloader <b>        grub | systemd-boot | none  (installkernel USE; default grub)
    --initramfs <i>         dracut | none               (installkernel USE; default dracut)
    --microcode             Install CPU microcode (Intel intel-microcode / AMD via firmware)

HARDENING:
    --sysctl-harden         Apply sysctl network/kernel hardening drop-in
    --harden-ipv6           Also apply IPv6 hardening knobs
    --firewall <backend>    nftables | iptables | ufw | none  (default: nftables)
    --no-ssh-rule           Do NOT auto-allow SSH in the firewall (risk of lockout)
    --ssh-harden            Write a hardened sshd_config.d drop-in
    --ssh-port <N>          SSH port (firewall allow + sshd Port); default 22
    --ssh-no-root           sshd: PermitRootLogin no
    --ssh-key-only          sshd: PasswordAuthentication no (need a working key!)

SERVICES & MONITORING:
    --audit                 Install sys-process/audit + a system logger
    --no-audit              Disable audit even if the profile enables it
    --fail2ban              Install fail2ban with an sshd jail
    --no-fail2ban           Disable fail2ban even if the profile enables it
    --usbguard              Install USBGuard (opt-in; can lock out USB input!)
    --apparmor              Install + enable AppArmor (needs kernel LSM support)
    --hardened-malloc       Install sys-libs/hardened_malloc (opt-in)
    --minimize-surface      Blacklist risky modules, disable kexec/coredumps, mask services
    --logs <level>          off | reduce | ephemeral  (log-footprint minimization)

ACCOUNTS (users / groups / root - passwords via chpasswd on stdin, never argv):
    --root-password         Set root's password (masked prompt)
    --disable-root          Lock root (guarded: needs a wheel member as fallback admin)
    --group <name>          Create a group (repeatable)
    --user <spec>           Create/adjust a user (repeatable). spec:
                            name[:sudo][:nopasswd][:groups=a,b][:shell=/bin/bash]
                            :sudo -> wheel + sudoers; :nopasswd -> NOPASSWD sudo (warned)

SHELL & TERMINAL:
    --shell                 Install zsh + oh-my-zsh + powerlevel10k + plugins
    --no-shell              Skip the shell setup (even if the profile enables it)
    --shell-user <name>     Configure for this user (default: sudo/current user)
    --editor <choice>       vim | neovim | both | none   (default: both)
    --no-chsh               Do not change the user's default shell to zsh

FONTS & DESKTOP:
    --fonts                 Install Nerd Fonts (${NERD_FONTS_LIST})
    --no-fonts              Skip Nerd Fonts (even if the profile enables them)
    --nerd-fonts <list>     Comma/space list of Nerd Fonts to install
    --desktop               Install a desktop stack (Xorg, dbus/elogind, PipeWire, NM)
    --display <choice>      x11 | wayland | both   (default: x11)
    --no-audio              Skip PipeWire
    --no-nm                 Skip NetworkManager
    --video-cards <value>   Set VIDEO_CARDS manually (skip autodetect)

REPOSITORIES (overlays, the native way):
    --overlay <list>        Enable official overlays (e.g. guru,pentoo) and/or add a
                            custom one as name=git-url (via eselect-repository)

APPLICATIONS (native Portage):
    --apps <list>           Install apps by name (firefox,vlc,obsidian,...) or raw atom;
                            an app's overlay (e.g. guru) is auto-enabled as needed
    --apps-profile <p>      daily | dev | media | gaming  (a ready-made app set)
    --steam                 Native Steam (steam-overlay + multilib + abi_x86_32)

DESKTOP ENVIRONMENT (make a fresh install graphical):
    --de <choice>           kde | gnome | sway | hyprland | xfce | none
    --dm <choice>           sddm | gdm | lightdm | greetd | none | auto (default: per-DE)

EXAMPLES:
    # Safe defaults, interactive
    sudo ./gentoo-post-install.sh

    # Desktop workstation, non-interactive, with binhost to speed things up
    sudo ./gentoo-post-install.sh --profile desktop --binhost -y

    # Only tune make.conf and install tooling, dry-run first
    sudo ./gentoo-post-install.sh --steps 2,4 --dry-run

    # Hardened server, keep licenses at Gentoo default
    sudo ./gentoo-post-install.sh --profile hardened --accept-license default

Project: github.com/franckferman/gentoo-post-install
EOF
}

# ==============================================
# STEP REGISTRY
# ==============================================
# Format: "NN|function|Short description"
# Only implemented steps are registered; more are added each iteration.
STEP_REGISTRY=(
    "01|step_01_sync_news|Sync Portage tree and read news"
    "02|step_02_portage_tuning|Configure make.conf (MAKEOPTS, flags, CPU flags, FEATURES)"
    "03|step_03_binhost|Configure binary package host (optional)"
    "04|step_04_portage_tooling|Install Portage tooling (gentoolkit, eix, ...)"
    "05|step_05_world_update|Update @world and clean dependencies"
    "06|step_06_use_flags|Seed sane global USE flags and package.use layout"
    "07|step_07_kernel|Install a distribution kernel + CPU microcode (optional)"
    "08|step_08_sysctl_hardening|Apply sysctl network/kernel hardening"
    "09|step_09_firewall|Configure firewall (nftables/iptables/ufw)"
    "10|step_10_ssh_hardening|Harden the OpenSSH server (sshd_config.d)"
    "11|step_11_audit_logging|Install audit + system logging"
    "12|step_12_fail2ban|Install and configure fail2ban (sshd jail)"
    "13|step_13_usbguard|Install USBGuard with a policy (opt-in)"
    "14|step_14_apparmor|Install and enable AppArmor (opt-in)"
    "15|step_15_shell|Shell & terminal: zsh + powerlevel10k + editors"
    "16|step_16_fonts|Install Nerd Fonts for the user"
    "17|step_17_desktop|Desktop stack: Xorg/Wayland, PipeWire, NetworkManager"
    "18|step_18_repositories|Enable overlays / extra ebuild repositories"
    "19|step_19_apps|Install applications (native Portage, overlay-aware)"
    "20|step_20_desktop_environment|Install a desktop environment + display manager"
    "21|step_21_minimize_surface|Minimize attack surface (modules, kexec, coredumps)"
    "22|step_22_logs|Minimize log footprint (journald, history, dmesg)"
    "23|step_23_accounts|Users, groups, sudo, and root password/lock"
)

list_steps() {
    echo "Available steps:"
    local entry num desc
    for entry in "${STEP_REGISTRY[@]}"; do
        IFS='|' read -r num _ desc <<< "$entry"
        printf "  %2s  %s\n" "$num" "$desc"
    done
}

list_apps() {
    echo "Applications  (--apps <name,...>  |  name -> atom [overlay] (license)):"
    local n spec atom overlay lic
    for n in firefox chromium chrome vlc mpv obs gimp inkscape libreoffice \
             thunderbird keepassxc spotify obsidian discord signal; do
        spec="$(_app_spec "$n")"
        IFS='|' read -r atom overlay lic <<< "$spec"
        printf "  %-13s %s%s%s\n" "$n" "$atom" "${overlay:+  [overlay: $overlay]}" "${lic:+  (license: $lic)}"
    done
    printf "  %-13s %s\n" "steam" "games-util/steam-launcher  [overlay: steam-overlay]  (use --steam)"
    echo
    echo "Profiles (--apps-profile): daily | dev | media | gaming. Raw category/atoms also work."
}

list_overlays() {
    echo "Popular overlays  (--overlay <name,...>):"
    printf "  %-14s %s\n" "guru"          "large community overlay (extra packages)"
    printf "  %-14s %s\n" "steam-overlay" "Valve Steam (games-util/steam-launcher) - see --steam"
    printf "  %-14s %s\n" "r7l"           "Obsidian and other desktop apps"
    printf "  %-14s %s\n" "pentoo"        "security / pentesting tools"
    printf "  %-14s %s\n" "science"       "scientific software"
    echo
    echo "Full official list:  eselect repository list"
    echo "Add a custom one:    --overlay name=https://git.example.org/repo.git"
}

parse_step_selection() {
    # Expand "1,3-5,7" into a normalized, zero-padded, sorted list into SELECTED_STEPS.
    local spec="$1" out=()
    local part start end i maxstep="${#STEP_REGISTRY[@]}"
    IFS=',' read -ra parts <<< "$spec"
    for part in "${parts[@]}"; do
        part="${part// /}"
        [[ -z "$part" ]] && continue
        if [[ "$part" == *-* ]]; then
            start="${part%-*}"; end="${part#*-}"
            [[ "$start" =~ ^[0-9]+$ && "$end" =~ ^[0-9]+$ ]] || die "Invalid step range: $part" "$EXIT_USAGE"
            # 10# forces base-10 so a zero-padded value like 08 is not read as octal.
            (( 10#$start >= 1 && 10#$end >= 10#$start && 10#$end <= maxstep )) \
                || die "Step range out of bounds (valid 1-${maxstep}): $part" "$EXIT_USAGE"
            for ((i=10#$start; i<=10#$end; i++)); do out+=("$(printf '%02d' "$i")"); done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
            (( 10#$part >= 1 && 10#$part <= maxstep )) \
                || die "Step out of range (valid 1-${maxstep}): $part" "$EXIT_USAGE"
            out+=("$(printf '%02d' "$((10#$part))")")
        else
            die "Invalid step selection: $part" "$EXIT_USAGE"
        fi
    done
    SELECTED_STEPS="$(printf '%s\n' "${out[@]}" | sort -u | tr '\n' ' ')"
}

# ==============================================
# ARGUMENT PARSING
# ==============================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) show_help; exit "$EXIT_SUCCESS" ;;
            -v|--version) echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"; exit "$EXIT_SUCCESS" ;;
            -y|--yes) ASSUME_YES=true ;;
            -n|--dry-run) DRY_RUN=true ;;
            --allow-root) ALLOW_ROOT=true ;;
            --no-banner) NO_BANNER=true ;;
            --no-emoji) USE_EMOJIS=false ;;
            --log-file) shift; [[ $# -gt 0 ]] || die "--log-file requires a path" "$EXIT_USAGE"; LOG_FILE="$1" ;;
            --rollback) ROLLBACK=true ;;
            --list-steps) _init_symbols; list_steps; exit "$EXIT_SUCCESS" ;;
            --list-apps) list_apps; exit "$EXIT_SUCCESS" ;;
            --list-overlays) list_overlays; exit "$EXIT_SUCCESS" ;;
            --steps) shift; [[ $# -gt 0 ]] || die "--steps requires an argument" "$EXIT_USAGE"; parse_step_selection "$1" ;;
            --profile) shift; [[ $# -gt 0 ]] || die "--profile requires an argument" "$EXIT_USAGE"; SYSTEM_PROFILE="$1" ;;
            --no-tune) TUNE_MAKECONF=false ;;
            --march) shift; case "$1" in native) SET_MARCH_NATIVE=true ;; none) SET_MARCH_NATIVE=false ;; *) die "--march expects native|none" "$EXIT_USAGE" ;; esac ;;
            --jobs) shift; [[ "$1" =~ ^[0-9]+$ ]] || die "--jobs expects a number" "$EXIT_USAGE"; MAKEOPTS_JOBS="$1" ;;
            --accept-license) shift; case "$1" in default|free|redist|all) ACCEPT_LICENSE_MODE="$1" ;; *) die "--accept-license expects default|free|redist|all" "$EXIT_USAGE" ;; esac ;;
            --no-cpu-flags) SET_CPU_FLAGS=false ;;
            --binhost) ENABLE_BINHOST=true ;;
            --binhost-uri) shift; [[ $# -gt 0 ]] || die "--binhost-uri requires an argument" "$EXIT_USAGE"; BINHOST_URI="$1"; ENABLE_BINHOST=true ;;
            --no-sync) DO_SYNC=false ;;
            --no-world-update) DO_WORLD_UPDATE=false ;;
            --no-depclean) DO_DEPCLEAN=false ;;
            --mirrors) RUN_MIRRORSELECT=true ;;
            --merge-config) MERGE_CONFIG=true ;;
            --install-kernel) INSTALL_KERNEL=true ;;
            --kernel-pkg) shift; [[ $# -gt 0 ]] || die "--kernel-pkg requires an argument" "$EXIT_USAGE"; KERNEL_PKG="$1"; INSTALL_KERNEL=true ;;
            --kernel-source) shift; case "$1" in bin|dist|source|vanilla) KERNEL_SOURCE="$1"; INSTALL_KERNEL=true ;; *) die "--kernel-source expects bin|dist|source|vanilla" "$EXIT_USAGE" ;; esac ;;
            --kernel-config) shift; case "$1" in standard|hardened|minimal|performance) KERNEL_CONFIG="$1"; INSTALL_KERNEL=true ;; *) die "--kernel-config expects standard|hardened|minimal|performance" "$EXIT_USAGE" ;; esac ;;
            --kernel-lockdown) KERNEL_LOCKDOWN=true ;;
            --kernel-cmdline-harden) KERNEL_CMDLINE_HARDEN=true ;;
            --kernel-manual) KERNEL_MANUAL=true ;;
            --bootloader) shift; case "$1" in grub|systemd-boot|none) BOOTLOADER="$1" ;; *) die "--bootloader expects grub|systemd-boot|none" "$EXIT_USAGE" ;; esac ;;
            --initramfs) shift; case "$1" in dracut|none) INITRAMFS="$1" ;; *) die "--initramfs expects dracut|none" "$EXIT_USAGE" ;; esac ;;
            --microcode) INSTALL_MICROCODE=true ;;
            --hardened-malloc) INSTALL_HARDENED_MALLOC=true ;;
            --minimize-surface) MINIMIZE_SURFACE=true ;;
            --root-password) ROOT_PASSWORD=true ;;
            --disable-root) DISABLE_ROOT=true ;;
            --group) shift; [[ $# -gt 0 ]] || die "--group requires a name" "$EXIT_USAGE"; NEW_GROUPS="${NEW_GROUPS} $1" ;;
            --user) shift; [[ $# -gt 0 ]] || die "--user requires a spec" "$EXIT_USAGE"; [[ -n "$NEW_USERS" ]] && NEW_USERS+=$'\n'; NEW_USERS+="$1" ;;
            --logs) shift; case "$1" in off|reduce|ephemeral) LOGS_LEVEL="$1" ;; *) die "--logs expects off|reduce|ephemeral" "$EXIT_USAGE" ;; esac ;;
            --sysctl-harden) HARDEN_SYSCTL=true ;;
            --harden-ipv6) HARDEN_IPV6=true ;;
            --firewall) shift; case "$1" in nftables|iptables|ufw|none) FIREWALL="$1"; CONFIGURE_FIREWALL=true; [[ "$1" == none ]] && CONFIGURE_FIREWALL=false ;; *) die "--firewall expects nftables|iptables|ufw|none" "$EXIT_USAGE" ;; esac ;;
            --no-ssh-rule) ALLOW_SSH=false ;;
            --ssh-harden) HARDEN_SSH=true ;;
            --ssh-port) shift; [[ "$1" =~ ^[0-9]+$ ]] || die "--ssh-port expects a number" "$EXIT_USAGE"; SSH_PORT="$1"; HARDEN_SSH=true ;;
            --ssh-no-root) SSH_DISABLE_ROOT=true; HARDEN_SSH=true ;;
            --ssh-key-only) SSH_KEY_ONLY=true; HARDEN_SSH=true ;;
            --audit) INSTALL_AUDIT=true; INSTALL_SYSLOG=true ;;
            --no-audit) INSTALL_AUDIT=false ;;
            --fail2ban) INSTALL_FAIL2BAN=true ;;
            --no-fail2ban) INSTALL_FAIL2BAN=false ;;
            --usbguard) INSTALL_USBGUARD=true ;;
            --apparmor) INSTALL_APPARMOR=true ;;
            --shell) INSTALL_SHELL=true ;;
            --no-shell) INSTALL_SHELL=false ;;
            --shell-user) shift; [[ $# -gt 0 ]] || die "--shell-user requires an argument" "$EXIT_USAGE"; SHELL_USER="$1"; INSTALL_SHELL=true ;;
            --editor) shift; case "$1" in vim|neovim|both|none) EDITOR_CHOICE="$1" ;; *) die "--editor expects vim|neovim|both|none" "$EXIT_USAGE" ;; esac ;;
            --no-chsh) SET_DEFAULT_SHELL=false ;;
            --fonts) INSTALL_FONTS=true ;;
            --no-fonts) INSTALL_FONTS=false ;;
            --nerd-fonts) shift; [[ $# -gt 0 ]] || die "--nerd-fonts requires a list" "$EXIT_USAGE"; NERD_FONTS_LIST="${1//,/ }"; INSTALL_FONTS=true ;;
            --desktop) INSTALL_DESKTOP=true ;;
            --display) shift; case "$1" in x11|wayland|both) DESKTOP_DISPLAY="$1"; INSTALL_DESKTOP=true ;; *) die "--display expects x11|wayland|both" "$EXIT_USAGE" ;; esac ;;
            --no-audio) DESKTOP_AUDIO=false ;;
            --no-nm) DESKTOP_NM=false ;;
            --video-cards) shift; [[ $# -gt 0 ]] || die "--video-cards requires a value" "$EXIT_USAGE"; VIDEO_CARDS_OVERRIDE="$1" ;;
            --overlay) shift; [[ $# -gt 0 ]] || die "--overlay requires a list" "$EXIT_USAGE"; OVERLAYS="${OVERLAYS:+$OVERLAYS }${1//,/ }" ;;
            --apps) shift; [[ $# -gt 0 ]] || die "--apps requires a list" "$EXIT_USAGE"; APPS="${APPS:+$APPS }${1//,/ }" ;;
            --apps-profile) shift; [[ $# -gt 0 ]] || die "--apps-profile requires a value" "$EXIT_USAGE"; APPS_PROFILE="$1" ;;
            --steam) INSTALL_STEAM=true ;;
            --de) shift; case "$1" in kde|gnome|sway|hyprland|xfce|none) DE="$1" ;; *) die "--de expects kde|gnome|sway|hyprland|xfce|none" "$EXIT_USAGE" ;; esac ;;
            --dm) shift; case "$1" in sddm|gdm|lightdm|greetd|none|auto) DM="$1" ;; *) die "--dm expects sddm|gdm|lightdm|greetd|none|auto" "$EXIT_USAGE" ;; esac ;;
            *) die "Unknown option: $1 (see --help)" "$EXIT_USAGE" ;;
        esac
        shift
    done
}

# ==============================================
# PROFILE DEFAULTS
# ==============================================
_prescan_profile() {
    # Extract --profile <name> before full parsing so profile defaults are applied
    # FIRST and explicit flags can then override them.
    local a prev=""
    for a in "$@"; do
        if [[ "$prev" == "--profile" ]]; then SYSTEM_PROFILE="$a"; prev=""; continue; fi
        [[ "$a" == "--profile" ]] && prev="--profile"
    done
}

_apply_profile() {
    case "$SYSTEM_PROFILE" in
        default)
            :  # balanced defaults already set above
            ;;
        desktop)
            SET_MARCH_NATIVE=true
            ACCEPT_LICENSE_MODE="redist"   # @FREE + @BINARY-REDISTRIBUTABLE (firmware), not a blanket *
            INSTALL_SHELL=true
            INSTALL_FONTS=true
            INSTALL_DESKTOP=true
            ;;
        server)
            SET_MARCH_NATIVE=true
            CONFIGURE_FIREWALL=true
            HARDEN_SYSCTL=true
            HARDEN_SSH=true
            INSTALL_AUDIT=true
            INSTALL_SYSLOG=true
            INSTALL_FAIL2BAN=true
            ;;
        hardened)
            SET_MARCH_NATIVE=true
            CONFIGURE_FIREWALL=true
            FIREWALL="nftables"
            HARDEN_SYSCTL=true
            HARDEN_IPV6=true
            HARDEN_SSH=true
            SSH_KEY_ONLY=true
            INSTALL_AUDIT=true
            INSTALL_SYSLOG=true
            INSTALL_FAIL2BAN=true
            INSTALL_APPARMOR=true
            ACCEPT_LICENSE_MODE="default"
            ;;
        minimal)
            INSTALL_TOOLING=true
            SET_CPU_FLAGS=true
            SET_MARCH_NATIVE=true
            DO_PRESERVED_REBUILD=true
            ;;
        opsec)
            # Everything hardened + minimal surface + reduced logging.
            SET_MARCH_NATIVE=true
            CONFIGURE_FIREWALL=true
            FIREWALL="nftables"
            HARDEN_SYSCTL=true
            HARDEN_IPV6=true
            HARDEN_SSH=true
            SSH_KEY_ONLY=true
            INSTALL_AUDIT=true
            INSTALL_SYSLOG=true
            INSTALL_FAIL2BAN=true
            INSTALL_APPARMOR=true
            INSTALL_HARDENED_MALLOC=true
            MINIMIZE_SURFACE=true
            LOGS_LEVEL="reduce"
            ACCEPT_LICENSE_MODE="default"
            ;;
        *)
            die "Unknown profile: $SYSTEM_PROFILE (default|desktop|server|hardened|minimal|opsec)" "$EXIT_USAGE"
            ;;
    esac
}

# ==============================================
# PREREQUISITE CHECKS
# ==============================================
detect_distribution() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO="${ID:-unknown}"
    fi
    if [[ ! -f /etc/gentoo-release && "$DISTRO" != "gentoo" ]]; then
        log_warn "This system does not look like Gentoo (no /etc/gentoo-release)."
        # --dry-run makes no changes and must be previewable anywhere (incl. CI), so it
        # only warns; a real run still asks for confirmation and aborts on a "no".
        if ! $DRY_RUN && ! confirm "Continue anyway?"; then
            die "Aborted: not a Gentoo system." "$EXIT_FAILURE"
        fi
    fi
    if have emerge; then
        DISTRO_PROFILE="$(eselect profile show 2>/dev/null | sed -n '2p' | tr -d ' \t' || true)"
    elif $DRY_RUN; then
        log_warn "Portage ('emerge') not found - dry-run continues (preview only; a real run needs Gentoo)."
    else
        die "Portage ('emerge') not found - is this really Gentoo?" "$EXIT_FAILURE"
    fi
    DISTRO="gentoo"
}

detect_multilib() {
    # A no-multilib profile cannot provide 32-bit (abi_x86_32); anything else can.
    if [[ "$DISTRO_PROFILE" == *no-multilib* ]]; then
        MULTILIB="no"
    else
        MULTILIB="yes"
    fi
}

detect_init_system() {
    if [[ -d /run/systemd/system ]]; then
        INIT_SYSTEM="systemd"
    elif [[ -f /run/openrc/softlevel ]] || have rc-update || have openrc; then
        INIT_SYSTEM="openrc"
    else
        INIT_SYSTEM="unknown"
        log_warn "Could not detect init system (assuming OpenRC-style service calls will be skipped)."
    fi
}

check_root() {
    if [[ $EUID -eq 0 ]]; then
        PRIV=""
        if ! $ALLOW_ROOT; then
            log_warn "Running as root. This is common on a fresh Gentoo install; continuing."
        fi
    else
        if have sudo; then
            PRIV="sudo"
        elif have doas; then
            PRIV="doas"
        elif $DRY_RUN; then
            # Dry-run never executes a privileged command (run_priv only prints), so it
            # needs no escalation - a preview must work for an unprivileged user anywhere.
            PRIV=""
            log_warn "No sudo/doas and not root - dry-run continues (preview only; a real run needs privileges)."
        else
            die "Need root: install sudo/doas or run as root (--allow-root)." "$EXIT_FAILURE"
        fi
    fi
}

check_sudo() {
    [[ -z "$PRIV" ]] && return 0
    $DRY_RUN && return 0
    log_info "Requesting privilege escalation via '$PRIV' ..."
    if ! $PRIV true; then
        die "Privilege escalation failed." "$EXIT_FAILURE"
    fi
}

detect_hardware() {
    NPROC="$(nproc 2>/dev/null || echo 1)"
    RAM_GB="$(awk '/MemTotal/{printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0)"
}

check_internet_connectivity() {
    log_info "Checking network connectivity ..."
    if have ping && ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        log_ok "Network reachable."
    elif have curl && curl -fsS --max-time 5 https://distfiles.gentoo.org >/dev/null 2>&1; then
        log_ok "Network reachable (via HTTPS)."
    else
        log_warn "No network detected - sync and package steps will likely fail."
    fi
}

# ==============================================
# PORTAGE / SERVICE ABSTRACTIONS
# ==============================================
emerge_install() {
    # Install packages if not already present (idempotent), quiet build by default.
    local opts=(--noreplace --verbose --ask=n)
    $EMERGE_QUIET && opts+=(--quiet-build=y)
    run_priv emerge "${opts[@]}" "$@"
}

service_enable() {
    local svc="$1"
    case "$INIT_SYSTEM" in
        systemd) run_priv systemctl enable "$svc" ;;
        openrc)  run_priv rc-update add "$svc" default ;;
        *) log_warn "Init system unknown; not enabling service '$svc'." ;;
    esac
}

service_start() {
    local svc="$1"
    case "$INIT_SYSTEM" in
        systemd) run_priv systemctl start "$svc" ;;
        openrc)  run_priv rc-service "$svc" start ;;
        *) log_warn "Init system unknown; not starting service '$svc'." ;;
    esac
}

service_enable_start() {
    # Enable at boot and start now (best-effort). $2 = runlevel for OpenRC (default 'default').
    local svc="$1" level="${2:-default}"
    case "$INIT_SYSTEM" in
        systemd) run_priv systemctl enable --now "$svc" ;;
        openrc)  run_priv rc-update add "$svc" "$level"; run_priv rc-service "$svc" start ;;
        *) log_warn "Init system unknown; not enabling/starting '$svc'." ;;
    esac
}

service_disable() {
    # Stop + disable a service if present (best-effort; no-op when absent).
    local svc="$1"
    case "$INIT_SYSTEM" in
        systemd) run_priv systemctl disable --now "$svc" 2>/dev/null || true ;;
        openrc)  run_priv rc-service "$svc" stop 2>/dev/null || true; run_priv rc-update del "$svc" 2>/dev/null || true ;;
    esac
}

write_root_file() {
    # write_root_file <path> <<<"content"   - writes stdin to a root-owned file (dry-run aware).
    # GPI_SYSROOT (empty by default) lets a chroot/image target or a test redirect the write.
    local path="${GPI_SYSROOT}$1"
    if $DRY_RUN; then
        cat >/dev/null   # drain stdin
        echo "    ${ICON_SKIP} [dry-run] write config to ${path}"
        return 0
    fi
    run_priv mkdir -p "$(dirname "$path")"
    run_priv tee "$path" >/dev/null
    log_ok "Wrote ${path}"
}

_resolve_target_user() {
    if [[ -n "$SHELL_USER" ]]; then
        TARGET_USER="$SHELL_USER"
    elif [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
        TARGET_USER="$SUDO_USER"
    elif [[ $EUID -ne 0 ]]; then
        TARGET_USER="$(id -un)"
    else
        TARGET_USER="root"
    fi
    TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)"
    [[ -z "$TARGET_HOME" ]] && TARGET_HOME="/home/${TARGET_USER}"
}

user_do() {
    # Run a shell command string as TARGET_USER (dry-run aware; no spaces-in-paths).
    local cmd="$1"
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] (as ${TARGET_USER}) ${cmd}"
        return 0
    fi
    if [[ "$(id -un)" == "$TARGET_USER" ]]; then
        bash -c "$cmd"
    elif [[ $EUID -eq 0 ]]; then
        su - "$TARGET_USER" -c "$cmd"
    else
        ${PRIV} -u "$TARGET_USER" bash -c "$cmd"
    fi
}

make_conf_backup_once() {
    $DRY_RUN && return 0
    if [[ -f "$MAKE_CONF" && ! -f "${MAKE_CONF}.gpi.bak" ]]; then
        run_priv cp -a "$MAKE_CONF" "${MAKE_CONF}.gpi.bak"
        log_ok "Backed up make.conf -> ${MAKE_CONF}.gpi.bak"
    fi
}

make_conf_set() {
    # make_conf_set KEY "VALUE"  -> sets KEY="VALUE" idempotently (replace or append).
    local key="$1" val="$2"
    make_conf_backup_once
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] set ${key}=\"${val}\" in ${MAKE_CONF}"
        return 0
    fi
    if run_priv grep -qE "^[[:space:]]*${key}=" "$MAKE_CONF" 2>/dev/null; then
        run_priv sed -i -E "s|^[[:space:]]*${key}=.*|${key}=\"${val}\"|" "$MAKE_CONF"
    else
        printf '%s="%s"\n' "$key" "$val" | run_priv tee -a "$MAKE_CONF" >/dev/null
    fi
    log_ok "make.conf: ${key}=\"${val}\""
}

# ==============================================
# STEPS
# ==============================================
step_01_sync_news() {
    log_section "Step 01 - Sync Portage tree & news"
    if $RUN_MIRRORSELECT; then
        have mirrorselect || emerge_install app-portage/mirrorselect || log_warn "mirrorselect install failed."
        log_info "Selecting fastest mirrors (mirrorselect -s3 -b10 -D) ..."
        if $DRY_RUN; then
            echo "    ${ICON_SKIP} [dry-run] mirrorselect -s3 -b10 -D  (updates GENTOO_MIRRORS in make.conf)"
        else
            make_conf_backup_once
            run_priv mirrorselect -s3 -b10 -D || log_warn "mirrorselect failed."
        fi
    fi
    if ! $DO_SYNC; then
        log_skip "Sync disabled (--no-sync)."
    else
        if have eix-sync; then
            log_info "Syncing via eix-sync ..."
            run_priv eix-sync || log_warn "eix-sync reported issues."
        else
            log_info "Syncing via emerge --sync ..."
            run_priv emerge --sync || {
                log_warn "emerge --sync failed; trying emerge-webrsync ..."
                run_priv emerge-webrsync || log_warn "Portage sync failed."
            }
        fi
    fi
    if have eselect; then
        log_info "Checking Portage news ..."
        run_priv eselect news read new || true
    fi
    log_ok "Step 01 complete."
}

step_02_portage_tuning() {
    log_section "Step 02 - Portage configuration (make.conf)"
    if ! $TUNE_MAKECONF; then
        log_skip "make.conf configuration disabled (--no-tune)."
        return 0
    fi

    # MAKEOPTS (jobs from cores capped by RAM: ~1 job / 2 GB)
    if $SET_MAKEOPTS; then
        local jobs="$MAKEOPTS_JOBS"
        if [[ -z "$jobs" ]]; then
            jobs="$NPROC"
            if (( RAM_GB > 0 )); then
                local rjobs=$(( RAM_GB / 2 )); (( rjobs < 1 )) && rjobs=1
                (( jobs > rjobs )) && jobs="$rjobs"
            fi
        fi
        make_conf_set "MAKEOPTS" "-j${jobs} -l$((NPROC + 1))"
    fi

    # COMMON_FLAGS baseline
    local cflags="-O2 -pipe"
    $SET_MARCH_NATIVE && cflags="-march=native -O2 -pipe"
    make_conf_set "COMMON_FLAGS" "$cflags"

    # EMERGE_DEFAULT_OPTS: resilient, verbose, quiet-build
    make_conf_set "EMERGE_DEFAULT_OPTS" "--verbose --quiet-build=y --with-bdeps=y --complete-graph=y --keep-going=y --ask=n"

    # FEATURES: parallel fetch + candy; getbinpkg handled in step 03
    make_conf_set "FEATURES" "candy parallel-fetch parallel-install"

    # ACCEPT_LICENSE per mode
    case "$ACCEPT_LICENSE_MODE" in
        free)    make_conf_set "ACCEPT_LICENSE" "-* @FREE" ;;
        redist)  make_conf_set "ACCEPT_LICENSE" "@FREE @BINARY-REDISTRIBUTABLE" ;;
        all)     make_conf_set "ACCEPT_LICENSE" "*" ;;
        default) log_skip "ACCEPT_LICENSE left at Gentoo profile default." ;;
    esac

    # CPU_FLAGS_X86 via cpuid2cpuflags (written to package.use for clarity)
    if $SET_CPU_FLAGS; then
        if ! have cpuid2cpuflags; then
            log_info "Installing app-portage/cpuid2cpuflags ..."
            emerge_install app-portage/cpuid2cpuflags || log_warn "Could not install cpuid2cpuflags."
        fi
        if have cpuid2cpuflags; then
            local flags; flags="$(cpuid2cpuflags 2>/dev/null || true)"   # e.g. "CPU_FLAGS_X86: aes avx ..."
            if [[ -n "$flags" ]]; then
                run_priv mkdir -p "$PKG_USE_DIR"
                if $DRY_RUN; then
                    echo "    ${ICON_SKIP} [dry-run] write '*/* ${flags}' to ${PKG_USE_DIR}/00cpu-flags"
                else
                    printf '# Managed by gentoo-post-install\n*/* %s\n' "$flags" | run_priv tee "${PKG_USE_DIR}/00cpu-flags" >/dev/null
                fi
                log_ok "CPU flags: ${flags}"
            fi
        fi
    fi
    log_ok "Step 02 complete."
}

step_03_binhost() {
    log_section "Step 03 - Binary package host"
    if ! $ENABLE_BINHOST; then
        log_skip "Binhost disabled (enable with --binhost)."
        return 0
    fi
    log_info "Configuring binary package host: ${BINHOST_URI}"
    run_priv mkdir -p "$BINREPOS_DIR"
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] write binrepo config to ${BINREPOS_DIR}/gentoobinhost.conf"
    else
        run_priv tee "${BINREPOS_DIR}/gentoobinhost.conf" >/dev/null <<EOF
# Managed by gentoo-post-install
[binhost]
priority = 9999
sync-uri = ${BINHOST_URI}
verify-signature = true
EOF
    fi
    # Trust anchors for signed binpkgs
    if ! have getuto; then
        emerge_install app-portage/getuto || log_warn "Could not install getuto (needed for binpkg signature trust)."
    fi
    if have getuto; then run_priv getuto || true; fi
    # Turn on getbinpkg in FEATURES (append to existing value)
    if run_priv grep -qE '^[[:space:]]*FEATURES=' "$MAKE_CONF" 2>/dev/null; then
        local cur; cur="$(run_priv sed -n -E 's/^[[:space:]]*FEATURES="?([^"]*)"?.*/\1/p' "$MAKE_CONF" | head -1)"
        case " $cur " in
            *" getbinpkg "*) : ;;
            *) make_conf_set "FEATURES" "${cur} getbinpkg binpkg-request-signature" ;;
        esac
    else
        make_conf_set "FEATURES" "candy parallel-fetch getbinpkg binpkg-request-signature"
    fi
    log_ok "Step 03 complete - subsequent emerges may pull prebuilt binaries."
}

step_04_portage_tooling() {
    log_section "Step 04 - Portage tooling"
    if ! $INSTALL_TOOLING; then
        log_skip "Tooling install disabled."
        return 0
    fi
    local pkgs=(
        app-portage/gentoolkit      # equery, eclean, revdep-rebuild
        app-portage/eix             # fast package index/search
        app-portage/portage-utils   # q* tools (qlist, qsize, ...)
        app-portage/genlop          # emerge time estimates/history
        app-portage/mirrorselect    # pick fast mirrors
    )
    log_info "Installing: ${pkgs[*]}"
    emerge_install "${pkgs[@]}" || log_warn "Some tooling packages failed to install."
    if have eix-update; then
        run_priv eix-update || true
    fi
    log_ok "Step 04 complete."
}

step_05_world_update() {
    log_section "Step 05 - World update & cleanup"
    if $DO_WORLD_UPDATE; then
        log_info "Updating @world (deep, new-use) ..."
        run_priv emerge --update --deep --newuse --with-bdeps=y --keep-going=y --ask=n @world \
            || log_warn "@world update reported issues (check output / dispatch-conf)."
    else
        log_skip "@world update skipped (--no-world-update)."
    fi
    if $DO_PRESERVED_REBUILD; then
        log_info "Rebuilding preserved libraries ..."
        run_priv emerge --ask=n @preserved-rebuild || true
    fi
    if $DO_DEPCLEAN; then
        if confirm "Run 'emerge --depclean' to remove orphaned packages?"; then
            run_priv emerge --ask=n --depclean || log_warn "depclean reported issues."
        else
            log_skip "depclean skipped by user."
        fi
    fi
    log_warn "If Portage wrote config updates, review them with: dispatch-conf (or etc-update)."
    log_ok "Step 05 complete."
}

step_06_use_flags() {
    log_section "Step 06 - USE flags layout"
    run_priv mkdir -p "$PKG_USE_DIR" "$PKG_ACCEPT_DIR" "$PKG_LICENSE_DIR"
    # A conservative, widely-useful global USE baseline as a dedicated file so the
    # user's own make.conf USE stays untouched and reviewable.
    local use_baseline
    case "$SYSTEM_PROFILE" in
        desktop) use_baseline="X wayland dbus policykit udev alsa pulseaudio pipewire networkmanager -kde" ;;
        server)  use_baseline="-X -gtk -gnome -kde -qt5 -qt6 ssl ipv6 threads" ;;
        hardened) use_baseline="-X -gtk -gnome -kde ssl ipv6" ;;  # toolchain hardening is default on 23.0 profiles; use eselect profile for a hardened profile
        minimal) use_baseline="-X ssl ipv6" ;;
        *)       use_baseline="ssl ipv6 threads" ;;
    esac
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] write global USE baseline to ${PKG_USE_DIR}/10-baseline"
    else
        {
            echo "# Managed by gentoo-post-install (profile: ${SYSTEM_PROFILE})"
            echo "# Review and adjust; remove this file to revert."
            echo "*/* ${use_baseline}"
        } | run_priv tee "${PKG_USE_DIR}/10-baseline" >/dev/null
    fi
    log_ok "Wrote USE baseline for profile '${SYSTEM_PROFILE}'."
    log_warn "USE changes take effect on next @world rebuild: emerge -uUDN @world"
    log_ok "Step 06 complete."
}

_cpu_vendor() {
    # GenuineIntel | AuthenticAMD | (other)
    awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo 2>/dev/null
}

_kernel_pkg_for_source() {
    case "$1" in
        bin)     echo "sys-kernel/gentoo-kernel-bin" ;;
        dist)    echo "sys-kernel/gentoo-kernel" ;;
        source)  echo "sys-kernel/gentoo-sources" ;;
        vanilla) echo "sys-kernel/vanilla-sources" ;;
        *)       echo "sys-kernel/gentoo-kernel-bin" ;;
    esac
}

_kernel_hardening_fragment() {
    # KSPP-recommended options; the single Gentoo toggle enables the bulk of them.
    # Ref: wiki KSPP tutorial.
    cat <<'EOF'
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
    if $KERNEL_LOCKDOWN; then
        cat <<'EOF'
CONFIG_SECURITY_LOCKDOWN_LSM=y
CONFIG_SECURITY_LOCKDOWN_LSM_EARLY=y
CONFIG_LOCK_DOWN_KERNEL_FORCE_CONFIDENTIALITY=y
EOF
    fi
}

_kernel_performance_fragment() {
    cat <<'EOF'
# Managed by gentoo-post-install - performance
CONFIG_HZ_1000=y
CONFIG_NO_HZ_IDLE=y
CONFIG_PREEMPT=y
EOF
    case "$(_cpu_vendor)" in
        GenuineIntel) echo "CONFIG_MNATIVE_INTEL=y" ;;
        AuthenticAMD) echo "CONFIG_MNATIVE_AMD=y" ;;
    esac
}

_apply_kernel_config() {
    # Write /etc/kernel/config.d fragments (consumed when a source-built dist-kernel
    # is (re)built). Only 'dist' actually builds from these; 'bin' is prebuilt.
    [[ "$KERNEL_CONFIG" == standard ]] && return 0
    run_priv mkdir -p /etc/kernel/config.d
    case "$KERNEL_CONFIG" in
        hardened)    _kernel_hardening_fragment | write_root_file /etc/kernel/config.d/90-gpi-hardening.config
                     $KERNEL_LOCKDOWN && log_warn "Lockdown LSM enabled - safe ONLY with signed modules or a monolithic kernel (else breaks module loading/hibernation/nvidia)." ;;
        performance) _kernel_performance_fragment | write_root_file /etc/kernel/config.d/90-gpi-performance.config ;;
        minimal)     if [[ "$KERNEL_SOURCE" == source || "$KERNEL_SOURCE" == vanilla ]]; then
                         log_info "minimal: build a hardware-only kernel with 'make localmodconfig' in /usr/src/linux (see build guidance)."
                     else
                         log_warn "minimal (localmodconfig) needs --kernel-source source; ignored for '${KERNEL_SOURCE}'."
                     fi ;;
    esac
    if [[ "$KERNEL_SOURCE" == bin && "$KERNEL_CONFIG" != standard ]]; then
        log_warn "gentoo-kernel-bin is PREBUILT - config fragments won't apply. Use --kernel-source dist (gentoo-kernel) to build with them."
    fi
}

_kernel_harden_cmdline() {
    local params="init_on_alloc=1 init_on_free=1 randomize_kstack_offset=on slab_nomerge page_table_check=on vsyscall=none pti=on page_alloc.shuffle=1"
    $KERNEL_LOCKDOWN && params+=" lockdown=confidentiality"
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] add KSPP cmdline to bootloader: ${params}"
        return 0
    fi
    case "$BOOTLOADER" in
        grub)
            if run_priv grep -q 'randomize_kstack_offset=on' /etc/default/grub 2>/dev/null; then
                log_skip "KSPP cmdline already present in /etc/default/grub."
            else
                if run_priv grep -qE '^[[:space:]]*GRUB_CMDLINE_LINUX="' /etc/default/grub 2>/dev/null; then
                    run_priv sed -i -E "s|^([[:space:]]*GRUB_CMDLINE_LINUX=\")(.*)(\")|\1\2 ${params}\3|" /etc/default/grub
                else
                    printf 'GRUB_CMDLINE_LINUX="%s"\n' "$params" | run_priv tee -a /etc/default/grub >/dev/null
                fi
                log_warn "GRUB cmdline updated - regenerate: grub-mkconfig -o /boot/grub/grub.cfg"
            fi
            ;;
        *)
            if run_priv grep -q 'randomize_kstack_offset=on' /etc/kernel/cmdline 2>/dev/null; then
                log_skip "KSPP cmdline already present in /etc/kernel/cmdline."
            else
                printf '%s\n' "$params" | run_priv tee -a /etc/kernel/cmdline >/dev/null
                log_warn "Appended KSPP params to /etc/kernel/cmdline - rebuild the initramfs / bootloader entry."
            fi
            ;;
    esac
}

_install_microcode() {
    log_info "CPU microcode ..."
    local vendor; vendor="$(_cpu_vendor)"
    case "$vendor" in
        GenuineIntel)
            make_conf_set "MICROCODE_SIGNATURES" "-S"   # current CPU only
            run_priv mkdir -p "$PKG_USE_DIR"
            if $DRY_RUN; then
                echo "    ${ICON_SKIP} [dry-run] write 'sys-firmware/intel-microcode initramfs split-ucode' to ${PKG_USE_DIR}/30-microcode"
            else
                printf '# Managed by gentoo-post-install\nsys-firmware/intel-microcode initramfs split-ucode\n' \
                    | run_priv tee "${PKG_USE_DIR}/30-microcode" >/dev/null
            fi
            emerge_install sys-firmware/intel-microcode || log_warn "intel-microcode install failed."
            log_info "Intel microcode installed - regenerate the initramfs / verify early load (dmesg | grep microcode)."
            ;;
        AuthenticAMD)
            emerge_install sys-kernel/linux-firmware || log_warn "linux-firmware install failed."
            log_info "AMD microcode ships in sys-kernel/linux-firmware (loaded via initramfs/kernel)."
            ;;
        *)
            log_warn "Unknown CPU vendor '${vendor:-?}' - skipping microcode."
            ;;
    esac
}

step_07_kernel() {
    log_section "Step 07 - Kernel & microcode"
    if ! $INSTALL_KERNEL && ! $INSTALL_MICROCODE; then
        log_skip "Kernel/microcode skipped (--install-kernel and/or --microcode)."
        return 0
    fi
    if ! $INSTALL_KERNEL; then
        $INSTALL_MICROCODE && _install_microcode
        log_ok "Step 07 complete."
        return 0
    fi
    local kpkg="${KERNEL_PKG:-$(_kernel_pkg_for_source "$KERNEL_SOURCE")}"
    local is_dist=false
    [[ "$KERNEL_SOURCE" == bin || "$KERNEL_SOURCE" == dist ]] && is_dist=true
    [[ -n "$KERNEL_PKG" && "$kpkg" == *gentoo-kernel* ]] && is_dist=true
    log_info "Installing linux-firmware and ${kpkg} (source=${KERNEL_SOURCE}, bootloader=${BOOTLOADER}, initramfs=${INITRAMFS}) ..."
    emerge_install sys-kernel/linux-firmware || log_warn "linux-firmware install failed."

    # sys-kernel/installkernel must carry the right USE flags BEFORE it is built,
    # so that a kernel install auto-generates the initramfs and updates the
    # bootloader. See wiki.gentoo.org/wiki/Installkernel.
    local ik_use=""
    [[ "$INITRAMFS" == dracut ]] && ik_use+=" dracut"
    case "$BOOTLOADER" in
        grub)         ik_use+=" grub" ;;
        systemd-boot) ik_use+=" systemd-boot" ;;
        none)         : ;;
    esac
    [[ "$INIT_SYSTEM" == systemd ]] && ik_use+=" systemd"
    ik_use="${ik_use# }"
    if [[ -n "$ik_use" ]]; then
        run_priv mkdir -p "$PKG_USE_DIR"
        if $DRY_RUN; then
            echo "    ${ICON_SKIP} [dry-run] write 'sys-kernel/installkernel ${ik_use}' to ${PKG_USE_DIR}/20-installkernel"
        else
            printf '# Managed by gentoo-post-install\nsys-kernel/installkernel %s\n' "$ik_use" \
                | run_priv tee "${PKG_USE_DIR}/20-installkernel" >/dev/null
        fi
        log_ok "installkernel USE: ${ik_use}"
    fi

    emerge_install sys-kernel/installkernel || log_warn "installkernel install failed."

    # Config fragments must exist BEFORE a source dist-kernel is built.
    log_info "Kernel config profile: ${KERNEL_CONFIG}${KERNEL_LOCKDOWN:+ +lockdown}"
    _apply_kernel_config

    emerge_install "$kpkg" || { log_err "Kernel install failed."; return 1; }

    if $is_dist; then
        if [[ "$BOOTLOADER" == none ]]; then
            log_warn "No bootloader integration selected - point your bootloader at the new kernel yourself."
        else
            log_info "installkernel handled the initramfs + ${BOOTLOADER}; verify /boot and your bootloader entry."
        fi
        [[ "$KERNEL_CONFIG" != standard && "$KERNEL_SOURCE" == dist ]] && \
            log_warn "Verify the new kernel BOOTS before relying on it - a hardened/minimal config can fail on your hardware. The previous kernel is kept."
    else
        log_warn "Sources installed under /usr/src (${KERNEL_SOURCE}). Configure + build required:"
        if [[ "$KERNEL_CONFIG" == minimal ]]; then
            log_warn "    cd /usr/src/linux && make localmodconfig && make && make modules_install && make install"
        elif ! $KERNEL_MANUAL; then
            log_warn "    cd /usr/src/linux && make defconfig && make menuconfig && make && make modules_install && make install"
        else
            log_warn "    cd /usr/src/linux && make menuconfig   # then build; no auto-build (--kernel-manual)"
        fi
        log_warn "    Verify it BOOTS before removing the current kernel."
    fi

    $KERNEL_CMDLINE_HARDEN && _kernel_harden_cmdline
    $INSTALL_MICROCODE && _install_microcode
    log_ok "Step 07 complete."
}

step_08_sysctl_hardening() {
    log_section "Step 08 - sysctl hardening"
    if ! $HARDEN_SYSCTL; then
        log_skip "sysctl hardening disabled (--sysctl-harden, or server/hardened profile)."
        return 0
    fi
    {
        cat <<'EOF'
# Managed by gentoo-post-install - network & kernel hardening.
# Remove this file and run 'sysctl --system' to revert.

# --- IPv4 network ---
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1

# --- Kernel / filesystem ---
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
kernel.randomize_va_space = 2
kernel.sysrq = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
fs.suid_dumpable = 0
EOF
        if $HARDEN_IPV6; then
            cat <<'EOF'

# --- IPv6 network ---
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
EOF
        fi
    } | write_root_file /etc/sysctl.d/99-gentoo-post-install.conf

    # Ensure sysctl values load at boot (OpenRC: sys-apps/procps sysctl service).
    if [[ "$INIT_SYSTEM" == openrc ]]; then run_priv rc-update add sysctl boot 2>/dev/null || true; fi
    if have sysctl && ! $DRY_RUN; then
        run_priv sysctl --system >/dev/null 2>&1 \
            || log_warn "sysctl --system returned non-zero (some keys may need kernel options e.g. Yama)."
    fi

    # Optional userspace hardened allocator.
    if $INSTALL_HARDENED_MALLOC; then
        log_info "Installing sys-libs/hardened_malloc ..."
        emerge_install sys-libs/hardened_malloc || log_warn "hardened_malloc install failed."
        log_info "Use it via its wrapper or LD_PRELOAD (see the package's post-install notes)."
    fi

    # Toolchain hardening guidance (it is NOT a USE flag on modern Gentoo).
    if [[ "$SYSTEM_PROFILE" == hardened ]]; then
        log_info "Note: on 23.0 profiles, toolchain hardening (SSP, PIE, RELRO+BIND_NOW, _FORTIFY_SOURCE=2) is already ON by default."
        log_info "For a hardened *profile*, do it deliberately (rebuilds the world):"
        log_info "    eselect profile list | grep hardened   # pick the match for your init"
        log_info "    eselect profile set <n> && emerge -e @world"
    fi
    log_ok "Step 08 complete."
}

_fw_nftables() {
    emerge_install net-firewall/nftables || { log_err "nftables install failed."; return 1; }
    local ssh_rule=""
    $ALLOW_SSH && ssh_rule="        tcp dport ${SSH_PORT} accept comment \"ssh\""
    # Back up an existing ruleset before replacing it (no silent data loss).
    if ! $DRY_RUN && [[ -f /etc/nftables.conf && ! -f /etc/nftables.conf.gpi.bak ]]; then
        run_priv cp -a /etc/nftables.conf /etc/nftables.conf.gpi.bak && log_ok "Backed up /etc/nftables.conf -> .gpi.bak"
    fi
    write_root_file /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
# Managed by gentoo-post-install - default-deny inbound firewall.
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        ct state established,related accept
        ct state invalid drop
        iif "lo" accept
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept
${ssh_rule}
    }
    chain forward {
        type filter hook forward priority filter; policy drop;
    }
    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF
    if ! $DRY_RUN; then
        if run_priv nft -c -f /etc/nftables.conf; then
            run_priv nft -f /etc/nftables.conf || log_warn "Applying nftables ruleset failed."
        else
            log_err "nftables ruleset failed validation (nft -c); not applying."
            return 1
        fi
        if [[ "$INIT_SYSTEM" == openrc ]]; then run_priv rc-service nftables save 2>/dev/null || true; fi
    fi
    service_enable_start nftables
    if [[ "$INIT_SYSTEM" == systemd ]]; then
        log_info "systemd: if the ruleset isn't restored at boot, enable nftables-store + nftables-load instead of nftables.service."
    fi
}

_fw_iptables() {
    emerge_install net-firewall/iptables || { log_err "iptables install failed."; return 1; }
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] default-deny INPUT + established/lo/icmp${ALLOW_SSH:+ + ssh/${SSH_PORT}}, then persist"
    else
        # Add accept rules BEFORE switching the policy to DROP (avoids self-lockout).
        run_priv iptables -F INPUT
        run_priv iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        run_priv iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
        run_priv iptables -A INPUT -i lo -j ACCEPT
        run_priv iptables -A INPUT -p icmp -j ACCEPT
        $ALLOW_SSH && run_priv iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
        run_priv iptables -P INPUT DROP
        run_priv iptables -P FORWARD DROP
        run_priv iptables -P OUTPUT ACCEPT
        run_priv mkdir -p /var/lib/iptables
        run_priv sh -c 'iptables-save > /var/lib/iptables/rules-save' || log_warn "Could not persist iptables rules."
    fi
    service_enable_start iptables
}

_fw_ufw() {
    emerge_install net-firewall/ufw || { log_err "ufw install failed."; return 1; }
    run_priv ufw default deny incoming
    run_priv ufw default allow outgoing
    $ALLOW_SSH && run_priv ufw allow "${SSH_PORT}/tcp"
    if $ASSUME_YES || confirm "Enable ufw now (SSH is allowed above to avoid lockout)?"; then
        run_priv ufw --force enable
    else
        log_skip "ufw configured but not enabled."
    fi
    service_enable ufw
}

step_09_firewall() {
    log_section "Step 09 - Firewall (${FIREWALL})"
    if ! $CONFIGURE_FIREWALL; then
        log_skip "Firewall config disabled (--firewall nftables|iptables|ufw)."
        return 0
    fi
    $ALLOW_SSH || log_warn "SSH allow rule is DISABLED (--no-ssh-rule): remote access may be cut off."
    case "$FIREWALL" in
        nftables) _fw_nftables ;;
        iptables) _fw_iptables ;;
        ufw)      _fw_ufw ;;
        *) log_warn "Unknown firewall backend '$FIREWALL'." ; return 1 ;;
    esac
    log_ok "Step 09 complete."
}

step_10_ssh_hardening() {
    log_section "Step 10 - OpenSSH hardening"
    if ! $HARDEN_SSH; then
        log_skip "SSH hardening disabled (--ssh-harden)."
        return 0
    fi
    if [[ ! -d /etc/ssh ]]; then
        log_skip "OpenSSH not present (/etc/ssh missing); skipping."
        return 0
    fi
    local permit_root="prohibit-password" pass_auth="yes"
    $SSH_DISABLE_ROOT && permit_root="no"
    $SSH_KEY_ONLY && pass_auth="no"
    $SSH_KEY_ONLY && log_warn "PasswordAuthentication will be DISABLED - ensure a working SSH key is installed!"

    write_root_file /etc/ssh/sshd_config.d/99-gentoo-post-install.conf <<EOF
# Managed by gentoo-post-install - OpenSSH hardening drop-in.
Port ${SSH_PORT}
PermitRootLogin ${permit_root}
PasswordAuthentication ${pass_auth}
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
MaxAuthTries 3
MaxSessions 4
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
EOF

    if ! $DRY_RUN; then
        # Ensure the main config actually pulls in the drop-in directory.
        if ! run_priv grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config 2>/dev/null; then
            log_warn "sshd_config lacks an Include for sshd_config.d - appending one (place it near the top if a directive fails to take effect)."
            printf '\nInclude /etc/ssh/sshd_config.d/*.conf\n' | run_priv tee -a /etc/ssh/sshd_config >/dev/null
        fi
        local sshd_bin; sshd_bin="$(command -v sshd 2>/dev/null || true)"
        [[ -z "$sshd_bin" && -x /usr/sbin/sshd ]] && sshd_bin="/usr/sbin/sshd"
        if [[ -n "$sshd_bin" ]]; then
            if run_priv "$sshd_bin" -t; then
                log_ok "sshd config validates."
                service_enable sshd 2>/dev/null || true
                if confirm "Restart sshd now to apply (may drop your current SSH session)?"; then
                    case "$INIT_SYSTEM" in
                        systemd) run_priv systemctl restart sshd ;;
                        openrc)  run_priv rc-service sshd restart ;;
                    esac
                else
                    log_skip "sshd not restarted; changes apply on next restart."
                fi
            else
                log_err "sshd -t FAILED - not applying. Review the drop-in file."
                return 1
            fi
        else
            log_warn "sshd binary not found; wrote drop-in but could not validate/restart."
        fi
    fi
    log_ok "Step 10 complete."
}

step_11_audit_logging() {
    log_section "Step 11 - Audit & system logging"
    local did=false
    if $INSTALL_AUDIT; then
        did=true
        log_info "Installing sys-process/audit ..."
        emerge_install sys-process/audit || log_warn "audit install failed."
        service_enable_start auditd 2>/dev/null || log_warn "Enable auditd manually (service name may differ)."
    fi
    if $INSTALL_SYSLOG; then
        if [[ "$INIT_SYSTEM" == systemd ]]; then
            log_skip "systemd detected - journald already logs; skipping extra syslog daemon."
        elif have rsyslogd || have syslog-ng || have sysklogd; then
            log_skip "A syslog daemon is already installed."
        else
            did=true
            log_info "Installing app-admin/sysklogd (system logger) ..."
            emerge_install app-admin/sysklogd || log_warn "sysklogd install failed."
            service_enable_start sysklogd 2>/dev/null || log_warn "Could not enable sysklogd."
        fi
        emerge_install app-admin/logrotate || true
    fi
    $did || log_skip "Audit/logging disabled for this profile (--audit to enable)."
    log_ok "Step 11 complete."
}

step_12_fail2ban() {
    log_section "Step 12 - fail2ban"
    if ! $INSTALL_FAIL2BAN; then
        log_skip "fail2ban disabled (--fail2ban to enable)."
        return 0
    fi
    emerge_install net-analyzer/fail2ban || { log_err "fail2ban install failed."; return 1; }
    local backend="auto" logpath_line=""
    if [[ "$INIT_SYSTEM" == systemd ]]; then
        backend="systemd"
    else
        logpath_line=$'\nlogpath  = /var/log/messages'
    fi
    write_root_file /etc/fail2ban/jail.d/99-gentoo-post-install.local <<EOF
# Managed by gentoo-post-install - protect sshd against brute force.
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = ${backend}

[sshd]
enabled  = true
port     = ${SSH_PORT}${logpath_line}
EOF
    service_enable_start fail2ban
    log_ok "Step 12 complete."
}

step_13_usbguard() {
    log_section "Step 13 - USBGuard"
    if ! $INSTALL_USBGUARD; then
        log_skip "USBGuard disabled (opt-in via --usbguard)."
        return 0
    fi
    log_warn "USBGuard blocks unknown USB devices and CAN lock out USB keyboards."
    log_warn "A policy allowing currently-connected devices will be generated first."
    if ! $ASSUME_YES && ! confirm "Install and configure USBGuard now?"; then
        log_skip "USBGuard skipped by user."
        return 0
    fi
    emerge_install sys-apps/usbguard || { log_err "usbguard install failed."; return 1; }
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] usbguard generate-policy > /etc/usbguard/rules.conf (chmod 600)"
    elif have usbguard; then
        if run_priv sh -c 'usbguard generate-policy > /etc/usbguard/rules.conf'; then
            run_priv chmod 600 /etc/usbguard/rules.conf
            log_ok "Generated USBGuard policy from connected devices."
        else
            log_warn "Could not generate policy; review /etc/usbguard/rules.conf BEFORE enabling."
        fi
    fi
    service_enable_start usbguard
    log_ok "Step 13 complete."
}

step_14_apparmor() {
    log_section "Step 14 - AppArmor"
    if ! $INSTALL_APPARMOR; then
        log_skip "AppArmor disabled (opt-in via --apparmor)."
        return 0
    fi
    emerge_install sys-apps/apparmor sys-apps/apparmor-utils || { log_err "AppArmor install failed."; return 1; }
    case "$INIT_SYSTEM" in
        systemd) run_priv systemctl enable apparmor ;;
        openrc)  run_priv rc-update add apparmor boot ;;
    esac
    log_warn "AppArmor needs kernel support (CONFIG_SECURITY_APPARMOR=y) and the LSM enabled."
    log_warn "Add to your bootloader kernel cmdline, then reboot:"
    log_warn "    lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
    log_warn "Verify afterwards with: aa-status"
    log_ok "Step 14 complete."
}

_write_zshrc() {
    local dest="${TARGET_HOME}/.zshrc"
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] backup + write ${dest} (owner ${TARGET_USER})"
        return 0
    fi
    [[ -f "$dest" ]] && run_priv cp -a "$dest" "${dest}.gpi.bak"
    local tmp; tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
# ~/.zshrc - managed by gentoo-post-install

# Powerlevel10k instant prompt (keep near the top)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
    git
    sudo
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-completions
)

source $ZSH/oh-my-zsh.sh

# User configuration
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
export EDITOR='vim'

# General aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias listen='ss -tuln'
alias myip='curl -s ifconfig.me'

# Gentoo / Portage aliases
alias sync='sudo emerge --sync'
alias up='sudo emerge -auUDN @world'
alias depclean='sudo emerge --depclean'
alias preserved='sudo emerge @preserved-rebuild'
alias revdep='sudo revdep-rebuild'
alias eq='equery'
alias es='eix'
alias news='eselect news read'
alias dispatch='sudo dispatch-conf'

# Powerlevel10k prompt customization
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF
    # Make the shell's default EDITOR follow --editor (neovim -> nvim; otherwise vim).
    local _ed="vim"; [[ "$EDITOR_CHOICE" == neovim ]] && _ed="nvim"
    sed -i "s|^export EDITOR=.*|export EDITOR='${_ed}'|" "$tmp"
    run_priv cp "$tmp" "$dest"
    run_priv chown "$TARGET_USER" "$dest"
    rm -f "$tmp"
    log_ok "Wrote ${dest}"
}

_write_vimrc() {
    local dest="${TARGET_HOME}/.vimrc"
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] write ${dest} (owner ${TARGET_USER})"
        return 0
    fi
    [[ -f "$dest" ]] && return 0   # don't clobber an existing vimrc
    local tmp; tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
" ~/.vimrc - sane defaults (gentoo-post-install)
set nocompatible
syntax on
filetype plugin indent on
set number relativenumber
set expandtab shiftwidth=4 tabstop=4 softtabstop=4
set autoindent smartindent
set incsearch hlsearch ignorecase smartcase
set wildmenu
set mouse=a
set clipboard=unnamedplus
set undofile
set background=dark
set laststatus=2
set encoding=utf-8
EOF
    run_priv cp "$tmp" "$dest"
    run_priv chown "$TARGET_USER" "$dest"
    rm -f "$tmp"
    log_ok "Wrote ${dest}"
}

step_15_shell() {
    log_section "Step 15 - Shell & terminal"
    if ! $INSTALL_SHELL; then
        log_skip "Shell setup disabled (--shell to enable; default on 'desktop' profile)."
        return 0
    fi
    _resolve_target_user
    log_info "Configuring shell for user '${TARGET_USER}' (${TARGET_HOME})."

    emerge_install app-shells/zsh dev-vcs/git net-misc/curl || log_warn "Base shell packages failed."
    case "$EDITOR_CHOICE" in
        vim)    emerge_install app-editors/vim ;;
        neovim) emerge_install app-editors/neovim ;;
        both)   emerge_install app-editors/vim app-editors/neovim ;;
        none)   : ;;
    esac

    # oh-my-zsh (git clone - deterministic, no curl|sh)
    user_do "test -d \$HOME/.oh-my-zsh || git clone --depth=1 ${URL_OHMYZSH_REPO} \$HOME/.oh-my-zsh" \
        || log_warn "oh-my-zsh clone failed."

    # powerlevel10k + plugins into ZSH_CUSTOM
    # shellcheck disable=SC2016  # $HOME must stay literal - expanded by the target user's shell
    local zc='$HOME/.oh-my-zsh/custom'
    user_do "test -d ${zc}/themes/powerlevel10k || git clone --depth=1 ${URL_POWERLEVEL10K} ${zc}/themes/powerlevel10k" || log_warn "p10k clone failed."
    user_do "test -d ${zc}/plugins/zsh-autosuggestions || git clone --depth=1 ${URL_PLUGIN_AUTOSUGGESTIONS} ${zc}/plugins/zsh-autosuggestions" || true
    user_do "test -d ${zc}/plugins/zsh-syntax-highlighting || git clone --depth=1 ${URL_PLUGIN_SYNTAX_HIGHLIGHTING} ${zc}/plugins/zsh-syntax-highlighting" || true
    user_do "test -d ${zc}/plugins/zsh-completions || git clone --depth=1 ${URL_PLUGIN_COMPLETIONS} ${zc}/plugins/zsh-completions" || true

    _write_zshrc

    # Editors config
    case "$EDITOR_CHOICE" in
        vim|both) _write_vimrc ;;
    esac
    if [[ "$EDITOR_CHOICE" == "neovim" || "$EDITOR_CHOICE" == "both" ]]; then
        user_do "test -d \$HOME/.config/nvim || { git clone --depth=1 ${URL_LAZYVIM} \$HOME/.config/nvim && rm -rf \$HOME/.config/nvim/.git; }" \
            || log_warn "LazyVim starter clone failed."
    fi

    # Default shell
    if $SET_DEFAULT_SHELL; then
        local zsh_path; zsh_path="$(command -v zsh 2>/dev/null || echo /bin/zsh)"
        if $DRY_RUN; then
            echo "    ${ICON_SKIP} [dry-run] chsh -s ${zsh_path} ${TARGET_USER}"
        else
            run_priv chsh -s "$zsh_path" "$TARGET_USER" || log_warn "Could not set zsh as default shell for ${TARGET_USER}."
        fi
    fi
    log_warn "Run 'p10k configure' in a new zsh session to tune the prompt."
    log_ok "Step 15 complete."
}

step_16_fonts() {
    log_section "Step 16 - Nerd Fonts"
    if ! $INSTALL_FONTS; then
        log_skip "Nerd Fonts disabled (--fonts to enable; default on 'desktop' profile)."
        return 0
    fi
    [[ -z "$TARGET_USER" ]] && _resolve_target_user
    log_info "Installing Nerd Fonts for '${TARGET_USER}': ${NERD_FONTS_LIST}"
    emerge_install media-libs/fontconfig app-arch/unzip net-misc/curl || log_warn "Font prerequisites failed."
    local font
    for font in $NERD_FONTS_LIST; do
        log_info "  → ${font}"
        user_do "set -e; d=\$HOME/.local/share/fonts/${font}; mkdir -p \"\$d\"; t=\$(mktemp); curl -fsSL ${URL_NERD_FONTS_DL}/${font}.zip -o \"\$t\" && unzip -oq \"\$t\" -d \"\$d\" && rm -f \"\$t\"" \
            || log_warn "Failed to install font ${font} (check the name / network)."
    done
    user_do "fc-cache -f >/dev/null 2>&1 || true"
    log_ok "Step 16 complete."
}

_detect_video_cards() {
    local vc="" gpu=""
    have lspci || return 0
    gpu="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || true)"
    grep -qi 'intel' <<< "$gpu" && vc+=" intel"
    grep -qiE 'amd|radeon|ati' <<< "$gpu" && vc+=" amdgpu radeonsi"
    grep -qi 'nvidia' <<< "$gpu" && vc+=" nouveau"   # FOSS driver by default
    echo "${vc# }"
}

step_17_desktop() {
    log_section "Step 17 - Desktop stack"
    if ! $INSTALL_DESKTOP; then
        log_skip "Desktop stack disabled (--desktop to enable; default on 'desktop' profile)."
        return 0
    fi
    # VIDEO_CARDS (make.conf)
    local vc="$VIDEO_CARDS_OVERRIDE"
    if [[ -z "$vc" ]]; then
        have lspci || emerge_install sys-apps/pciutils || true
        vc="$(_detect_video_cards)"
    fi
    if [[ -n "$vc" ]]; then
        make_conf_set "VIDEO_CARDS" "$vc"
    else
        log_warn "Could not detect a GPU - set VIDEO_CARDS in make.conf manually (intel/amdgpu/nouveau/nvidia)."
    fi
    # INPUT_DEVICES: libinput is the modern default (covers mouse/touchpad/keyboard).
    make_conf_set "INPUT_DEVICES" "libinput"

    # Session base: dbus (+ elogind on OpenRC; systemd-logind is built in)
    emerge_install sys-apps/dbus || log_warn "dbus install failed."
    if [[ "$INIT_SYSTEM" == openrc ]]; then
        emerge_install sys-auth/elogind || log_warn "elogind install failed."
        service_enable_start elogind boot 2>/dev/null || true
        service_enable_start dbus 2>/dev/null || true
    fi

    # Display server
    case "$DESKTOP_DISPLAY" in
        x11|both) emerge_install x11-base/xorg-server || log_warn "Xorg install failed." ;;
    esac
    if [[ "$DESKTOP_DISPLAY" == "wayland" || "$DESKTOP_DISPLAY" == "both" ]]; then
        log_info "Wayland selected - install a compositor of your choice (sway/hyprland/gnome/kde) separately."
    fi

    # Audio (PipeWire)
    if $DESKTOP_AUDIO; then
        emerge_install media-video/pipewire media-video/wireplumber || log_warn "PipeWire install failed."
        log_info "Enable PipeWire per-user (systemd: 'systemctl --user enable --now pipewire wireplumber'; OpenRC: session autostart)."
    fi

    # Networking
    if $DESKTOP_NM; then
        emerge_install net-misc/networkmanager || log_warn "NetworkManager install failed."
        service_enable_start NetworkManager 2>/dev/null || log_warn "Could not enable NetworkManager."
    fi

    [[ -n "$vc" ]] && log_warn "VIDEO_CARDS set - rebuild affected packages: emerge -uUDN @world"
    log_ok "Step 17 complete."
}

_ensure_eselect_repository() {
    # Make sure app-eselect/eselect-repository is usable (git for git-synced overlays).
    if run_priv eselect repository list >/dev/null 2>&1; then
        return 0
    fi
    emerge_install app-eselect/eselect-repository dev-vcs/git || return 1
    run_priv mkdir -p /etc/portage/repos.conf
}

_enable_overlay() {
    # _enable_overlay <name>|<name=git-url>  - enable an official overlay or add a custom one, then sync.
    local spec="$1" name url
    _ensure_eselect_repository || { log_warn "eselect-repository unavailable; cannot enable '${spec}'."; return 1; }
    if [[ "$spec" == *=* ]]; then
        name="${spec%%=*}"; url="${spec#*=}"
        log_info "Adding custom overlay ${name} (${url})"
        run_priv eselect repository add "$name" git "$url" || log_warn "Could not add overlay ${name}."
    else
        name="$spec"
        # Skip if already enabled (best-effort; noisy-safe in dry-run).
        if ! $DRY_RUN && run_priv eselect repository list -i 2>/dev/null | grep -qw "$name"; then
            log_skip "Overlay ${name} already enabled."
            return 0
        fi
        log_info "Enabling overlay ${name}"
        run_priv eselect repository enable "$name" || { log_warn "Could not enable overlay ${name} (check: eselect repository list)."; return 1; }
    fi
    run_priv emaint sync -r "$name" || log_warn "Sync of overlay ${name} failed."
}

step_18_repositories() {
    log_section "Step 18 - Overlays / repositories"
    if [[ -z "$OVERLAYS" ]]; then
        log_skip "No overlays requested (--overlay guru,pentoo,... or name=git-url)."
        return 0
    fi
    local ov
    for ov in $OVERLAYS; do
        _enable_overlay "$ov"
    done
    if have eix-update && ! $DRY_RUN; then run_priv eix-update >/dev/null 2>&1 || true; fi
    log_ok "Step 18 complete - repos in /etc/portage/repos.conf/ (eselect-repo.conf)."
}

_app_spec() {
    # Friendly name -> "atom|overlay|license". Empty when unknown. A raw cat/atom
    # (contains "/") passes through. Overlay atoms are best-effort - verify against
    # the current overlay tree.
    case "$1" in
        firefox)      echo "www-client/firefox-bin||" ;;
        chromium)     echo "www-client/chromium||" ;;
        chrome)       echo "www-client/google-chrome||google-chrome" ;;
        vlc)          echo "media-video/vlc||" ;;
        mpv)          echo "media-video/mpv||" ;;
        obs)          echo "media-video/obs-studio||" ;;
        gimp)         echo "media-gfx/gimp||" ;;
        inkscape)     echo "media-gfx/inkscape||" ;;
        libreoffice)  echo "app-office/libreoffice-bin||" ;;
        thunderbird)  echo "mail-client/thunderbird-bin||" ;;
        keepassxc)    echo "app-admin/keepassxc||" ;;
        spotify)      echo "media-sound/spotify||spotify" ;;
        obsidian)     echo "app-text/obsidian|r7l|" ;;
        discord)      echo "net-im/discord||" ;;
        signal)       echo "net-im/signal-desktop-bin||" ;;
        */*)          echo "$1||" ;;
        *)            echo "" ;;
    esac
}

_apps_profile_list() {
    case "$1" in
        daily)  echo "firefox vlc keepassxc" ;;
        dev)    echo "firefox keepassxc obsidian" ;;
        media)  echo "vlc mpv obs gimp" ;;
        gaming) echo "discord steam" ;;   # "steam" routes to the native Steam installer
        *)      echo "" ;;
    esac
}

_install_steam_native() {
    # Native Steam via the steam-overlay. Requires a multilib profile. Ref: wiki Steam.
    log_section "Steam (native)"
    if [[ "$MULTILIB" == no ]]; then
        log_err "Steam needs a MULTILIB profile; current profile is no-multilib (${DISTRO_PROFILE})."
        log_warn "Switch first:  eselect profile list | grep -v no-multilib"
        log_warn "               eselect profile set <n> && emerge -e @world   # then rerun --steam"
        return 1
    fi
    log_warn "Native Steam pulls a large 32-bit (abi_x86_32) dependency tree - the first build is long."
    _enable_overlay steam-overlay || { log_err "Could not enable steam-overlay."; return 1; }

    write_root_file "${PKG_LICENSE_DIR}/steam" <<'EOF'
# Managed by gentoo-post-install
games-util/steam-launcher ValveSteamLicense
EOF
    write_root_file "${PKG_ACCEPT_DIR}/steam" <<'EOF'
# Managed by gentoo-post-install
*/*::steam-overlay
games-util/game-device-udev-rules
sys-libs/libudev-compat
EOF

    log_info "Installing games-util/steam-launcher (autounmask writes the abi_x86_32 USE deps) ..."
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] emerge --autounmask-write --autounmask-continue games-util/steam-launcher"
    else
        run_priv emerge --ask=n --autounmask-write=y --autounmask-license=y --autounmask-continue=y games-util/steam-launcher \
            || log_warn "Steam needs review - run 'dispatch-conf' to accept the written USE/keyword changes, then re-run --steam."
    fi
    log_ok "Steam step done (launch 'steam' once to finish its first-run bootstrap)."
}

step_19_apps() {
    log_section "Step 19 - Applications"
    local list="${APPS//,/ }"
    if [[ -n "$APPS_PROFILE" ]]; then
        local pl; pl="$(_apps_profile_list "$APPS_PROFILE")"
        if [[ -z "$pl" ]]; then
            log_warn "Unknown apps-profile '${APPS_PROFILE}' (daily|dev|media|gaming)."
        else
            list="${pl} ${list}"
        fi
    fi
    if [[ -z "${list// }" ]] && ! $INSTALL_STEAM; then
        log_skip "No applications requested (--apps ... / --apps-profile ... / --steam)."
        return 0
    fi

    local app spec atom overlay lic
    local atoms=() overlays=() licenses=()
    for app in $list; do
        if [[ "$app" == "steam" ]]; then INSTALL_STEAM=true; continue; fi
        spec="$(_app_spec "$app")"
        if [[ -z "$spec" ]]; then
            log_warn "Unknown app '${app}' - skipped (pass a raw category/atom to force it)."
            continue
        fi
        IFS='|' read -r atom overlay lic <<< "$spec"
        atoms+=("$atom")
        [[ -n "$overlay" ]] && overlays+=("$overlay")
        [[ -n "$lic" ]] && licenses+=("${atom} ${lic}")
    done

    # Auto-enable the overlays these apps need (deduplicated).
    if [[ ${#overlays[@]} -gt 0 ]]; then
        local o
        for o in $(printf '%s\n' "${overlays[@]}" | sort -u); do
            _enable_overlay "$o"
        done
    fi

    # Per-package licenses (e.g. google-chrome, spotify).
    if [[ ${#licenses[@]} -gt 0 ]]; then
        run_priv mkdir -p "$PKG_LICENSE_DIR"
        if $DRY_RUN; then
            echo "    ${ICON_SKIP} [dry-run] write ${#licenses[@]} license entr(y/ies) to ${PKG_LICENSE_DIR}/gpi-apps"
        else
            { echo "# Managed by gentoo-post-install"; printf '%s\n' "${licenses[@]}"; } \
                | run_priv tee "${PKG_LICENSE_DIR}/gpi-apps" >/dev/null
        fi
    fi

    if [[ ${#atoms[@]} -gt 0 ]]; then
        log_info "Installing: ${atoms[*]}"
        emerge_install "${atoms[@]}" || log_warn "Some applications failed to install (check keywords/licenses)."
    fi

    if $INSTALL_STEAM; then
        _install_steam_native
    fi
    log_ok "Step 19 complete."
}

_de_package() {
    case "$1" in
        kde)      echo "kde-plasma/plasma-meta" ;;
        gnome)    echo "gnome-base/gnome" ;;
        sway)     echo "gui-wm/sway" ;;
        hyprland) echo "gui-wm/hyprland" ;;
        xfce)     echo "xfce-base/xfce4-meta" ;;
        *)        echo "" ;;
    esac
}

_default_dm_for_de() {
    case "$1" in
        kde)           echo "sddm" ;;
        gnome)         echo "gdm" ;;
        xfce)          echo "lightdm" ;;
        sway|hyprland) echo "greetd" ;;
        *)             echo "none" ;;
    esac
}

_dm_package() {
    case "$1" in
        sddm)    echo "x11-misc/sddm" ;;
        gdm)     echo "gnome-base/gdm" ;;
        lightdm) echo "x11-misc/lightdm x11-misc/lightdm-gtk-greeter" ;;
        greetd)  echo "gui-libs/greetd gui-apps/tuigreet" ;;
        *)       echo "" ;;
    esac
}

_enable_display_manager() {
    # Enable a display manager the Gentoo way: generic 'display-manager' service on
    # OpenRC (DISPLAYMANAGER in /etc/conf.d/display-manager), or systemctl on systemd.
    # greetd ships its own OpenRC service. Ref: wiki Display manager.
    local dm="$1"
    case "$INIT_SYSTEM" in
        systemd)
            run_priv systemctl enable "${dm}.service"
            ;;
        openrc)
            if [[ "$dm" == greetd ]]; then
                run_priv rc-update add greetd default
                return 0
            fi
            emerge_install gui-libs/display-manager-init || log_warn "display-manager-init install failed."
            if $DRY_RUN; then
                echo "    ${ICON_SKIP} [dry-run] set DISPLAYMANAGER=\"${dm}\" in /etc/conf.d/display-manager"
            elif run_priv grep -qE '^[[:space:]]*DISPLAYMANAGER=' /etc/conf.d/display-manager 2>/dev/null; then
                run_priv sed -i -E "s|^[[:space:]]*DISPLAYMANAGER=.*|DISPLAYMANAGER=\"${dm}\"|" /etc/conf.d/display-manager
            else
                printf 'DISPLAYMANAGER="%s"\n' "$dm" | run_priv tee -a /etc/conf.d/display-manager >/dev/null
            fi
            run_priv rc-update add display-manager default
            ;;
        *) log_warn "Unknown init system; enable ${dm} manually." ;;
    esac
}

step_20_desktop_environment() {
    log_section "Step 20 - Desktop environment"
    if [[ -z "$DE" || "$DE" == none ]]; then
        log_skip "No desktop environment selected (--de kde|gnome|sway|hyprland|xfce)."
        return 0
    fi
    local depkg; depkg="$(_de_package "$DE")"
    [[ -z "$depkg" ]] && { log_err "Unknown DE '${DE}'."; return 1; }

    # Session / seat prerequisites (elogind on OpenRC covers Wayland seat management).
    emerge_install sys-apps/dbus || true
    if [[ "$INIT_SYSTEM" == openrc ]]; then
        emerge_install sys-auth/elogind || log_warn "elogind install failed."
        run_priv rc-update add elogind boot 2>/dev/null || true
    fi

    log_info "Installing ${DE} (${depkg}) ..."
    local pk; read -r -a pk <<< "$depkg"
    emerge_install "${pk[@]}" || { log_err "${DE} install failed (may need a profile/keywords: eselect profile list | grep ${DE})."; return 1; }
    if [[ "$INIT_SYSTEM" == openrc && ( "$DE" == kde || "$DE" == gnome ) ]]; then
        log_warn "Tip: the matching OpenRC profile helps - eselect profile list | grep -E '${DE}(/|$)'"
    fi

    # Display manager
    local dm="$DM"
    [[ -z "$dm" || "$dm" == auto ]] && dm="$(_default_dm_for_de "$DE")"
    if [[ "$dm" == none ]]; then
        log_info "No display manager - start ${DE} from a TTY (dbus-run-session ${DE}, or ~/.xinitrc)."
    else
        local dmpkg; dmpkg="$(_dm_package "$dm")"
        if [[ -z "$dmpkg" ]]; then
            log_warn "Unknown display manager '${dm}'."
        else
            log_info "Installing display manager ${dm} (${dmpkg}) ..."
            local dpk; read -r -a dpk <<< "$dmpkg"
            emerge_install "${dpk[@]}" || log_warn "${dm} install failed."
            _enable_display_manager "$dm"
        fi
    fi
    log_ok "Step 20 complete - reboot (or start the DM) to reach the graphical login."
}

step_21_minimize_surface() {
    log_section "Step 21 - Attack surface minimization"
    if ! $MINIMIZE_SURFACE; then
        log_skip "Surface minimization disabled (--minimize-surface)."
        return 0
    fi

    # 1) Blacklist rarely-needed / historically-risky modules (install = /bin/true blocks load).
    {
        echo "# Managed by gentoo-post-install - attack surface reduction"
        local m
        for m in firewire-core firewire-ohci thunderbolt \
                 cramfs freevxfs jffs2 hfs hfsplus udf \
                 dccp sctp rds tipc; do
            echo "install ${m} /bin/true"
        done
    } | write_root_file /etc/modprobe.d/gpi-blacklist.conf

    # 2) Kernel/opsec sysctl (kexec off, strict ptrace, BPF hardening).
    {
        cat <<'EOF'
# Managed by gentoo-post-install - opsec sysctl
kernel.kexec_load_disabled = 1
kernel.yama.ptrace_scope = 2
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
kernel.perf_event_paranoid = 3
dev.tty.ldisc_autoload = 0
EOF
    } | write_root_file /etc/sysctl.d/99-gpi-opsec.conf
    if have sysctl && ! $DRY_RUN; then
        run_priv sysctl --system >/dev/null 2>&1 || log_warn "sysctl --system returned non-zero."
    fi

    # 3) Disable core dumps (limits + sysctl already sets suid_dumpable via base hardening).
    printf '# Managed by gentoo-post-install\n* hard core 0\n* soft core 0\n' \
        | write_root_file /etc/security/limits.d/gpi-coredump.conf

    # 4) Mask a few commonly-unneeded, network-exposed services (no-op if absent).
    local svc
    for svc in avahi-daemon cups cupsd rpcbind nfs; do
        service_disable "$svc"
    done

    log_warn "Blacklisted modules & disabled services can break hardware/printing/mDNS - review /etc/modprobe.d/gpi-blacklist.conf and re-enable what you need."
    log_ok "Step 21 complete."
}

step_22_logs() {
    log_section "Step 22 - Log-footprint minimization (${LOGS_LEVEL})"
    if [[ "$LOGS_LEVEL" == off ]]; then
        log_skip "Log minimization off (--logs reduce|ephemeral)."
        return 0
    fi
    log_warn "PRIVACY choice with a real cost: less logging = harder to debug AND harder to detect a real intrusion."
    [[ -z "$TARGET_USER" ]] && _resolve_target_user

    # 1) journald (systemd): reduced retention, or fully volatile (RAM) for 'ephemeral'.
    if [[ "$INIT_SYSTEM" == systemd ]]; then
        if [[ "$LOGS_LEVEL" == ephemeral ]]; then
            printf '[Journal]\nStorage=volatile\nRuntimeMaxUse=50M\n' \
                | write_root_file /etc/systemd/journald.conf.d/gpi-logs.conf
        else
            printf '[Journal]\nStorage=persistent\nSystemMaxUse=50M\nMaxRetentionSec=3day\n' \
                | write_root_file /etc/systemd/journald.conf.d/gpi-logs.conf
        fi
        if ! $DRY_RUN; then run_priv systemctl restart systemd-journald 2>/dev/null || true; fi
    else
        log_info "OpenRC: reduce your syslog/logrotate retention; a fully ephemeral setup needs /var/log on tmpfs (manual)."
    fi

    # 2) Shell history off (system-wide) + clear the target user's history.
    #    Use `unset HISTFILE` (no file at all) rather than HISTFILE=/dev/null - pointing
    #    a history file at the /dev/null device is a known footgun (tools that rotate or
    #    recreate the history file can clobber the device).
    printf '# Managed by gentoo-post-install - no shell history\nunset HISTFILE\nexport HISTSIZE=0\nexport SAVEHIST=0\n' \
        | write_root_file /etc/profile.d/gpi-nohistory.sh
    # shellcheck disable=SC2016  # $HOME must expand in the target user's shell, not here
    user_do 'rm -f "$HOME/.bash_history" "$HOME/.zsh_history" 2>/dev/null; history -c 2>/dev/null || true'

    # 3) Restrict dmesg; disable core dumps to disk.
    printf '# Managed by gentoo-post-install - log/telemetry restriction\nkernel.dmesg_restrict = 1\nkernel.core_pattern = |/bin/false\n' \
        | write_root_file /etc/sysctl.d/99-gpi-logs.conf
    if have sysctl && ! $DRY_RUN; then
        run_priv sysctl --system >/dev/null 2>&1 || true
    fi
    log_ok "Step 22 complete."
}

_set_password() {
    # _set_password <user> <label>  - masked prompt, applied via chpasswd on STDIN (never argv).
    local user="$1" label="${2:-password for $1}"
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] set ${label} (masked prompt -> chpasswd on stdin)"
        return 0
    fi
    # A masked prompt needs a real terminal. In a non-interactive run (piped stdin,
    # cron, CI) reading fd 0 would consume unrelated input or take EOF as an empty
    # password, so skip deterministically - a new account stays locked until a
    # password is set, which is the safe default.
    if [[ ! -t 0 ]]; then
        log_warn "Non-interactive shell: skipping ${label}. Set it later with:  passwd ${user}"
        return 0
    fi
    local pw pw2
    read -rsp "New ${label}: " pw; echo
    read -rsp "Confirm ${label}: " pw2; echo
    if [[ "$pw" != "$pw2" ]]; then log_err "Passwords differ - not changing ${user}."; unset pw pw2; return 1; fi
    if [[ -z "$pw" ]]; then log_warn "Empty password - skipping ${user}."; unset pw pw2; return 1; fi
    if printf '%s:%s' "$user" "$pw" | run_priv chpasswd; then log_ok "Password set for ${user}."; else log_err "chpasswd failed for ${user}."; fi
    unset pw pw2
}

_write_sudoers_dropin() {
    # _write_sudoers_dropin <basename> <content>  - validated with visudo -c, installed 0440.
    local path="${SUDOERS_DIR}/$1" content="$2"
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] write '${content}' to ${path} (validated with visudo -c)"
        return 0
    fi
    local tmp; tmp="$(mktemp)"
    printf '# Managed by gentoo-post-install\n%s\n' "$content" > "$tmp"
    if run_priv visudo -c -f "$tmp" >/dev/null 2>&1; then
        run_priv install -m 0440 -o root -g root "$tmp" "$path" && log_ok "sudoers: ${path}"
    else
        log_err "sudoers validation failed for ${path} - not installed."
    fi
    rm -f "$tmp"
}

_ensure_wheel_sudo() {
    have sudo || emerge_install app-admin/sudo || log_warn "sudo install failed."
    _write_sudoers_dropin "00-gpi-wheel" "%wheel ALL=(ALL:ALL) ALL"
}

_parse_user_spec() {
    # spec: name[:sudo][:nopasswd][:groups=a,b][:shell=/bin/bash] -> "name|sudo|nopasswd|groups|shell"
    local spec="$1" name sudo=false nopasswd=false groups="" shell="/bin/bash"
    local -a parts; IFS=':' read -ra parts <<< "$spec"
    name="${parts[0]}"
    local i p
    for ((i=1; i<${#parts[@]}; i++)); do
        p="${parts[i]}"
        case "$p" in
            sudo)      sudo=true ;;
            nopasswd)  nopasswd=true ;;
            groups=*)  groups="${p#groups=}" ;;
            shell=*)   shell="${p#shell=}" ;;
            *)         log_warn "Unknown --user option '${p}' (sudo|nopasswd|groups=..|shell=..)." ;;
        esac
    done
    printf '%s|%s|%s|%s|%s' "$name" "$sudo" "$nopasswd" "$groups" "$shell"
}

_create_user_from_spec() {
    local name sudo nopasswd groups shell
    IFS='|' read -r name sudo nopasswd groups shell <<< "$(_parse_user_spec "$1")"
    [[ -z "$name" ]] && { log_warn "Empty --user spec."; return 1; }

    if getent passwd "$name" >/dev/null 2>&1; then
        log_skip "User ${name} exists - adjusting groups/sudo only."
    else
        run_priv useradd -m -s "$shell" "$name" && log_ok "Created user ${name} (shell ${shell})."
    fi
    [[ -n "$groups" ]] && run_priv usermod -aG "$groups" "$name"

    if [[ "$sudo" == true ]]; then
        run_priv usermod -aG wheel "$name"
        _ensure_wheel_sudo
        if [[ "$nopasswd" == true ]]; then
            log_warn "NOPASSWD sudo for ${name}: anyone with this user's session gets passwordless root. Opt-in only."
            _write_sudoers_dropin "10-gpi-${name}" "${name} ALL=(ALL:ALL) NOPASSWD: ALL"
        fi
    fi
    # Login password (masked). Not created accounts stay locked until a password is set.
    _set_password "$name" "password for ${name}"
}

_disable_root() {
    # Require a NON-root wheel member as fallback admin, else refuse (lock-out guard).
    local non_root; non_root="$(getent group wheel 2>/dev/null | cut -d: -f4 | tr ',' '\n' | grep -vx root | paste -sd, -)"
    if [[ -z "$non_root" ]]; then
        log_err "Refusing --disable-root: no NON-root user in 'wheel' - you would lock yourself out. Create one first (--user name:sudo)."
        return 1
    fi
    log_warn "Locking root (fallback admins in wheel: ${non_root})."
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] passwd -l root ; usermod -s /sbin/nologin root"
        return 0
    fi
    run_priv passwd -l root && log_ok "Root password locked."
    run_priv usermod -s /sbin/nologin root && log_ok "Root shell -> /sbin/nologin."
}

step_23_accounts() {
    log_section "Step 23 - Accounts (users, groups, root)"
    local did=false g

    for g in $NEW_GROUPS; do
        did=true
        if getent group "$g" >/dev/null 2>&1; then
            log_skip "Group ${g} already exists."
        else
            run_priv groupadd "$g" && log_ok "Created group ${g}."
        fi
    done

    if [[ -n "$NEW_USERS" ]]; then
        did=true
        local spec
        while IFS= read -r spec; do
            [[ -z "$spec" ]] && continue
            _create_user_from_spec "$spec"
        done <<< "$NEW_USERS"
    fi

    if $ROOT_PASSWORD; then did=true; _set_password root "root password"; fi
    if $DISABLE_ROOT;  then did=true; _disable_root; fi

    $did || log_skip "No account changes requested (--user / --group / --root-password / --disable-root)."
    log_ok "Step 23 complete."
}

# ==============================================
# ROLLBACK
# ==============================================
_rollback_remove() {
    # Remove a managed drop-in only if it still carries our marker (safety).
    local f="$1"
    if $DRY_RUN; then
        echo "    ${ICON_SKIP} [dry-run] remove (if managed) ${f}"
        return 0
    fi
    run_priv test -f "$f" 2>/dev/null || return 0
    if run_priv grep -q "gentoo-post-install" "$f" 2>/dev/null; then
        run_priv rm -f "$f"
        log_ok "Removed ${f}"
    else
        log_warn "Kept ${f} (missing our marker - not touching an unmanaged file)."
    fi
}

_rollback_sudoers() {
    # Remove the sudoers drop-ins we created: 00-gpi-wheel and the per-user
    # 10-gpi-<name> NOPASSWD/sudo grants (dynamic names). Each removal is still
    # guarded by the managed-marker check in _rollback_remove, so an unmanaged
    # file that happens to match the glob is left alone. Leaving a NOPASSWD grant
    # behind after a rollback would be a real security hole.
    local sd
    while IFS= read -r sd; do
        [[ -n "$sd" ]] && _rollback_remove "$sd"
    done < <(run_priv sh -c "ls ${SUDOERS_DIR}/00-gpi-wheel ${SUDOERS_DIR}/10-gpi-* 2>/dev/null" || true)
}

do_rollback() {
    log_section "Rollback - revert gentoo-post-install changes"
    log_warn "Restores make.conf from backup and removes managed drop-in files."
    log_warn "Does NOT uninstall packages, disable services, or modify /etc/nftables.conf."
    _resolve_target_user

    local managed=(
        "${PKG_USE_DIR}/00cpu-flags"
        "${PKG_USE_DIR}/10-baseline"
        "${PKG_USE_DIR}/20-installkernel"
        "${PKG_USE_DIR}/30-microcode"
        "/etc/kernel/config.d/90-gpi-hardening.config"
        "/etc/kernel/config.d/90-gpi-performance.config"
        "${PKG_LICENSE_DIR}/gpi-apps"
        "${PKG_LICENSE_DIR}/steam"
        "${PKG_ACCEPT_DIR}/steam"
        "/etc/sysctl.d/99-gentoo-post-install.conf"
        "/etc/sysctl.d/99-gpi-opsec.conf"
        "/etc/sysctl.d/99-gpi-logs.conf"
        "/etc/modprobe.d/gpi-blacklist.conf"
        "/etc/security/limits.d/gpi-coredump.conf"
        "/etc/systemd/journald.conf.d/gpi-logs.conf"
        "/etc/profile.d/gpi-nohistory.sh"
        "${BINREPOS_DIR}/gentoobinhost.conf"
        "/etc/fail2ban/jail.d/99-gentoo-post-install.local"
        "/etc/ssh/sshd_config.d/99-gentoo-post-install.conf"
    )

    echo "Plan:"
    if [[ -f "${MAKE_CONF}.gpi.bak" ]]; then
        echo "  restore  ${MAKE_CONF}  <=  ${MAKE_CONF}.gpi.bak"
    else
        echo "  (no make.conf backup found - make.conf will be left as-is)"
    fi
    local f
    for f in "${managed[@]}"; do echo "  remove   ${f} (if managed)"; done
    echo "  remove   ${SUDOERS_DIR}/00-gpi-wheel and ${SUDOERS_DIR}/10-gpi-* (managed sudoers grants, if any)"

    if ! confirm "Proceed with rollback?"; then
        log_skip "Rollback cancelled."
        return 0
    fi

    if [[ -f "${MAKE_CONF}.gpi.bak" ]]; then
        run_priv cp -a "${MAKE_CONF}.gpi.bak" "$MAKE_CONF"
        log_ok "Restored make.conf from ${MAKE_CONF}.gpi.bak"
    else
        log_warn "No make.conf backup; leaving ${MAKE_CONF} untouched."
    fi

    for f in "${managed[@]}"; do
        _rollback_remove "$f"
    done
    _rollback_sudoers

    if have sysctl && ! $DRY_RUN; then
        run_priv sysctl --system >/dev/null 2>&1 || true
    fi

    log_warn "Firewall (/etc/nftables.conf) left untouched - a pre-change backup is at /etc/nftables.conf.gpi.bak if you configured one."
    log_warn "Per-user shell files keep their backups (e.g. ${TARGET_HOME}/.zshrc.gpi.bak)."
    log_warn "Managed sudoers grants were removed, but user accounts and groups were NOT deleted (data-safety)."
    log_warn "Installed packages and enabled services were NOT reverted."
    log_warn "Changes appended into shared files are NOT auto-reverted - edit them by hand if needed:"
    log_warn "    KSPP kernel params (GRUB_CMDLINE_LINUX in /etc/default/grub, or /etc/kernel/cmdline),"
    log_warn "    the 'Include /etc/ssh/sshd_config.d/*.conf' line in /etc/ssh/sshd_config,"
    log_warn "    and DISPLAYMANAGER in /etc/conf.d/display-manager (OpenRC)."
    log_ok "Rollback complete."
}

# ==============================================
# ORCHESTRATION
# ==============================================
_step_selected() {
    local num="$1"
    [[ -z "$SELECTED_STEPS" ]] && return 0
    [[ " $SELECTED_STEPS " == *" $num "* ]]
}

run_selected_steps() {
    local entry num fn desc rc=0
    for entry in "${STEP_REGISTRY[@]}"; do
        IFS='|' read -r num fn desc <<< "$entry"
        if _step_selected "$num"; then
            if ! "$fn"; then
                rc=1
                log_err "Step ${num} (${desc}) failed; continuing."
            fi
        else
            log_skip "Skipping step ${num} (${desc})."
        fi
    done
    return $rc
}

show_completion_summary() {
    log_section "Summary"
    log_ok "Profile        : $SYSTEM_PROFILE"
    log_ok "Init system    : $INIT_SYSTEM"
    log_ok "Portage profile: ${DISTRO_PROFILE:-unknown}"
    log_ok "CPU / RAM      : ${NPROC} cores / ${RAM_GB} GB"
    $ENABLE_BINHOST && log_ok "Binhost        : enabled (${BINHOST_URI})"
    echo ""
    log_info "Next steps you may want to run manually:"
    echo "    - dispatch-conf         # merge pending config file updates"
    echo "    - eselect news read     # re-check important news items"
    echo "    - emerge -uUDN @world   # rebuild after USE flag changes"
}

cleanup() {
    :
}

handle_interrupt() {
    echo ""
    log_warn "Interrupted - exiting."
    cleanup
    exit "$EXIT_FAILURE"
}

# ==============================================
# MAIN
# ==============================================
show_run_plan() {
    log_section "Run plan"
    log_info "Profile        : ${SYSTEM_PROFILE}"
    log_info "Init system    : ${INIT_SYSTEM}"
    log_info "CPU / RAM      : ${NPROC} cores / ${RAM_GB} GB"
    log_info "Portage profile: ${DISTRO_PROFILE:-unknown} (multilib=${MULTILIB})"
    log_info "make.conf tune : ${TUNE_MAKECONF} (march-native=${SET_MARCH_NATIVE}, cpu-flags=${SET_CPU_FLAGS})"
    log_info "Binhost        : ${ENABLE_BINHOST}"
    local fw="off"; $CONFIGURE_FIREWALL && fw="$FIREWALL"
    log_info "Firewall       : ${fw}"
    log_info "Hardening      : sysctl=${HARDEN_SYSCTL} ssh=${HARDEN_SSH} audit=${INSTALL_AUDIT} fail2ban=${INSTALL_FAIL2BAN} apparmor=${INSTALL_APPARMOR}"
    log_info "Shell/Desktop  : shell=${INSTALL_SHELL} fonts=${INSTALL_FONTS} desktop=${INSTALL_DESKTOP}"
    local entry num _f _d list=""
    for entry in "${STEP_REGISTRY[@]}"; do
        IFS='|' read -r num _f _d <<< "$entry"
        _step_selected "$num" && list+="${num} "
    done
    log_info "Steps to run   : ${list:-none}"
}

_start_logging() {
    [[ -z "$LOG_FILE" ]] && return 0
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    {
        echo ""
        echo "===== ${SCRIPT_NAME} v${SCRIPT_VERSION} - $(date '+%Y-%m-%d %H:%M:%S') ====="
    } >> "$LOG_FILE" 2>/dev/null || { log_warn "Cannot write to ${LOG_FILE}; continuing without a log."; LOG_FILE=""; return 0; }
    # Tee stdout+stderr to the log for the remainder of the run.
    exec > >(tee -a "$LOG_FILE") 2>&1
    log_info "Transcript: ${LOG_FILE}"
}

main() {
    trap handle_interrupt SIGINT SIGTERM

    _init_symbols
    _prescan_profile "$@"   # discover --profile first
    _apply_profile          # profile sets defaults ...
    parse_args "$@"         # ... then explicit flags override them
    _start_logging
    show_banner

    detect_distribution
    detect_multilib
    detect_init_system
    check_root
    check_sudo

    if $ROLLBACK; then
        do_rollback
        exit $?
    fi

    detect_hardware
    check_internet_connectivity

    log_ok "Starting ${SCRIPT_NAME} v${SCRIPT_VERSION}"
    log_ok "Target: Gentoo (${INIT_SYSTEM}) - profile '${SYSTEM_PROFILE}'"
    $DRY_RUN && log_warn "DRY-RUN mode: no changes will be made."

    show_run_plan
    if ! $DRY_RUN && ! $ASSUME_YES; then
        if ! confirm "Proceed with this plan?"; then
            die "Aborted by user." "$EXIT_SUCCESS"
        fi
    fi
    echo ""

    run_selected_steps
    local rc=$?

    if $MERGE_CONFIG; then
        log_section "Config merge (dispatch-conf)"
        if $DRY_RUN; then
            echo "    ${ICON_SKIP} [dry-run] dispatch-conf"
        else
            run_priv dispatch-conf || log_warn "dispatch-conf returned non-zero."
        fi
    fi

    cleanup
    show_completion_summary

    if [[ $rc -eq 0 ]]; then
        log_ok "Completed successfully."
        exit "$EXIT_SUCCESS"
    else
        log_warn "Completed with one or more step failures - review the log above."
        exit "$EXIT_FAILURE"
    fi
}

# Entry point. Sourcing the script (for tests) with GPI_LIB=1 skips execution.
if [[ "${GPI_LIB:-0}" != "1" && "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

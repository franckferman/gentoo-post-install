# Bash completion for gentoo-post-install.
#
# Install (per user):
#   mkdir -p ~/.local/share/bash-completion/completions
#   cp contrib/gentoo-post-install.bash ~/.local/share/bash-completion/completions/gentoo-post-install.sh
# or source it directly:  source contrib/gentoo-post-install.bash

# COMPREPLY=($(compgen ...)) is the standard completion idiom (words are space-free).
# shellcheck disable=SC2207

_gentoo_post_install() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    opts="--help --version --yes --dry-run --allow-root --no-banner --no-emoji \
--log-file --steps --list-steps --list-apps --list-overlays --rollback \
--profile --no-tune --march --jobs --accept-license --no-cpu-flags \
--binhost --binhost-uri --no-sync --no-world-update --no-depclean --mirrors --merge-config \
--install-kernel --kernel-pkg --kernel-source --kernel-config --kernel-lockdown \
--kernel-cmdline-harden --kernel-manual --bootloader --initramfs --microcode \
--sysctl-harden --harden-ipv6 --firewall --no-ssh-rule --ssh-harden --ssh-port \
--ssh-no-root --ssh-key-only --hardened-malloc --minimize-surface --logs \
--audit --no-audit --fail2ban --no-fail2ban --usbguard --apparmor \
--shell --no-shell --shell-user --editor --no-chsh \
--fonts --no-fonts --nerd-fonts --desktop --display --no-audio --no-nm --video-cards \
--overlay --apps --apps-profile --steam --de --dm \
--root-password --disable-root --group --user"

    # Value completion for options that take a fixed set of choices.
    case "$prev" in
        --profile)        COMPREPLY=($(compgen -W "default desktop server hardened minimal opsec" -- "$cur")); return ;;
        --march)          COMPREPLY=($(compgen -W "native none" -- "$cur")); return ;;
        --accept-license) COMPREPLY=($(compgen -W "default free redist all" -- "$cur")); return ;;
        --firewall)       COMPREPLY=($(compgen -W "nftables iptables ufw none" -- "$cur")); return ;;
        --editor)         COMPREPLY=($(compgen -W "vim neovim both none" -- "$cur")); return ;;
        --bootloader)     COMPREPLY=($(compgen -W "grub systemd-boot none" -- "$cur")); return ;;
        --initramfs)      COMPREPLY=($(compgen -W "dracut none" -- "$cur")); return ;;
        --kernel-source)  COMPREPLY=($(compgen -W "bin dist source vanilla" -- "$cur")); return ;;
        --kernel-config)  COMPREPLY=($(compgen -W "standard hardened minimal performance" -- "$cur")); return ;;
        --logs)           COMPREPLY=($(compgen -W "off reduce ephemeral" -- "$cur")); return ;;
        --de)             COMPREPLY=($(compgen -W "kde gnome sway hyprland xfce none" -- "$cur")); return ;;
        --dm)             COMPREPLY=($(compgen -W "sddm gdm lightdm greetd none auto" -- "$cur")); return ;;
        --display)        COMPREPLY=($(compgen -W "x11 wayland both" -- "$cur")); return ;;
        --apps-profile)   COMPREPLY=($(compgen -W "daily dev media gaming" -- "$cur")); return ;;
        --log-file|--shell-user|--video-cards|--kernel-pkg|--binhost-uri|--jobs|--ssh-port|--steps|--overlay|--apps|--nerd-fonts|--group|--user)
            return ;;  # free-form argument
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$opts" -- "$cur"))
    fi
}
complete -F _gentoo_post_install gentoo-post-install.sh
complete -F _gentoo_post_install ./gentoo-post-install.sh

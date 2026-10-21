# Shell & terminal

> A comfortable interactive shell for your login user: `zsh` with oh-my-zsh, the
> Powerlevel10k theme, the three common zsh plugins, and your editor of choice.
> Mirrors the script's step 15 (`--shell`).

## What the script automates

`step_15_shell` installs `zsh`, `git`, and `curl`, then (as your real login user, not
root) clones oh-my-zsh, the Powerlevel10k theme, and the `zsh-autosuggestions`,
`zsh-syntax-highlighting`, and `zsh-completions` plugins into that user's home. It
installs your editor (`vim`, `neovim`, or both), writes a managed `~/.zshrc` (and a
`~/.vimrc`, and a LazyVim starter for neovim), and finally sets `zsh` as the user's
login shell with `chsh`. Everything that touches a dotfile is done as the target user
so files land with the right ownership.

## Concepts

The shell is the program that reads your commands. Gentoo gives you `bash` by default;
`zsh` is a drop-in interactive upgrade with better completion, globbing, and theming.

- **oh-my-zsh** is a configuration framework for zsh: a directory of themes and plugins
  plus a loader you `source` from `~/.zshrc`. It does not replace zsh, it organizes it.
- **Powerlevel10k** is a fast, informative prompt theme. It wants a patched font to draw
  its icons, which is exactly what the next chapter ([Fonts](17-fonts.md)) installs.
- **Plugins** add behavior: `zsh-autosuggestions` proposes commands from history as you
  type, `zsh-syntax-highlighting` colors the command line as you go, and
  `zsh-completions` ships extra completion definitions.
- **The target user matters.** A shell config in `/root` helps nobody when you log in as
  yourself. The script resolves the real user (the `--shell-user` value, else `SUDO_USER`
  when you ran it with sudo, else the current non-root user) and runs every dotfile step
  as that user so ownership is correct. This is the most common thing people get wrong
  setting this up by hand as root.
- **oh-my-zsh is cloned with git, not `curl | sh`.** A pinned `git clone` is
  deterministic and auditable; piping a remote installer into a shell is neither.

## Do it by hand

Throughout, run the privileged installs as root and the dotfile steps **as your login
user**. Replace `youruser` with your username. From a root shell you can run a single
user command with `su - youruser -c '...'`; the explanations assume that pattern, which
is what the script's `user_do` helper does.

### 1. Install zsh, git, curl, and your editor

```bash
# root
emerge --ask=n app-shells/zsh dev-vcs/git net-misc/curl
```

`git` and `curl` are needed to fetch oh-my-zsh and the plugins. Then pick an editor
(the script's `--editor`, default `both`):

```bash
# root
emerge --ask=n app-editors/vim app-editors/neovim   # both (default)
# or just one:
emerge --ask=n app-editors/vim                       # --editor vim
emerge --ask=n app-editors/neovim                    # --editor neovim
# --editor none installs neither
```

### 2. Clone oh-my-zsh into the user's home

```bash
# as youruser
test -d "$HOME/.oh-my-zsh" || git clone --depth=1 \
  https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
```

`--depth=1` takes only the latest commit (a shallow, fast clone). The `test -d` guard
makes this idempotent: re-running it does nothing if the directory already exists.

### 3. Clone the theme and plugins into `ZSH_CUSTOM`

oh-my-zsh looks for user-supplied themes and plugins under
`~/.oh-my-zsh/custom`. Put Powerlevel10k and the three plugins there:

```bash
# as youruser
zc="$HOME/.oh-my-zsh/custom"
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  "$zc/themes/powerlevel10k"
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
  "$zc/plugins/zsh-autosuggestions"
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
  "$zc/plugins/zsh-syntax-highlighting"
git clone --depth=1 https://github.com/zsh-users/zsh-completions \
  "$zc/plugins/zsh-completions"
```

Each lives in a subdirectory named exactly as it is referenced in `~/.zshrc`, so the
loader finds it by name.

### 4. Write `~/.zshrc`

**Warning:** This overwrites `~/.zshrc`. If you already have one, back it up first (the script
copies an existing `~/.zshrc` to `~/.zshrc.gpi.bak` before writing).

```bash
# as youruser
[ -f "$HOME/.zshrc" ] && cp -a "$HOME/.zshrc" "$HOME/.zshrc.gpi.bak"
cat > "$HOME/.zshrc" <<'EOF'
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
```

The `plugins=(...)` array and `ZSH_THEME` line are what tie steps 2 and 3 together. If
you chose neovim, set `export EDITOR='nvim'` instead of `vim` (the script rewrites that
one line to match `--editor`).

### 5. Write editor configs

For `vim` (or `both`), drop a sane `~/.vimrc`. The script will not clobber an existing
one, so guard it:

```bash
# as youruser
[ -f "$HOME/.vimrc" ] || cat > "$HOME/.vimrc" <<'EOF'
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
```

For `neovim` (or `both`), seed the LazyVim starter config and drop its `.git` so it is
yours to edit:

```bash
# as youruser
test -d "$HOME/.config/nvim" || { \
  git clone --depth=1 https://github.com/LazyVim/starter "$HOME/.config/nvim" && \
  rm -rf "$HOME/.config/nvim/.git"; }
```

### 6. Set zsh as the login shell

**Warning:** `chsh` changes which shell you get at login. If your `~/.zshrc` is broken, your login
shell starts in a broken state. You can still fix it from root, so this is low risk, but
test zsh once (step below) before you rely on it.

```bash
# root
chsh -s "$(command -v zsh)" youruser
```

`command -v zsh` resolves the installed path (typically `/bin/zsh`). Skip this step
entirely with the script's `--no-chsh` if you want to keep bash as your login shell and
just start zsh manually.

## Verify

```bash
# login shell is now zsh:
getent passwd youruser | cut -d: -f7          # -> /bin/zsh
# the framework and theme are in place:
ls ~/.oh-my-zsh ~/.oh-my-zsh/custom/themes/powerlevel10k
ls ~/.oh-my-zsh/custom/plugins                # the three plugins
```

Then open a **new** zsh session as the user. You should see the Powerlevel10k prompt,
autosuggestions appear in grey as you type, and syntax highlighting colorizes the command line as you go. On first
launch, run `p10k configure` to tune the prompt (the script reminds you to do this; it
does not run it for you, since it is interactive).

## Pitfalls and rollback

- **Prompt shows boxes or `?` glyphs** → Powerlevel10k needs a Nerd Font and your
  terminal must be set to use it. Install fonts in [Fonts](17-fonts.md), then pick the
  font in your terminal emulator.
- **Files owned by root** → you ran the dotfile steps as root instead of the user. Fix
  with `chown -R youruser:youruser ~youruser/.oh-my-zsh ~youruser/.zshrc`. This is why
  the script runs them as the target user.
- **zsh login feels broken** → log in on another TTY as root and revert the shell:
  `chsh -s /bin/bash youruser`, then fix `~/.zshrc` and try again.
- **Rollback:** this step is **not** reverted by the script's `--rollback` (which only
  restores `make.conf` and removes system drop-ins). Undo it by hand:
  ```bash
  # root
  chsh -s /bin/bash youruser
  # as youruser
  [ -f ~/.zshrc.gpi.bak ] && mv ~/.zshrc.gpi.bak ~/.zshrc || rm -f ~/.zshrc
  rm -rf ~/.oh-my-zsh ~/.config/nvim
  ```

## Script reference

- **Step:** `15` - `step_15_shell` (helpers `_write_zshrc`, `_write_vimrc`,
  `_resolve_target_user`, `user_do`)
- **Flags:** `--shell`, `--no-shell`, `--shell-user <name>`,
  `--editor vim|neovim|both|none`, `--no-chsh`
- **Managed files (in the target user's home):** `~/.oh-my-zsh/` (framework + theme +
  plugins under `custom/`), `~/.zshrc` (existing one backed up to `~/.zshrc.gpi.bak`),
  `~/.vimrc` (only if absent), `~/.config/nvim/` (LazyVim starter). Login shell changed
  via `chsh` unless `--no-chsh`.

---
[← Previous: AppArmor](15-apparmor.md) · [Handbook index](README.md) · [Next: Fonts →](17-fonts.md)

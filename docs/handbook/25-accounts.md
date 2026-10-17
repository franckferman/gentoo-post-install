# Users, groups & sudo

> Create groups and users, grant admin rights through `wheel` and validated sudoers
> drop-ins, set passwords safely via `chpasswd` on stdin, and optionally lock root.
> Mirrors the script's step 23 (`--user`, `--group`, `--root-password`, `--disable-root`).

## What the script automates

`step_23_accounts` creates any requested groups, creates or adjusts users from a compact
spec, grants sudo by adding the user to `wheel` and installing validated `sudoers.d`
drop-ins, sets passwords with a masked prompt piped to `chpasswd`, and can set or lock
the root account. Each piece is safe to reproduce by hand.

**Warning:** Locking root (`--disable-root`) is the one step that can lock you out of
administration entirely. The script refuses unless a **non-root member of `wheel`**
exists as a fallback admin. Do the same: never lock root until you have a working
sudo-capable user.

## Concepts

- **Groups** gate access to resources (devices, services). You may want application or
  hardware groups (`video`, `audio`, `plugdev`, ...) or custom ones.
- **`wheel`** is the conventional "administrators" group. Granting sudo means adding a
  user to `wheel` and telling sudo that `wheel` may run commands.
- **`sudoers.d` drop-ins** are small files under `/etc/sudoers.d/` that `sudo` reads in
  addition to `/etc/sudoers`. They **must** be syntactically valid (a broken sudoers can
  lock out sudo) and mode `0440`, so you always validate with `visudo -c` before
  installing. The script writes two kinds:
  - `00-gpi-wheel` (`%wheel ALL=(ALL:ALL) ALL`): lets any `wheel` member sudo, with a
    password.
  - `10-gpi-<name>` (`<name> ALL=(ALL:ALL) NOPASSWD: ALL`): passwordless sudo for one
    user (opt-in, risky).
- **Passwords via `chpasswd` on stdin.** You never put a password on a command line
  (it would land in `ps` output and shell history). Instead you read it with a masked
  prompt and pipe `user:password` into `chpasswd`. A freshly created account stays
  **locked** until a password is set, which is the safe default.
- **The user spec** passed to `--user` is:

  ```text
  name[:sudo][:nopasswd][:groups=a,b][:shell=/bin/bash]
  ```

  `sudo` adds the user to `wheel`; `nopasswd` additionally grants passwordless sudo;
  `groups=` is a comma list of supplementary groups; `shell=` sets the login shell
  (default `/bin/bash`). Order of the options after the name does not matter.

## Do it by hand

### 1. Create groups

Each `--group <name>` becomes a `groupadd`, skipped if the group already exists:

```bash
# root
getent group plugdev >/dev/null || groupadd plugdev
```

`getent group <name>` checks existence first so re-running is idempotent.

### 2. Create or adjust a user

Take the spec `alice:sudo:groups=video,audio:shell=/bin/zsh` as the example.

Create the account if it does not exist (otherwise just adjust its groups/sudo):

```bash
# root
if ! getent passwd alice >/dev/null; then
  useradd -m -s /bin/zsh alice      # -m makes the home dir; -s sets the login shell
fi
usermod -aG video,audio alice       # supplementary groups (append, do not replace)
```

`useradd -m` creates the home directory; `-s` sets the shell. `usermod -aG` **appends**
groups (the `-a` is essential; without it you would replace the user's group list).

### 3. Grant sudo via wheel + a validated drop-in

If the spec includes `sudo`, add the user to `wheel`, make sure `sudo` is installed, and
install the wheel drop-in:

```bash
# root
usermod -aG wheel alice
command -v sudo >/dev/null || emerge --ask=n --noreplace app-admin/sudo

# Validate, then install the wheel rule at 0440:
tmp="$(mktemp)"
printf '# Managed by gentoo-post-install\n%%wheel ALL=(ALL:ALL) ALL\n' > "$tmp"
visudo -c -f "$tmp" && install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/00-gpi-wheel
rm -f "$tmp"
```

Always `visudo -c -f <file>` before installing: it parses the file and refuses a broken
rule, which is what protects you from locking sudo out. The `0440 root:root` mode is what
`sudo` requires of files in `sudoers.d`.

**Warning:** Passwordless sudo (the spec's `nopasswd`) means anyone with that user's session gets
root with no prompt. Add it only deliberately:

```bash
# root  (only if you really want NOPASSWD for alice)
tmp="$(mktemp)"
printf '# Managed by gentoo-post-install\nalice ALL=(ALL:ALL) NOPASSWD: ALL\n' > "$tmp"
visudo -c -f "$tmp" && install -m 0440 -o root -g root "$tmp" /etc/sudoers.d/10-gpi-alice
rm -f "$tmp"
```

### 4. Set the password (masked prompt, via chpasswd on stdin)

Read the password with a masked prompt and pipe `user:password` to `chpasswd`. **Never**
type a password as a command argument:

```bash
# root
read -rsp "New password for alice: " pw; echo
read -rsp "Confirm password for alice: " pw2; echo
if [ "$pw" = "$pw2" ] && [ -n "$pw" ]; then
  printf '%s:%s' alice "$pw" | chpasswd      # password goes in on STDIN, not argv
else
  echo "Passwords differ or empty - not changing." >&2
fi
unset pw pw2
```

Why this way: command-line arguments are visible in `ps` and (for interactive shells)
land in history, so a password passed as an argument leaks. `chpasswd` reads
`user:password` pairs from standard input, so the secret never appears in the process
table. This is exactly what the script's `_set_password` does. (In a non-interactive
shell with no terminal, there is no safe way to prompt, so set it later with
`passwd alice`; the account stays locked until then.)

### 5. (Optional) Set or lock root

To set root's password, use the same masked-prompt-to-`chpasswd` pattern with `root` as
the user.

**Warning:** To **lock** root, first confirm a non-root `wheel` member exists as a fallback admin,
or you risk locking yourself out of all administration:

```bash
# root
# Fallback admins = wheel members other than root:
getent group wheel | cut -d: -f4 | tr ',' '\n' | grep -vx root
```

If that prints at least one name (your sudo user from step 3), it is safe to lock root:

```bash
# root
passwd -l root                    # lock the root password (no password login)
usermod -s /sbin/nologin root     # replace root's shell so it cannot be used to log in
```

`passwd -l` disables password authentication for root; setting the shell to
`/sbin/nologin` stops interactive root logins entirely. You then administer the box
through your `wheel` user and `sudo`.

## Verify

```bash
# root
id alice                                   # groups include wheel (and video,audio,...)
getent passwd alice                        # shell field matches what you set
sudo -l -U alice                           # shows the sudo rules that apply to alice
ls -l /etc/sudoers.d/                       # drop-ins present, mode -r--r----- (0440)
visudo -c                                  # whole sudoers set parses cleanly

# If you locked root:
passwd -S root                             # status field "L" = locked
getent passwd root                         # shell is /sbin/nologin
```

`sudo -l -U alice` is the authoritative check that the grant works; `visudo -c` confirms
no drop-in broke the config. As the new user, a plain `sudo -v` should prompt for (and
accept) the password you set.

## Pitfalls and rollback

- **`--disable-root` refused:** there was no non-root user in `wheel`. Create one first
  (`--user name:sudo`, or steps 2-3), then lock root.
- **sudo "command not allowed" / nothing works:** a drop-in failed validation and was not
  installed, or `wheel` was never granted. Check `visudo -c` and that `00-gpi-wheel`
  exists.
- **Added to `wheel` but still prompted every time:** that is normal; `wheel` sudo
  requires a password. `nopasswd` removes the prompt (not recommended).
- **Locked out of root with no working sudo user:** boot a live/rescue medium, chroot
  in, and `passwd -u root` / restore root's shell.
- **Rollback:** remove the drop-ins and, if needed, unlock root:
  ```bash
  # root
  rm -f /etc/sudoers.d/00-gpi-wheel /etc/sudoers.d/10-gpi-alice
  gpasswd -d alice wheel         # drop a user from wheel
  passwd -u root                 # unlock root's password
  usermod -s /bin/bash root      # restore root's login shell
  ```
  Removing a user account itself (`userdel -r alice`) is a separate, deliberate step the
  script never does automatically.

## Script reference

- **Step:** `23` - `step_23_accounts` (+ `_set_password`, `_disable_root`,
  `_create_user_from_spec`, `_parse_user_spec`, `_ensure_wheel_sudo`,
  `_write_sudoers_dropin`)
- **Flags:** `--group <name>` (repeatable), `--user <spec>` (repeatable; spec
  `name[:sudo][:nopasswd][:groups=a,b][:shell=/bin/bash]`), `--root-password`,
  `--disable-root`
- **Managed files:** `/etc/sudoers.d/00-gpi-wheel`, `/etc/sudoers.d/10-gpi-<name>`
  (both `0440 root:root`, validated with `visudo -c`); account changes via
  `groupadd`/`useradd`/`usermod`/`passwd`/`chpasswd`.

---
[← Previous: Log-footprint minimization](24-log-minimization.md) · [Handbook index](README.md) · [Next: Appendix: profiles, rollback, troubleshooting, references →](99-appendix.md)

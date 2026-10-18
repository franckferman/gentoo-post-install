# Log-footprint minimization

> Reduce how much the system records about itself: cap or make `journald` volatile,
> disable shell history, restrict `dmesg`, and drop crash dumps. Mirrors the script's
> step 22 (`--logs off|reduce|ephemeral`).

## What the script automates

`step_22_logs` has three levels. `off` (the default) does nothing. `reduce` keeps logs
but small and short-lived; `ephemeral` keeps the system journal in RAM only so it is
gone on reboot. Both non-`off` levels also disable shell history system-wide, clear the
target user's history, restrict `dmesg` to root, and route core dumps to nothing.

**Warning:** This is a **privacy choice with a real cost**: less logging makes the system both
harder to debug *and* harder to investigate after a real intrusion. Logs are also how
you detect a compromise, so weigh the trade-off before turning this up.

## Concepts

The three levels (`--logs <level>`):

- **`off`**: no changes. The step logs a skip and returns.
- **`reduce`**: keep persistent logs, but bound them (journald capped at 50 MB and a
  3-day retention). A good "quieter, not blind" middle ground.
- **`ephemeral`**: journald stored in `volatile` (RAM) with a 50 MB runtime cap, so all
  system logs vanish on reboot. Maximum privacy, zero post-reboot forensics.

**`journald` is a systemd component.** On **OpenRC** there is no journald, so the script
cannot drop in a journald config; it instead reminds you to tune your syslog/logrotate
retention yourself, and notes that a truly ephemeral OpenRC setup means putting
`/var/log` on a `tmpfs`, which is a manual change. Be honest about this: the journald
knobs below only take effect on systemd.

The non-journald parts apply to **both** init systems:

- **Shell history** is written per-user to `~/.bash_history` / `~/.zsh_history`. Setting
  `HISTSIZE=0`/`SAVEHIST=0` and unsetting `HISTFILE` system-wide stops new history from
  being saved.
- **`dmesg`** exposes the kernel ring buffer, which can leak addresses and device
  details; `kernel.dmesg_restrict=1` limits it to root.
- **Core dumps** can be routed to `/bin/false` via `kernel.core_pattern` so a crash
  writes nothing to disk.

## Do it by hand

Pick a level. The steps below show `ephemeral`; for `reduce` use the alternate journald
block in step 1. `off` means "do none of this".

### 1. journald retention (systemd only)

For **`ephemeral`** (journal in RAM, lost on reboot):

```bash
# root  (systemd)
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/gpi-logs.conf <<'EOF'
[Journal]
Storage=volatile
RuntimeMaxUse=50M
EOF
systemctl restart systemd-journald
```

For **`reduce`** (persistent but small and short-lived), use this content instead:

```ini
[Journal]
Storage=persistent
SystemMaxUse=50M
MaxRetentionSec=3day
```

`Storage=volatile` keeps the journal under `/run` (tmpfs); `RuntimeMaxUse` caps that RAM
usage. `SystemMaxUse` caps on-disk size and `MaxRetentionSec` drops entries older than
three days. Restarting `systemd-journald` applies the change immediately.

On **OpenRC** there is nothing to drop in here. Instead, reduce retention in your syslog
daemon and `logrotate` (shorter `rotate`/`maxage`), and for a fully ephemeral setup mount
`/var/log` on a `tmpfs` (an `/etc/fstab` entry) so logs do not survive a reboot. These
are manual choices, not written by the script.

### 2. Disable shell history

Write a system-wide profile snippet so new shells save no history:

```bash
# root
cat > /etc/profile.d/gpi-nohistory.sh <<'EOF'
# Managed by gentoo-post-install - no shell history
unset HISTFILE
export HISTSIZE=0
export SAVEHIST=0
EOF
```

Why `unset HISTFILE` and **not** `HISTFILE=/dev/null`: pointing the history file at the
`/dev/null` *device* is a known footgun, because some tools rotate or recreate the
history file and can clobber the device node. Having no history file at all is cleaner.

Then clear the existing history for your user (run as that user, or via `su -`):

```bash
# as your user
rm -f "$HOME/.bash_history" "$HOME/.zsh_history" 2>/dev/null
history -c 2>/dev/null || true
```

The profile snippet takes effect in new login shells; the `rm` removes what was already
saved.

### 3. Restrict dmesg and drop core dumps

```bash
# root
cat > /etc/sysctl.d/99-gpi-logs.conf <<'EOF'
# Managed by gentoo-post-install - log/telemetry restriction
kernel.dmesg_restrict = 1
kernel.core_pattern = |/bin/false
EOF
sysctl --system
```

`dmesg_restrict = 1` means an unprivileged user can no longer read the kernel ring
buffer. `core_pattern = |/bin/false` pipes any core dump to `/bin/false`, which discards
it (nothing written to disk). `sysctl --system` applies both now. This pairs with the
core-dump limits in [Attack-surface minimization](23-attack-surface.md).

## Verify

```bash
# systemd: confirm the journal store and size
journalctl --disk-usage
systemctl show systemd-journald -p Storage      # or inspect the drop-in directly
cat /etc/systemd/journald.conf.d/gpi-logs.conf

# Both: sysctl values are live
sysctl kernel.dmesg_restrict kernel.core_pattern

# History is off in a new login shell
bash -lc 'echo "HISTFILE=[$HISTFILE] HISTSIZE=$HISTSIZE"'   # -> HISTFILE=[] HISTSIZE=0
```

For `ephemeral`, `journalctl --disk-usage` should point at the runtime (RAM) journal,
and after a reboot `journalctl --boot=-1` should have nothing from before.

## Pitfalls and rollback

- **"I can't debug anything":** that is the cost. Set `--logs reduce` (or `off`) to get
  useful history back, or temporarily `journalctl` while the daemon still holds the
  current boot.
- **OpenRC and you expected journald behavior:** there is no journald on OpenRC; only the
  history, `dmesg`, and `core_pattern` changes apply. Tune syslog/logrotate or use a
  `/var/log` tmpfs for the rest.
- **History still saving:** `/etc/profile.d/*.sh` only applies to *login* shells; open a
  new login session, or `source /etc/profile.d/gpi-nohistory.sh`. A desktop terminal may
  need you to log out and back in.
- **Rollback:** remove the drop-ins and restart/reapply:
  ```bash
  # root
  rm -f /etc/systemd/journald.conf.d/gpi-logs.conf \
        /etc/profile.d/gpi-nohistory.sh \
        /etc/sysctl.d/99-gpi-logs.conf
  systemctl restart systemd-journald 2>/dev/null || true   # systemd
  sysctl --system
  ```
  New login shells get normal history back; journald returns to its built-in defaults.

## Script reference

- **Step:** `22` - `step_22_logs`
- **Flags:** `--logs off|reduce|ephemeral` (the `opsec` profile sets `reduce`)
- **Managed files:** `/etc/systemd/journald.conf.d/gpi-logs.conf` (systemd only),
  `/etc/profile.d/gpi-nohistory.sh`, `/etc/sysctl.d/99-gpi-logs.conf`; also clears the
  target user's `~/.bash_history` and `~/.zsh_history`.

---
[← Previous: Attack-surface minimization](23-attack-surface.md) · [Handbook index](README.md) · [Next: Users, groups & sudo →](25-accounts.md)

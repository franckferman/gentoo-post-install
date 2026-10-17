# fail2ban

> Install fail2ban and drop in an sshd jail that watches the auth log and temporarily
> bans IP addresses that fail to log in too many times. Mirrors the script's step 12
> (`--fail2ban`).

## What the script automates

`step_12_fail2ban` installs `net-analyzer/fail2ban`, then writes one managed jail
drop-in at `/etc/fail2ban/jail.d/99-gentoo-post-install.local`. That file sets sane
`[DEFAULT]` ban timings and enables the `[sshd]` jail on your real SSH port. It picks
the right log backend for your init system (the systemd journal on systemd, the
auto/`/var/log/messages` path on OpenRC) and then enables and starts the `fail2ban`
service. The SSH port it writes is the same `SSH_PORT` used by
[SSH hardening](11-ssh-hardening.md), so the jail watches the port you actually listen
on.

## Concepts

fail2ban is a log-scanning daemon. It ties together three kinds of object:

- **A jail** is the unit you turn on. It names a *filter*, a *backend* (where to read
  log lines), and an *action* (what to do on a match), plus thresholds. The `[sshd]`
  jail watches SSH authentication.
- **A filter** is a set of regular expressions (shipped in `/etc/fail2ban/filter.d/`)
  that recognize a failed attempt in a log line, for example a rejected SSH password.
- **An action** is what happens when the threshold is crossed (shipped in
  `/etc/fail2ban/action.d/`). The default action inserts a firewall rule that drops the
  offending IP for the ban duration.
- **The backend** decides how fail2ban reads logs: `systemd` reads the journal directly,
  while `auto` (used on OpenRC) tails a file such as `/var/log/messages`, which is why
  [audit & logging](12-audit-logging.md) installs a syslog daemon first.

The three thresholds that matter:

- **`maxretry`** is how many failures trip the jail (the script uses `5`).
- **`findtime`** is the window those failures must happen within (`10m`).
- **`bantime`** is how long the ban lasts (`1h`).

So: five failed logins from one IP within ten minutes earns that IP a one-hour ban.

Precedence matters. Distribution defaults live in `/etc/fail2ban/jail.conf`; **never
edit that file**. Your overrides go in `*.local` files, and drop-ins in
`/etc/fail2ban/jail.d/` are read last, so the script's `99-` prefixed file wins. This
survives package upgrades cleanly.

## Do it by hand

### 1. Install fail2ban

```bash
# root
emerge --ask=n --noreplace net-analyzer/fail2ban
```

`--noreplace` keeps the command idempotent (skips it if already installed), matching
the script's `emerge_install` helper. fail2ban needs a working firewall backend; by
default its ban action uses `iptables`/`nftables`, so install your
[firewall](10-firewall.md) first.

### 2. Write the sshd jail drop-in

The backend and one extra line differ by init system. On **systemd** fail2ban reads the
journal; on **OpenRC** it tails `/var/log/messages`, so you add an explicit `logpath`.

```bash
# root - systemd
cat > /etc/fail2ban/jail.d/99-gentoo-post-install.local <<'EOF'
# Managed by gentoo-post-install - protect sshd against brute force.
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = 22
EOF
```

```bash
# root - OpenRC
cat > /etc/fail2ban/jail.d/99-gentoo-post-install.local <<'EOF'
# Managed by gentoo-post-install - protect sshd against brute force.
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = auto

[sshd]
enabled  = true
port     = 22
logpath  = /var/log/messages
EOF
```

Replace `22` with your real SSH port if you changed it in
[SSH hardening](11-ssh-hardening.md); the script substitutes its `SSH_PORT` here so the
jail and the daemon agree. The `[DEFAULT]` block sets the thresholds for every jail;
`[sshd] enabled = true` switches on the SSH jail (its filter is the stock
`filter.d/sshd.conf`, so you do not write one).

### 3. Enable and start the service

The script's `service_enable_start` means "enable at boot and start now":

```bash
# root - systemd
systemctl enable --now fail2ban

# root - OpenRC
rc-update add fail2ban default
rc-service fail2ban start
```

## Verify

```bash
# root
fail2ban-client status              # lists active jails - expect 'sshd'
fail2ban-client status sshd         # per-jail: failures seen, currently banned IPs
```

`fail2ban-client status sshd` shows the number of currently failed and banned IPs and
confirms the jail is reading logs. To test the ban logic safely, fail a login from
another host a few times and watch the banned count rise; a banned IP also appears in
your firewall rules. Check the daemon's own log if a jail does not start:

```bash
# root
tail -n 20 /var/log/fail2ban.log      # or: journalctl -u fail2ban  (systemd)
```

Service state:

```bash
# systemd
systemctl is-active fail2ban
# OpenRC
rc-service fail2ban status
```

## Pitfalls and rollback

- **Warning:** **Banning yourself.** If you fumble your own SSH logins from a remote box, you can
  be locked out for `bantime`. Keep a console/second session open while testing, and
  unban yourself with `fail2ban-client set sshd unbanip <your-ip>` if needed. Consider
  adding `ignoreip = 127.0.0.1/8 <your-lan>` to `[DEFAULT]`.
- **Wrong port.** If the jail's `port` does not match your real SSH port, bans are
  inserted for the wrong port and do nothing useful. Keep it in sync with sshd.
- **No log to read (OpenRC).** With `backend = auto` and no syslog daemon, fail2ban has
  nothing to tail and the jail silently sees zero failures. Install a logger first (see
  [audit & logging](12-audit-logging.md)).
- **Edited `jail.conf`.** Overrides belong in `*.local`/`jail.d`; a package upgrade can
  overwrite `jail.conf`. The script only ever writes the `99-` drop-in.
- **Rollback:** `--rollback` removes the managed jail drop-in, which disables the jail:
  ```bash
  # root
  rm -f /etc/fail2ban/jail.d/99-gentoo-post-install.local
  systemctl reload fail2ban 2>/dev/null || rc-service fail2ban restart
  ```
  Rollback does not stop the service or unmerge the package; do that by hand if you want
  fail2ban fully gone.

## Script reference

- **Step:** `12` - `step_12_fail2ban`
- **Flags:** `--fail2ban`, `--no-fail2ban`
- **Managed files:** `/etc/fail2ban/jail.d/99-gentoo-post-install.local` (backend and
  `logpath` differ by init system; `port` follows `--ssh-port`)

---
[← Previous: Audit & logging](12-audit-logging.md) · [Handbook index](README.md) · [Next: USBGuard →](14-usbguard.md)

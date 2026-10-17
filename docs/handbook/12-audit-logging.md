# Audit & logging

> Install the kernel audit framework (`auditd`) and make sure the system keeps a
> persistent text log, so security-relevant events are recorded and survive reboots.
> Mirrors the script's step 11 (`--audit`).

## What the script automates

`step_11_audit_logging` installs `sys-process/audit` (the userspace for the kernel
audit subsystem) and enables its `auditd` service. It then makes sure a general system
logger exists: on systemd it does nothing (journald already logs), and on OpenRC it
installs `app-admin/sysklogd` only if no syslog daemon is present, plus
`app-admin/logrotate` to keep log files from growing without bound. The single
`--audit` flag turns on both halves (it sets the audit *and* the syslog switch). There
are no managed config files here; this step is deliberately minimal (install the right
packages and start the right services), so the manual version is short.

## Concepts

Two different logging layers are in play, and they do not replace each other:

- **The kernel audit framework** (`auditd`) records *security* events decided by kernel
  rules: syscalls, file accesses on watched paths, logins, use of privileged
  capabilities. It writes structured records to `/var/log/audit/audit.log` and is the
  data source for compliance tooling and intrusion forensics. Without the `auditd`
  daemon running, audit messages the kernel emits have nowhere to go (they fall back to
  the kernel ring buffer at best).
- **A system logger** collects ordinary `syslog(3)` messages from daemons and the
  kernel. On **systemd** this is `journald`, which is always present and already keeps a
  log, so no extra daemon is needed. On **OpenRC** there is no logger by default, so you
  install one (`app-admin/sysklogd` writes plain text to `/var/log/messages`); other
  daemons in this handbook, notably [fail2ban](13-fail2ban.md), read that file.
- **`logrotate`** periodically compresses and prunes log files so a chatty service
  cannot fill the disk. journald does its own rotation, so this mainly matters on
  OpenRC, but installing it is harmless either way.

The audit daemon and the syslog daemon run independently: you can have one without the
other. The script installs both because a hardened box wants structured security
records *and* a durable general log.

## Do it by hand

### 1. Install the audit userspace

```bash
# root
emerge --ask=n --noreplace sys-process/audit
```

`sys-process/audit` provides `auditd` (the daemon that drains kernel audit records to
disk) and the tools `auditctl`, `ausearch`, and `aureport`. `--noreplace` makes the
command idempotent (it skips the package if it is already installed), matching the
script's `emerge_install` helper.

### 2. Enable and start `auditd`

The script's `service_enable_start` means "enable at boot *and* start now". Expand it
for your init system:

```bash
# root - systemd
systemctl enable --now auditd

# root - OpenRC
rc-update add auditd default
rc-service auditd start
```

Once running, the daemon writes to `/var/log/audit/audit.log`. The default ruleset is
minimal; you add rules later with `auditctl` or in `/etc/audit/rules.d/*.rules` (the
script does not write any custom rules, so you start from the stock policy).

### 3. Ensure a system logger exists

On **systemd**, stop here: `journald` already captures everything, and adding a second
logger just duplicates work. The script explicitly skips this part under systemd.

On **OpenRC**, check whether a logger is already installed before adding one:

```bash
# root - OpenRC: only install if none of these exist
command -v rsyslogd syslog-ng sysklogd >/dev/null 2>&1 \
  || emerge --ask=n --noreplace app-admin/sysklogd
```

If nothing was installed before, enable and start it:

```bash
# root - OpenRC
rc-update add sysklogd default
rc-service sysklogd start
```

`app-admin/sysklogd` is a small, classic logger that writes plain text to
`/var/log/messages`. The script chooses it (rather than `rsyslog` or `syslog-ng`)
because it is the lightest option that satisfies the "persistent text log" requirement.
If you already run `rsyslog` or `syslog-ng`, keep it; the script leaves an existing
logger alone.

### 4. Install logrotate

```bash
# root
emerge --ask=n --noreplace app-admin/logrotate
```

`logrotate` reads `/etc/logrotate.conf` and the drop-ins in `/etc/logrotate.d/` and
rotates matching logs on a schedule (driven by a cron job or a systemd timer). This
keeps `/var/log/messages` and friends from growing unbounded on an OpenRC system.

## Verify

```bash
# root
auditctl -s                 # audit status: should show 'enabled 1' and a pid
ausearch -m LOGIN --start today   # today's login audit records
tail -n 5 /var/log/audit/audit.log

# OpenRC only: confirm the syslog is capturing messages
logger "gpi audit test" && tail -n 3 /var/log/messages
```

`auditctl -s` printing `enabled 1` with a non-zero `pid` confirms the daemon is live.
The `logger` line injects a test message; seeing it land in `/var/log/messages` proves
the syslog path works. On systemd, use `journalctl -n 5` instead of reading
`/var/log/messages`.

Service state:

```bash
# systemd
systemctl is-active auditd
# OpenRC
rc-service auditd status
```

## Pitfalls and rollback

- **No audit records appear** → the daemon is not running, or it started before the
  disk was writable. Check `auditctl -s` and the service status; restart `auditd`.
- **`/var/log/audit/audit.log` grows fast** → you (or a tool) added noisy rules. Review
  `auditctl -l` and `/etc/audit/rules.d/`. The stock policy the script leaves is quiet.
- **Running a second logger on systemd** → journald plus a syslog daemon double-logs and
  wastes disk. That is why the script skips the extra logger under systemd.
- **Rollback:** this step has no managed drop-in files, so `--rollback` does not touch
  it. To undo manually, stop and disable the services, then unmerge the packages:
  ```bash
  # systemd
  systemctl disable --now auditd
  # OpenRC
  rc-service auditd stop; rc-update del auditd
  rc-service sysklogd stop; rc-update del sysklogd
  # then, if you really want the packages gone:
  emerge --ask=n --depclean sys-process/audit app-admin/sysklogd app-admin/logrotate
  ```
  Removing the packages is optional; leaving them installed but disabled is harmless.

## Script reference

- **Step:** `11` - `step_11_audit_logging`
- **Flags:** `--audit` (enables audit *and* the system logger), `--no-audit`
- **Managed files:** none (the step only installs packages and enables services;
  `auditd` writes `/var/log/audit/audit.log` at runtime, `sysklogd` writes
  `/var/log/messages`)

---
[← Previous: SSH hardening](11-ssh-hardening.md) · [Handbook index](README.md) · [Next: fail2ban →](13-fail2ban.md)

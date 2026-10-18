# SSH hardening

> Drop a hardened OpenSSH server config into
> `/etc/ssh/sshd_config.d/99-gentoo-post-install.conf`, make sure the main config
> actually includes it, validate with `sshd -t`, then restart. Mirrors the script's
> step 10 (`--ssh-harden`, `--ssh-port`, `--ssh-no-root`, `--ssh-key-only`).

## What the script automates

`step_10_ssh_hardening` writes a single sshd drop-in at
`/etc/ssh/sshd_config.d/99-gentoo-post-install.conf` with safer defaults: a chosen
port, a `PermitRootLogin` policy, optional password-login disable, modern-only
crypto, and tighter session limits. It then guarantees `/etc/ssh/sshd_config` carries
an `Include` line for the drop-in directory (appending one if missing), validates the
whole config with `sshd -t`, and only on success offers to restart the service. It
runs only when `/etc/ssh` exists.

## Concepts

OpenSSH reads its server config from `/etc/ssh/sshd_config`, and modern versions also
read fragments from `/etc/ssh/sshd_config.d/`. Using a drop-in keeps your changes in
one labeled file that is easy to review or remove, instead of editing the distributed
config in place.

Two points about how sshd parses config decide everything here:

- **The `Include` must be present.** The drop-in only takes effect if the main config
  contains `Include /etc/ssh/sshd_config.d/*.conf`. Recent OpenSSH ships this line, but
  not every `sshd_config` has it, so you must check.
- **For most directives, the first value wins.** `sshd` takes the *first* occurrence
  of a keyword, not the last. So the `Include` generally belongs near the **top** of
  `sshd_config`; if it sits below a directive you also set in the drop-in, the main
  file's value is used and your override is silently ignored.

The directives worth understanding:

- **`Port`** is where sshd listens. Moving off 22 does not add real security (a scan
  finds it), but it cuts log noise from untargeted bots.
- **`PermitRootLogin`** controls root logins. `prohibit-password` allows root only by
  key (no password), `no` forbids root entirely.
- **`PasswordAuthentication`** toggles password logins for everyone. `no` means
  key-only, the strongest setting and the easiest way to lock yourself out.
- The crypto lines (`KexAlgorithms`, `Ciphers`, `MACs`) restrict negotiation to modern
  algorithms, and the session limits reduce brute-force surface and reap idle sessions.

**Warning:** This chapter is full of lockout traps: a custom `Port` the firewall does not allow,
`PermitRootLogin no` on a box where root is your only way in, and `PasswordAuthentication
no` with no working key. Read each warning before you apply it, and keep a second logged-in
session or console open while you test.

## Do it by hand

### 1. Decide your policy

Match the script's logic. The defaults are a custom-free, key-friendly baseline:

- Port: `22` (the script's `--ssh-port <N>` sets another).
- `PermitRootLogin`: `prohibit-password` by default; `no` with `--ssh-no-root`.
- `PasswordAuthentication`: `yes` by default; `no` with `--ssh-key-only`.

**Warning:** Before setting `PasswordAuthentication no` (key-only), confirm you have a working
key. From your client: `ssh-copy-id user@host`, then open a **new** session and log in
with the key *without* being asked for a password. Only disable passwords once that
succeeds. If you disable them with no installed key, you cannot log in at all.

### 2. Write the hardened drop-in

This is the exact file the script writes. Substitute your port and the
`PermitRootLogin` / `PasswordAuthentication` values you chose above (shown here with
the defaults):

```bash
# root
install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-gentoo-post-install.conf <<'EOF'
# Managed by gentoo-post-install - OpenSSH hardening drop-in.
Port 22
PermitRootLogin prohibit-password
PasswordAuthentication yes
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
```

What the less obvious lines do:

- **`KbdInteractiveAuthentication no`** closes the keyboard-interactive path (a common
  route for PAM-based password prompts), while `PubkeyAuthentication yes` keeps keys
  working and `PermitEmptyPasswords no` refuses accounts with blank passwords.
- **`X11Forwarding`, `AllowAgentForwarding`, `AllowTcpForwarding` set to `no`** drop
  forwarding features a plain login does not need; each is a lateral-movement vector if
  a session is compromised. Turn a specific one back on only if you actually use it.
- **`MaxAuthTries 3`, `LoginGraceTime 30`** give an attacker few guesses and little
  time per connection. **`MaxSessions 4`** caps multiplexed channels.
- **`ClientAliveInterval 300` + `ClientAliveCountMax 2`** disconnect a session that has
  been unreachable for about 10 minutes, cleaning up dead connections.
- The **`KexAlgorithms` / `Ciphers` / `MACs`** lines allow only strong, modern
  primitives (Curve25519 key exchange, ChaCha20-Poly1305 and AES-GCM ciphers,
  encrypt-then-MAC HMACs), refusing weak legacy algorithms.

### 3. Ensure the main config includes the drop-in

Check for the `Include` line and add it only if it is missing:

```bash
# root
grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config \
  || printf '\nInclude /etc/ssh/sshd_config.d/*.conf\n' >> /etc/ssh/sshd_config
```

This appends the include if it is not already present. As noted in Concepts, because
the first match wins for most keywords, if an override does not take effect move the
`Include` line to near the top of `/etc/ssh/sshd_config`.

### 4. Validate before you restart

**Warning:** Never restart sshd on a config you have not tested. A syntax error can leave the
daemon refusing to start, and on a remote box that is a lockout.

```bash
# root
sshd -t && echo "config OK"
```

`sshd -t` parses the full config (main file plus every include) and exits non-zero with
the offending line on any error. If it fails, fix the drop-in and re-run; do not
restart until it passes. (Use the full path `/usr/sbin/sshd -t` if `sshd` is not on
root's `PATH`.)

### 5. Enable and restart the service

Make sure sshd starts at boot, then restart to apply. Keep your current session open
and test a **new** connection before closing it.

```bash
# root  (OpenRC)
rc-update add sshd default
rc-service sshd restart
```

```bash
# root  (systemd)
systemctl enable sshd
systemctl restart sshd
```

**Warning:** If you changed `Port`, open that port in the firewall *before* restarting (see
[Firewall](10-firewall.md)), and connect with `ssh -p <N>`. A new port that the
firewall still blocks is a lockout.

## Verify

Confirm sshd is listening and the hardened values are in force:

```bash
# root
sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|x11forwarding|maxauthtries)'
```

`sshd -T` dumps the *effective* configuration after includes are merged, so this proves
the drop-in actually took effect (not just that the file exists). Then, from another
machine, open a fresh session on the right port and confirm your intended auth method
works:

```bash
$ ssh -p 22 user@host     # use your real port; key login if you went key-only
```

If password auth is disabled, a login attempt should proceed straight to the key (or
be refused with "Permission denied (publickey)" when no key is offered).

## Pitfalls and rollback

- **Warning:** **Key-only with no key** (`PasswordAuthentication no`): you cannot log in. Verify
  key login in a second session first; recover from console if locked out.
- **Warning:** **`PermitRootLogin no` on a root-only box**: if root is the only account and you
  have no other user with sudo/console access, you lose remote administration. Create
  and test a non-root admin account first.
- **Warning:** **Custom port blocked by the firewall**: open it in the firewall and use `ssh -p`.
- **Override ignored**: almost always the `Include` sits below a conflicting directive
  in `sshd_config` (first match wins). Move the `Include` to the top and re-run
  `sshd -T` to confirm.
- **Rollback.** Remove the drop-in and restart sshd; the daemon falls back to the main
  config:
  ```bash
  # root
  rm -f /etc/ssh/sshd_config.d/99-gentoo-post-install.conf
  sshd -t && rc-service sshd restart        # OpenRC
  # sshd -t && systemctl restart sshd        # systemd
  ```
  The script's `--rollback` removes the drop-in (it carries the managed marker). It
  does **not** remove the `Include` line it may have appended, which is harmless to
  leave, and it does not disable the sshd service.

## Script reference

- **Step:** `10` - `step_10_ssh_hardening`
- **Flags:** `--ssh-harden`, `--ssh-port <N>`, `--ssh-no-root`, `--ssh-key-only`
  (`--ssh-port`, `--ssh-no-root`, and `--ssh-key-only` each imply `--ssh-harden`)
- **Managed files:** `/etc/ssh/sshd_config.d/99-gentoo-post-install.conf`; may append an
  `Include /etc/ssh/sshd_config.d/*.conf` line to `/etc/ssh/sshd_config`.

---
[← Previous: Firewall](10-firewall.md) · [Handbook index](README.md) · [Next: Audit & logging →](12-audit-logging.md)

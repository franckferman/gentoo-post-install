# Firewall

> Put up a default-deny inbound firewall that still lets replies, loopback, ICMP, and
> (unless you say otherwise) SSH through, using one of three backends: nftables,
> iptables, or ufw. Mirrors the script's step 09 (`--firewall`, `--firewall-lan`,
> `--no-ssh-rule`).

## What the script automates

`step_09_firewall` configures a host firewall whose default policy is to **drop all
inbound traffic**, then opens only what you need. With the default backend
(`--firewall nftables`) it installs `net-firewall/nftables`, backs up any existing
`/etc/nftables.conf` to `/etc/nftables.conf.gpi.bak`, writes a managed ruleset,
validates it, applies it, and enables the service at boot. The `iptables` and `ufw`
backends reach the same end state through their own tooling. An SSH allow rule is kept
by default so you do not lock yourself out of a remote box; `--firewall-lan` opens the
local-discovery ports a desktop wants.

## Concepts

A host firewall filters packets in the kernel. The policy that matters most here is
the **input** policy: with a default of `drop`, anything you did not explicitly allow
is refused, which is the safe posture for a workstation or server. Three pieces make
default-deny usable:

- **Stateful tracking (conntrack).** Allowing `established,related` connections means
  replies to connections *you* initiated come back in, so outbound browsing, updates,
  and SSH sessions work even though nothing inbound is opened for them.
- **Loopback.** `lo` must be allowed or local services that talk to `127.0.0.1` break.
- **ICMP.** Permitting ICMP (and ICMPv6) keeps `ping`, path-MTU discovery, and IPv6
  neighbor discovery working.

The three backends are different front-ends to the same kernel filtering:

- **nftables** is the modern framework and Gentoo's default choice here. One file,
  `/etc/nftables.conf`, holds the whole ruleset in a readable syntax.
- **iptables** is the older interface. Rules are added imperatively and then saved to
  a file that a service restores at boot.
- **ufw** ("uncomplicated firewall") is a high-level wrapper that generates iptables
  rules from simple `allow`/`deny` commands.

**Warning:** Default-deny plus a remote session is the classic lockout. Always keep the SSH
rule (and open the right port) *before* the drop policy takes effect. The script adds
accept rules first and only then flips the policy, and it keeps an SSH rule unless you
pass `--no-ssh-rule`.

Pick one backend and follow only its section below. The SSH port used is `22` unless
you set a custom one in [SSH hardening](11-ssh-hardening.md); keep the firewall rule
and the SSH `Port` in agreement.

## Do it by hand

### Backend A: nftables (default)

**1. Install nftables and back up any existing ruleset.**

```bash
# root
emerge --ask=n net-firewall/nftables
[ -f /etc/nftables.conf ] && [ ! -f /etc/nftables.conf.gpi.bak ] \
  && cp -a /etc/nftables.conf /etc/nftables.conf.gpi.bak
```

The backup is taken once, only if a config already exists and no backup is there yet,
so re-running never clobbers your saved original.

**2. Write the ruleset to `/etc/nftables.conf`.** This is the exact ruleset the script
emits (shown with the SSH rule on port 22 kept):

```bash
# root
cat > /etc/nftables.conf <<'EOF'
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
        tcp dport 22 accept comment "ssh"
    }
    chain forward {
        type filter hook forward priority filter; policy drop;
    }
    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF
```

Line by line: `flush ruleset` clears anything loaded so the file is the single source
of truth. The `inet` family covers IPv4 and IPv6 at once. The `input` chain's
`policy drop` is the default-deny; the rules above it carve out exceptions:
established/related replies, a drop for `invalid` packets, loopback, ICMP and ICMPv6,
and finally SSH. `forward` is dropped (this host is not a router), and `output` is
accepted (the host may talk out freely).

**Warning:** If you do not want the SSH rule (for example this is a local-only desktop with no
remote login), omit the `tcp dport 22 accept` line. That is the script's
`--no-ssh-rule`. Do not omit it on a machine you administer over SSH.

If you want the LAN/desktop discovery ports (the script's `--firewall-lan`), add these
inside the `input` chain, after the SSH line:

```nft
        udp dport 5353 accept comment "mDNS"
        udp dport 1900 accept comment "SSDP/DLNA"
        tcp dport 1714-1764 accept comment "KDE Connect"
        udp dport 1714-1764 accept comment "KDE Connect"
```

These open mDNS (Avahi service discovery), SSDP/DLNA (media discovery), and the KDE
Connect port range, which desktops need for printer/service discovery and phone
pairing. Leave them out on a server.

**3. Validate, then apply.** Never load a ruleset you have not checked.

```bash
# root
nft -c -f /etc/nftables.conf   # -c = check only, parse without applying
nft -f /etc/nftables.conf      # apply it now
```

Checking first is what stops a typo from leaving you with a half-loaded or empty
ruleset.

**4. Persist and enable at boot.** On OpenRC, the init script can snapshot the live
ruleset, and you add the service to the default runlevel; on systemd you enable and
start the unit:

```bash
# root  (OpenRC)
rc-service nftables save          # save current live ruleset for restore at boot
rc-update add nftables default
rc-service nftables start
```

```bash
# root  (systemd)
systemctl enable --now nftables
```

On systemd, if your ruleset is not restored after a reboot, enable the
`nftables-store` and `nftables-load` units instead of `nftables.service` (that is the
note the script prints).

### Backend B: iptables

Install iptables, then add every accept rule **before** switching the policy to DROP,
so your SSH session is never the thing that gets cut:

```bash
# root
emerge --ask=n net-firewall/iptables

iptables -F INPUT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT          # ssh; omit for --no-ssh-rule
# --firewall-lan: mDNS / SSDP / KDE Connect
# iptables -A INPUT -p udp --dport 5353 -j ACCEPT
# iptables -A INPUT -p udp --dport 1900 -j ACCEPT
# iptables -A INPUT -p tcp --dport 1714:1764 -j ACCEPT
# iptables -A INPUT -p udp --dport 1714:1764 -j ACCEPT
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT
```

**Warning:** Order is the whole game here. If you set `-P INPUT DROP` first, the policy applies
immediately and can drop your current SSH connection before the allow rule exists. Add
the accepts first, exactly as above.

Persist the rules so a service can restore them at boot, then enable that service:

```bash
# root
mkdir -p /var/lib/iptables
iptables-save > /var/lib/iptables/rules-save

rc-update add iptables default && rc-service iptables start   # OpenRC
# systemctl enable --now iptables                              # systemd
```

`/var/lib/iptables/rules-save` is the path Gentoo's iptables init script restores from.

### Backend C: ufw

ufw hides the rule ordering behind simple commands and sets safe defaults for you:

```bash
# root
emerge --ask=n net-firewall/ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp                 # ssh; omit for --no-ssh-rule
# --firewall-lan:
# ufw allow 5353/udp
# ufw allow 1900/udp
# ufw allow 1714:1764/tcp
# ufw allow 1714:1764/udp
ufw --force enable               # --force skips the interactive y/N prompt
```

`default deny incoming` plus `default allow outgoing` is the same posture as the other
backends. `ufw allow 22/tcp` is added before enabling, so SSH survives.

Enable the service at boot (ufw's own `enable` turns filtering on now; the init service
makes it come back after a reboot):

```bash
# root
rc-update add ufw default        # OpenRC
# systemctl enable ufw           # systemd
```

## Verify

List the live ruleset and confirm the input policy is drop with only your intended
holes open:

```bash
# root
nft list ruleset        # nftables: shows policy drop + your accept rules
iptables -L INPUT -n -v # iptables: 'policy DROP' on the chain line
ufw status verbose      # ufw: 'Default: deny (incoming)' + your allow rules
```

From another machine, a port scan or an `ssh` attempt to a port you did not open
should time out, while SSH to the port you allowed still connects. Locally, outbound
traffic (updates, browsing) keeps working because of the established/related rule.

## Pitfalls and rollback

- **Warning:** **Locking yourself out.** Dropping inbound without an SSH allow rule (or with the
  wrong port) ends a remote session and refuses the next one. If you can, test over a
  console or a second logged-in session before trusting the rules.
- **Custom SSH port mismatch.** If you changed the SSH `Port` (see
  [SSH hardening](11-ssh-hardening.md)), the firewall must allow that same port. The
  script shares one `SSH_PORT` value across both steps; by hand, keep them in sync.
- **nftables not restored at boot (systemd).** Use `nftables-store` +
  `nftables-load`, or make sure `rc-service nftables save` ran (OpenRC), so the live
  ruleset is written back to `/etc/nftables.conf` for next boot.
- **Rollback.** The script's `--rollback` does **not** touch `/etc/nftables.conf`, does
  not uninstall the backend, and does not disable the service, so reverting is manual.
  For nftables, restore your backup (or flush) and reload:
  ```bash
  # root
  cp -a /etc/nftables.conf.gpi.bak /etc/nftables.conf   # if you had one
  nft -f /etc/nftables.conf
  # no prior config? drop everything:  nft flush ruleset
  rc-service nftables stop && rc-update del nftables     # OpenRC, to disable
  # systemctl disable --now nftables                      # systemd
  ```
  For iptables, `iptables -F && iptables -P INPUT ACCEPT` (and remove the rules-save
  file); for ufw, `ufw disable` (or `ufw reset`).

## Script reference

- **Step:** `09` - `step_09_firewall` (helpers `_nftables_ruleset`, `_fw_nftables`,
  `_fw_iptables`, `_fw_ufw`)
- **Flags:** `--firewall nftables|iptables|ufw|none`, `--firewall-lan`, `--no-ssh-rule`
  (and `--ssh-port <N>`, shared with SSH hardening, sets the allowed port)
- **Managed files:** `/etc/nftables.conf` (backed up to `/etc/nftables.conf.gpi.bak`)
  for the nftables backend; `/var/lib/iptables/rules-save` for the iptables backend;
  ufw stores its own rules under `/etc/ufw/`.

---
[← Previous: sysctl hardening](09-sysctl-hardening.md) · [Handbook index](README.md) · [Next: SSH hardening →](11-ssh-hardening.md)

# sysctl hardening

> Write a set of safe network and kernel `sysctl` knobs to
> `/etc/sysctl.d/99-gentoo-post-install.conf` and load them, so the running kernel
> drops spoofed/redirected traffic and leaks less information. Mirrors the script's
> step 08 (`--sysctl-harden`, `--harden-ipv6`).

## What the script automates

`step_08_sysctl_hardening` writes a single drop-in file,
`/etc/sysctl.d/99-gentoo-post-install.conf`, containing a curated list of IPv4,
kernel, and filesystem tunables, then makes sure they load at boot and applies them
now with `sysctl --system`. With `--harden-ipv6` it appends an IPv6 block. Doing it
by hand is exactly that: drop one file in `/etc/sysctl.d/`, then reload. Nothing here
installs packages or changes a service beyond enabling the OpenRC `sysctl` loader.

## Concepts

`sysctl` exposes kernel tunables under `/proc/sys/`. Each setting is a `key = value`
line where dots map to the path (for example `net.ipv4.tcp_syncookies` is
`/proc/sys/net/ipv4/tcp_syncookies`). Values set with the `sysctl` command are live
but not persistent; files under `/etc/sysctl.d/` are read at boot (and by
`sysctl --system`) so the settings survive a reboot.

Why a drop-in and not `/etc/sysctl.conf`: `/etc/sysctl.d/` is the modern, additive
location. Files load in lexical order, so the `99-` prefix means this file is read
last and wins over defaults. One self-contained file is also trivial to review and to
remove for rollback.

The knobs fall into three groups:

- **Network anti-spoofing / anti-DoS.** Reverse-path filtering, SYN cookies, and
  ignoring ICMP redirects and source routing make the host harder to spoof, redirect,
  or flood.
- **Kernel information-leak reduction.** Hiding kernel pointers and the kernel log,
  and restricting `ptrace`, stop an unprivileged local user from reading addresses and
  memory that help build an exploit.
- **Filesystem link/FIFO protections.** These close classic time-of-check/time-of-use
  tricks in world-writable directories like `/tmp`.

Some knobs depend on kernel config (for example `kernel.yama.ptrace_scope` needs
`CONFIG_SECURITY_YAMA`). If a key is missing, `sysctl --system` prints an error for
that line and moves on; that is why the script treats a non-zero exit as a warning,
not a failure.

## Do it by hand

### 1. Write the hardening drop-in

Create the file with the same content the script writes. Every line is a kernel
tunable; the comments explain intent.

```bash
# root
cat > /etc/sysctl.d/99-gentoo-post-install.conf <<'EOF'
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
```

What each group buys you:

- **`rp_filter = 1`** (strict reverse-path filtering): drop an incoming packet if the
  reply would not go back out the same interface it arrived on. This blocks the
  simplest source-address spoofing. The `all` and `default` entries cover current and
  future interfaces.
- **`accept_redirects = 0` / `secure_redirects = 0`**: ignore ICMP redirect messages.
  A redirect can silently rewrite your routing table and steer traffic through an
  attacker. `send_redirects = 0` stops this host from issuing them (only routers
  legitimately do).
- **`accept_source_route = 0`**: refuse packets that carry their own routing path, an
  old technique for bypassing firewalls and routing.
- **`log_martians = 1`**: log packets with impossible source addresses so spoofing
  attempts show up in the kernel log.
- **`icmp_echo_ignore_broadcasts = 1`**: do not answer pings sent to a broadcast
  address, which neutralizes "smurf" amplification. `icmp_ignore_bogus_error_responses
  = 1` discards malformed ICMP error replies to cut noise.
- **`tcp_syncookies = 1`**: fall back to SYN cookies when the SYN backlog fills, which
  lets the host survive a SYN-flood instead of dropping new connections.
- **`tcp_rfc1337 = 1`**: drop RST packets for sockets in TIME-WAIT, mitigating the
  TIME-WAIT assassination hazard from RFC 1337.
- **`kptr_restrict = 2`**: always print kernel pointers in `/proc` as zeros, even for
  root, so leaked addresses cannot defeat KASLR.
- **`dmesg_restrict = 1`**: only privileged users can read the kernel ring buffer,
  which otherwise leaks addresses and hardware details.
- **`yama.ptrace_scope = 1`**: a process may only `ptrace` its own descendants, so one
  compromised user program cannot read another process's memory (needs Yama in the
  kernel).
- **`randomize_va_space = 2`**: full address-space layout randomization (stack, heap,
  and mmap). This is usually the default, but pinning it is cheap insurance.
- **`sysrq = 0`**: disable the magic SysRq key combinations, which can be abused at a
  console to dump memory or trigger actions.
- **`fs.protected_hardlinks` / `protected_symlinks`**: refuse to follow links in
  sticky world-writable directories unless the follower owns the link, closing a
  family of symlink races in `/tmp`.
- **`fs.protected_fifos = 2` / `protected_regular = 2`**: do not let a program write
  through a FIFO or regular file it does not own in a sticky world- or group-writable
  directory, blocking a related `O_CREAT` trick.
- **`fs.suid_dumpable = 0`**: never write a core dump for a set-UID program, since the
  dump could contain secrets it ran with elevated rights.

### 2. (IPv6) Add the IPv6 block

Only if you want the IPv6 hardening the script's `--harden-ipv6` adds, append this
block to the same file:

```bash
# root
cat >> /etc/sysctl.d/99-gentoo-post-install.conf <<'EOF'

# --- IPv6 network ---
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
EOF
```

`accept_redirects` and `accept_source_route` mean the same as their IPv4 twins.
`accept_ra = 0` tells the host to ignore IPv6 Router Advertisements, which blocks a
rogue router from autoconfiguring your addresses and routes.

**Warning:** `accept_ra = 0` disables SLAAC autoconfiguration. On a network that hands out IPv6
only via Router Advertisements (common on home and many ISP setups), this can leave
the host without an IPv6 address or default route. Enable the IPv6 block only if you
use static IPv6 or DHCPv6, or if you can accept losing IPv6 connectivity.

### 3. Make the values load at boot

On systemd, `systemd-sysctl` reads `/etc/sysctl.d/` automatically at boot, so there is
nothing to enable. On OpenRC, the `sysctl` service (from `sys-apps/procps`) is what
applies these files, so add it to the `boot` runlevel:

```bash
# root  (OpenRC only)
rc-update add sysctl boot
```

### 4. Apply the settings now

Load every file under `/etc/sysctl.d/` into the running kernel without a reboot:

```bash
# root
sysctl --system
```

`--system` reads all the standard directories in order and prints each file it loads.
If it exits non-zero, read the error: it usually names a single key your kernel does
not expose (for example Yama is not built in), while every other key still applied.

## Verify

Query the live values and confirm they match the file:

```bash
# root
sysctl net.ipv4.tcp_syncookies net.ipv4.conf.all.rp_filter \
       kernel.kptr_restrict kernel.dmesg_restrict kernel.yama.ptrace_scope
# expect: tcp_syncookies = 1, rp_filter = 1, kptr_restrict = 2,
#         dmesg_restrict = 1, ptrace_scope = 1
```

If you added the IPv6 block:

```bash
# root
sysctl net.ipv6.conf.all.accept_ra net.ipv6.conf.all.accept_redirects
# expect both = 0
```

Reading a key back as the value you set means it is live. A "No such file or
directory" error means the matching kernel feature is not built in, so that one line
is a no-op on this kernel.

## Pitfalls and rollback

- **`rp_filter = 1` and asymmetric routing.** On a multi-homed host or some VPN/policy
  routing setups, replies legitimately leave by a different interface than they
  arrived, and strict filtering drops them. If that is your case, set the relevant
  interface to loose mode (`2`) instead of disabling it globally.
- **`accept_ra = 0` breaking IPv6.** See the warning above; this is the most common
  surprise. Remove the IPv6 block (or set `accept_ra = 1`) and reload.
- **A key errors out.** `sysctl --system` naming a missing key is almost always a
  kernel-config gap (Yama, or a tunable disabled in your kernel). It is harmless; the
  other keys still applied.
- **Rollback.** Remove the drop-in and reload. The now-removed settings revert to the
  kernel defaults on the next reload or reboot (some live values that were already
  changed persist until reboot):
  ```bash
  # root
  rm -f /etc/sysctl.d/99-gentoo-post-install.conf
  sysctl --system
  ```
  The script's `--rollback` does exactly this (removes the drop-in, then runs
  `sysctl --system`). It does not remove the OpenRC `sysctl` boot service, which is
  harmless to leave enabled.

## Script reference

- **Step:** `08` - `step_08_sysctl_hardening`
- **Flags:** `--sysctl-harden`, `--harden-ipv6`
- **Managed files:** `/etc/sysctl.d/99-gentoo-post-install.conf`
- **Also touches:** adds the `sysctl` service to the OpenRC `boot` runlevel; runs
  `sysctl --system`. (The server, hardened, and opsec profiles enable `--sysctl-harden`,
  and the hardened and opsec profiles also enable `--harden-ipv6`, by default.)

---
[← Previous: Kernel, microcode & Secure Boot](08-kernel-microcode.md) · [Handbook index](README.md) · [Next: Firewall →](10-firewall.md)

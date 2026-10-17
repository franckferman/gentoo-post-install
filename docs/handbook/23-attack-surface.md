# Attack-surface minimization

> Shrink what an attacker (or a bug) can reach: blacklist rarely-needed kernel modules,
> disable kexec and core dumps, apply an opsec sysctl set, and mask network-exposed
> services you do not use. Mirrors the script's step 21 (`--minimize-surface`).

## What the script automates

`step_21_minimize_surface` is opt-in. When enabled it writes a module blacklist, an
"opsec" sysctl drop-in (kexec off, strict ptrace, BPF hardening), a limits drop-in that
forbids core dumps, and disables a short list of commonly-unneeded, network-facing
services. The `opsec` system profile turns this on for you; otherwise pass
`--minimize-surface`.

**Warning:** Everything here **removes functionality on purpose**. Blacklisting modules can disable
hardware you actually use; masking services breaks printing (CUPS) and local network
service discovery (mDNS/Avahi). Review each file below and re-enable what you need.

## Concepts

"Attack surface" is the sum of code paths an unprivileged user, a network peer, or a
malicious device can reach. You reduce it by turning off code that is present but
unnecessary on your machine.

- **Kernel modules** are drivers and protocol handlers the kernel can load on demand
  (when a device appears, or a socket of some family is opened). Each one is extra
  privileged code. Modules with a history of bugs or a DMA path (FireWire, Thunderbolt)
  or obscure filesystems and network protocols you never use are good candidates to
  block. The idiom `install <module> /bin/true` tells `modprobe` to run `/bin/true`
  (a no-op that succeeds) instead of loading the module, so any attempt to auto-load it
  quietly does nothing.
- **kexec** lets the kernel boot a *new* kernel directly, bypassing the bootloader and
  any Secure Boot verification. Disabling it (`kexec_load_disabled=1`) closes a path to
  loading an unsigned kernel. It is a one-way switch until the next reboot.
- **Core dumps** are memory snapshots written when a program crashes. They can contain
  secrets (keys, passwords) and are a local information-disclosure risk, so hardened
  systems forbid them.
- **ptrace / BPF / perf** are powerful introspection interfaces. Restricting them
  (`yama.ptrace_scope`, `unprivileged_bpf_disabled`, `perf_event_paranoid`) limits what
  an unprivileged process can inspect or inject into others.
- **Services** listening on the network (mDNS, print spooler, RPC, NFS) are reachable
  code. If you do not use them, do not run them.

## Do it by hand

### 1. Blacklist risky / unused modules

Write `/etc/modprobe.d/gpi-blacklist.conf` with one `install ... /bin/true` line per
module. This is the exact set the script blocks: FireWire and Thunderbolt (DMA),
obscure filesystems, and rarely-used network protocols.

```bash
# root
cat > /etc/modprobe.d/gpi-blacklist.conf <<'EOF'
# Managed by gentoo-post-install - attack surface reduction
install firewire-core /bin/true
install firewire-ohci /bin/true
install thunderbolt /bin/true
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install udf /bin/true
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
EOF
```

**Warning:** If you use a Thunderbolt dock, a FireWire device, optical media or UDF-formatted
media, or any of these filesystems/protocols, remove that line. `install ... /bin/true`
does not just blacklist; it actively prevents load even on explicit `modprobe`.

### 2. Apply the opsec sysctl set

```bash
# root
cat > /etc/sysctl.d/99-gpi-opsec.conf <<'EOF'
# Managed by gentoo-post-install - opsec sysctl
kernel.kexec_load_disabled = 1
kernel.yama.ptrace_scope = 2
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
kernel.perf_event_paranoid = 3
dev.tty.ldisc_autoload = 0
EOF
sysctl --system
```

- `kexec_load_disabled = 1`: no loading a replacement kernel (one-way until reboot).
- `yama.ptrace_scope = 2`: only root may `ptrace`; processes cannot trace each other.
- `unprivileged_bpf_disabled = 1` + `bpf_jit_harden = 2`: lock down the BPF subsystem.
- `perf_event_paranoid = 3`: deny unprivileged use of performance counters.
- `dev.tty.ldisc_autoload = 0`: stop unprivileged auto-loading of TTY line disciplines.

`sysctl --system` re-reads every `*.conf` under the standard directories and applies
them now, so you do not need a reboot for these. See
[sysctl hardening](09-sysctl-hardening.md) for the base set this complements.

### 3. Forbid core dumps

```bash
# root
cat > /etc/security/limits.d/gpi-coredump.conf <<'EOF'
# Managed by gentoo-post-install
* hard core 0
* soft core 0
EOF
```

This sets the core-dump size limit to zero for all users via PAM's limits. The base
sysctl hardening (chapter 09) also sets `fs.suid_dumpable = 0` so setuid programs never
dump; the two together close the common core-dump leak paths. See also
[Log-footprint minimization](24-log-minimization.md), which additionally routes
`kernel.core_pattern` to `/bin/false`.

### 4. Mask unneeded network-facing services

Disable services you do not use. The script targets mDNS (Avahi), printing (CUPS), and
RPC/NFS; each is a no-op if the service is not installed.

On **systemd**:

```bash
# root  (systemd)
for svc in avahi-daemon cups cupsd rpcbind nfs; do
  systemctl disable --now "$svc" 2>/dev/null || true
done
```

On **OpenRC**:

```bash
# root  (OpenRC)
for svc in avahi-daemon cups cupsd rpcbind nfs; do
  rc-service "$svc" stop 2>/dev/null || true
  rc-update del "$svc" 2>/dev/null || true
done
```

**Warning:** Disabling `cups`/`cupsd` stops local and network printing; disabling `avahi-daemon`
breaks `.local` name resolution and device discovery (network printers, Chromecast-style
devices). Keep whichever you rely on.

## Verify

```bash
# root
# Modules are blocked (should print "install /bin/true"):
modprobe --show-depends dccp 2>&1 | head -1

# sysctl values are live:
sysctl kernel.kexec_load_disabled kernel.yama.ptrace_scope kernel.perf_event_paranoid

# Core-dump limit is zero for a login shell:
ulimit -c          # -> 0  (in a fresh login session)

# Services are off:
systemctl is-enabled cups 2>/dev/null         # systemd: disabled / not-found
rc-update show | grep -E 'cups|avahi|nfs'     # OpenRC: no output
```

A blocked module should report that `modprobe` is wired to `/bin/true`; a value like
`kernel.kexec_load_disabled = 1` confirms the sysctl applied.

## Pitfalls and rollback

- **Missing hardware after reboot:** a blacklisted module was actually needed (dock,
  FireWire, UDF media). Remove its line from `gpi-blacklist.conf` and
  `modprobe <module>` (or reboot).
- **Printing or `.local` names stopped working:** re-enable `cups` / `avahi-daemon`.
- **kexec-based tools fail:** expected; `kexec_load_disabled` cannot be undone without a
  reboot, even after removing the sysctl file.
- **Rollback:** remove the drop-ins and re-apply sysctl; re-enable services as needed:
  ```bash
  # root
  rm -f /etc/modprobe.d/gpi-blacklist.conf /etc/sysctl.d/99-gpi-opsec.conf \
        /etc/security/limits.d/gpi-coredump.conf
  sysctl --system        # note: kexec stays disabled until reboot
  ```
  Core-dump and limits changes apply to new login sessions; log out and back in (or
  reboot) for a clean slate.

## Script reference

- **Step:** `21` - `step_21_minimize_surface`
- **Flags:** `--minimize-surface` (also enabled by the `opsec` profile)
- **Managed files:** `/etc/modprobe.d/gpi-blacklist.conf`,
  `/etc/sysctl.d/99-gpi-opsec.conf`, `/etc/security/limits.d/gpi-coredump.conf`; plus
  disabling `avahi-daemon`, `cups`/`cupsd`, `rpcbind`, `nfs` via the init system.

---
[← Previous: Desktop environment & display manager](22-desktop-environment.md) · [Handbook index](README.md) · [Next: Log-footprint minimization →](24-log-minimization.md)

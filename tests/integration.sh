#!/usr/bin/env bash
#
# Integration harness for gentoo-post-install.
# Unlike tests/test.sh (pure functions, dry-run), this runs selected step_* functions
# FOR REAL against a throwaway temp tree, with every external command mocked, and
# asserts the files they produce (content included). It never touches the host: all
# Portage paths are redirected under a temp dir, PRIV is empty (no sudo), and mocks
# stand in for emerge/eselect/etc.
#
# Usage: bash tests/integration.sh
#
# The config globals set below are consumed by the sourced library functions;
# ShellCheck can't see across the dynamic `source`, so silence its file-wide "unused" warning.
# shellcheck disable=SC2034
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/../gentoo-post-install.sh"

ROOT="$(mktemp -d)"
MOCKBIN="$(mktemp -d)"
trap 'rm -rf "$ROOT" "$MOCKBIN"' EXIT

# --- mocks: everything the exercised steps might call (all succeed, no side effects) ---
for c in emerge eselect emaint getuto eix-update eix-sync mirrorselect sysctl \
         systemctl rc-update rc-service chsh sudo doas; do
    printf '#!/bin/sh\nexit 0\n' > "${MOCKBIN}/${c}"; chmod +x "${MOCKBIN}/${c}"
done
# cpuid2cpuflags must emit realistic output for the CPU-flags file.
cat > "${MOCKBIN}/cpuid2cpuflags" <<'EOF'
#!/bin/sh
echo "CPU_FLAGS_X86: aes avx avx2 sse4_2"
EOF
chmod +x "${MOCKBIN}/cpuid2cpuflags"
export PATH="${MOCKBIN}:${PATH}"

# --- redirect all Portage paths under the temp tree BEFORE sourcing ---
export MAKE_CONF="${ROOT}/etc/portage/make.conf"
export PKG_USE_DIR="${ROOT}/etc/portage/package.use"
export PKG_ACCEPT_DIR="${ROOT}/etc/portage/package.accept_keywords"
export PKG_LICENSE_DIR="${ROOT}/etc/portage/package.license"
export BINREPOS_DIR="${ROOT}/etc/portage/binrepos.conf"
mkdir -p "$(dirname "$MAKE_CONF")"

# shellcheck source=/dev/null
GPI_LIB=1 source "$SCRIPT"

# --- run in real mode against the temp tree (no sudo, no dry-run) ---
DRY_RUN=false
PRIV=""
ASSUME_YES=true
NPROC=8
RAM_GB=16

TESTS=0
FAILS=0
ok()   { TESTS=$((TESTS+1)); printf '  ok   %s\n' "$1"; }
bad()  { TESTS=$((TESTS+1)); FAILS=$((FAILS+1)); printf '  FAIL %s\n' "$1"; }
assert_file()  { if [ -f "$1" ]; then ok "file exists: ${1#"$ROOT"}"; else bad "missing file: ${1#"$ROOT"}"; fi; }
assert_grep()  { if grep -qE "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3 (in ${1#"$ROOT"})"; fi; }
assert_count() { local n; n="$(grep -cE "$2" "$1" 2>/dev/null || echo 0)"; if [ "$n" = "$3" ]; then ok "$4"; else bad "$4 (got $n, want $3)"; fi; }

echo "== step_02_portage_tuning (real writes to temp make.conf) =="
: > "$MAKE_CONF"
step_02_portage_tuning >/dev/null 2>&1
assert_grep "$MAKE_CONF" '^MAKEOPTS="-j[0-9]+ -l[0-9]+"' "MAKEOPTS written"
assert_grep "$MAKE_CONF" '^COMMON_FLAGS="-march=native -O2 -pipe"' "COMMON_FLAGS march=native"
assert_grep "$MAKE_CONF" '^EMERGE_DEFAULT_OPTS=' "EMERGE_DEFAULT_OPTS written"
assert_grep "$MAKE_CONF" '^FEATURES=' "FEATURES written"
assert_file "${PKG_USE_DIR}/00cpu-flags"
assert_grep "${PKG_USE_DIR}/00cpu-flags" 'CPU_FLAGS_X86: aes' "CPU flags captured"
# idempotency: run again, MAKEOPTS must not duplicate
step_02_portage_tuning >/dev/null 2>&1
assert_count "$MAKE_CONF" '^MAKEOPTS=' 1 "MAKEOPTS not duplicated on re-run"

echo "== step_06_use_flags =="
SYSTEM_PROFILE=hardened
step_06_use_flags >/dev/null 2>&1
assert_file "${PKG_USE_DIR}/10-baseline"
assert_grep "${PKG_USE_DIR}/10-baseline" '^\*/\* ' "USE baseline uses the */* wildcard"

echo "== step_03_binhost =="
ENABLE_BINHOST=true
BINHOST_URI="https://distfiles.gentoo.org/releases/amd64/binpackages/23.0/x86-64"
step_03_binhost >/dev/null 2>&1
assert_file "${BINREPOS_DIR}/gentoobinhost.conf"
assert_grep "${BINREPOS_DIR}/gentoobinhost.conf" '^sync-uri = https://distfiles' "binhost sync-uri"
assert_grep "${BINREPOS_DIR}/gentoobinhost.conf" '^verify-signature = true' "binhost signature verification"

echo "== step_19_apps license drop-in (chrome) =="
APPS="chrome"
APPS_PROFILE=""
INSTALL_STEAM=false
step_19_apps >/dev/null 2>&1
assert_file "${PKG_LICENSE_DIR}/gpi-apps"
assert_grep "${PKG_LICENSE_DIR}/gpi-apps" 'www-client/google-chrome google-chrome' "chrome license accepted"

echo "== _install_microcode (vendor-detected) =="
INSTALL_MICROCODE=true
_install_microcode >/dev/null 2>&1
case "$(_cpu_vendor)" in
    GenuineIntel)
        assert_file "${PKG_USE_DIR}/30-microcode"
        assert_grep "${PKG_USE_DIR}/30-microcode" 'sys-firmware/intel-microcode' "intel-microcode USE fragment" ;;
    *)
        ok "non-Intel CPU: microcode path via linux-firmware (no fragment expected)" ;;
esac

echo
echo "== GPI_SYSROOT: absolute /etc drop-ins written for real under a staged root =="
# write_root_file honors GPI_SYSROOT, so the security-critical drop-ins that target
# absolute paths (/etc/sysctl.d, /etc/modprobe.d, /etc/security/limits.d) can be run
# for real and their content asserted - without touching the host. Only steps whose
# side commands are all mocked are exercised here (step_08 sysctl, step_21 surface).
SYSROOT="${ROOT}/sysroot"
export GPI_SYSROOT="$SYSROOT"
INIT_SYSTEM=systemd
SYSTEM_PROFILE=hardened
INSTALL_HARDENED_MALLOC=false

# --- step_08: sysctl hardening (IPv4 + kernel + IPv6) ---
HARDEN_SYSCTL=true
HARDEN_IPV6=true
step_08_sysctl_hardening >/dev/null 2>&1
sysctl_f="${SYSROOT}/etc/sysctl.d/99-gentoo-post-install.conf"
assert_file "$sysctl_f"
assert_grep "$sysctl_f" '^net\.ipv4\.tcp_syncookies = 1'   "sysctl: tcp_syncookies"
assert_grep "$sysctl_f" '^kernel\.kptr_restrict = 2'       "sysctl: kptr_restrict"
assert_grep "$sysctl_f" '^kernel\.yama\.ptrace_scope = 1'  "sysctl: yama ptrace_scope"
assert_grep "$sysctl_f" '^net\.ipv6\.conf\.all\.accept_ra = 0' "sysctl: IPv6 block present (HARDEN_IPV6)"

# --- step_21: attack-surface minimization (module blacklist + opsec sysctl + coredumps) ---
MINIMIZE_SURFACE=true
step_21_minimize_surface >/dev/null 2>&1
blk="${SYSROOT}/etc/modprobe.d/gpi-blacklist.conf"
assert_file "$blk"
assert_grep "$blk" '^install dccp /bin/true'   "modprobe: dccp blacklisted"
assert_grep "$blk" '^install firewire-core /bin/true' "modprobe: firewire blacklisted"
opsec="${SYSROOT}/etc/sysctl.d/99-gpi-opsec.conf"
assert_file "$opsec"
assert_grep "$opsec" '^kernel\.kexec_load_disabled = 1' "opsec sysctl: kexec disabled"
assert_grep "$opsec" '^kernel\.unprivileged_bpf_disabled = 1' "opsec sysctl: unprivileged BPF off"
assert_file "${SYSROOT}/etc/security/limits.d/gpi-coredump.conf"
assert_grep "${SYSROOT}/etc/security/limits.d/gpi-coredump.conf" '^\* hard core 0' "limits: core dumps disabled"
unset GPI_SYSROOT

echo "== idempotency: re-running every writing step yields a byte-identical tree =="
# Snapshot the whole temp tree (path + content hash), run all writers a second time,
# snapshot again. Any drift - appended duplicate, rewritten timestamp, growth - changes
# the manifest and fails the check. Backups (.gpi.bak) are created once, so they are stable.
_manifest() { find "$ROOT" -type f -exec sha256sum {} + | sed "s#${ROOT}##g" | sort; }
idem_before="$(_manifest)"
step_02_portage_tuning >/dev/null 2>&1
step_06_use_flags      >/dev/null 2>&1
step_03_binhost        >/dev/null 2>&1
step_19_apps           >/dev/null 2>&1
_install_microcode     >/dev/null 2>&1
idem_after="$(_manifest)"
if [ "$idem_before" = "$idem_after" ]; then
    ok "tree is byte-identical after a second full run (no duplication/drift)"
else
    bad "tree changed on re-run (idempotency broken)"
    diff <(printf '%s\n' "$idem_before") <(printf '%s\n' "$idem_after") | head -20
fi

if [ "$FAILS" -eq 0 ]; then
    echo "All ${TESTS} integration checks passed."
    exit 0
else
    echo "${FAILS}/${TESTS} integration checks FAILED."
    exit 1
fi

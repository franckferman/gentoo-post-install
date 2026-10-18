# USBGuard

> Install USBGuard and lock the machine to the USB devices that are plugged in *right
> now*, blocking everything else. Mirrors the script's step 13 (`--usbguard`), which is
> opt-in for exactly the reason below.

> **Warning:** **USBGuard can lock you out of your own keyboard and mouse.** It blocks every USB
> device that is not in its allow-list. If you enable it without first authorizing the
> devices you are using, your USB keyboard and pointer can stop responding the moment
> the service starts. Always generate the policy from the currently-connected devices
> first, keep a non-USB way in (a laptop's built-in keyboard, a serial/SSH session, or a
> PS/2 keyboard) available, and read the generated rules before enabling the service.

## What the script automates

`step_13_usbguard` is opt-in and prompts for confirmation before doing anything. It
installs `sys-apps/usbguard`, generates an initial allow-list from the devices attached
at that moment (`usbguard generate-policy > /etc/usbguard/rules.conf`), tightens that
file's permissions to `600`, and then enables and starts the `usbguard` service. The
important idea: the policy is seeded from *your current hardware*, so the keyboard and
mouse you are using are allowed, and only *new* devices are blocked.

## Concepts

USBGuard is a userspace daemon that implements a USB device allow-list in the kernel. It
decides, per device, whether to **allow**, **block**, or **reject** it based on a rule
set:

- **Rules** live in `/etc/usbguard/rules.conf`. Each line matches on attributes such as
  USB `id` (vendor:product), serial number, `hash`, `name`, `via-port`, and
  `with-interface` (the device classes it exposes), and ends in `allow`, `block`, or
  `reject`. The first matching rule wins; anything with no match gets the daemon's
  default policy.
- **`allow`** authorizes a device, **`block`** leaves it unauthorized (present but
  dead), and **`reject`** logically unplugs it.
- **`generate-policy`** inspects every device currently connected and emits an `allow`
  rule for each. This is how you bootstrap a working policy without hand-writing rules:
  the hardware in front of you becomes the baseline.
- **`ImplicitPolicyTarget`** in `/etc/usbguard/usbguard-daemon.conf` controls what
  happens to devices that match no rule (`block` by default). This is what makes a
  newly inserted, unknown USB stick inert.

Because the policy is pinned to specific devices, swapping to a different keyboard later
means that keyboard is *not* in the list and will be blocked. That is the whole point of
the tool, and also its main foot-gun.

## Do it by hand

### 1. See what is connected (and decide if this is safe)

```bash
# root
usb-devices 2>/dev/null | grep -E 'Manufacturer|Product' || lsusb
```

Confirm your keyboard and mouse appear. If you are on a remote or headless box, or you
rely on a USB keyboard with nothing else to fall back on, understand that enabling the
service commits you to this device set.

### 2. Install USBGuard

```bash
# root
emerge --ask=n --noreplace sys-apps/usbguard
```

`--noreplace` keeps the install idempotent, matching the script's `emerge_install`
helper.

### 3. Generate the initial policy from current devices

```bash
# root
usbguard generate-policy > /etc/usbguard/rules.conf
chmod 600 /etc/usbguard/rules.conf
```

`generate-policy` writes one `allow` rule per currently-attached device to
`/etc/usbguard/rules.conf`. `chmod 600` restricts the file to root, because it describes
your exact hardware (serials, hashes) and is security-sensitive. The script does exactly
these two commands.

### 4. **Warning:** Read the rules before you enable anything

```bash
# root
cat /etc/usbguard/rules.conf
```

Every device you need to keep working (keyboard, mouse, hub, internal card reader,
Bluetooth/wifi-over-USB) must have an `allow` line. If one is missing, plug it in and
re-run `generate-policy`, or add an `allow` rule by hand. **Do not skip this step.** It
is your last chance to catch a missing input device before the daemon starts enforcing.

### 5. Enable and start the service (carefully)

The script's `service_enable_start` means "enable at boot and start now". Do this only
once you have confirmed the rules:

```bash
# root - systemd
systemctl enable --now usbguard

# root - OpenRC
rc-update add usbguard default
rc-service usbguard start
```

The instant the daemon starts, any connected device without an `allow` rule is blocked.
If your input stops responding, see the rollback section.

## Verify

```bash
# root
usbguard list-devices                 # every device, with 'allow' or 'block' status
usbguard list-rules                    # the active rule set
```

`list-devices` should show your keyboard and mouse as `allow`. Test enforcement by
inserting a USB stick that was *not* present during generation: it should appear as
`block`. To authorize it for this session, use `usbguard allow-device <id>`; to make
that permanent, append a rule with `usbguard allow-device -p <id>`.

Service state:

```bash
# systemd
systemctl is-active usbguard
# OpenRC
rc-service usbguard status
```

## Pitfalls and rollback

- **Warning:** **Locked out of your keyboard/mouse.** If input dies after the service starts, you
  need a way in that USBGuard is not blocking: a laptop's built-in (non-USB) keyboard, a
  serial console, or an existing SSH session. From there, stop the service (below). This
  is why the script prompts before proceeding and why you keep a fallback ready.
- **New/replacement devices are blocked.** Swapping keyboards or plugging in a new hub
  will be blocked by design. Authorize with `usbguard allow-device -p <id>` (the `-p`
  makes it permanent) rather than disabling the daemon.
- **World-writable rules.** If `/etc/usbguard/rules.conf` is not `600`, the daemon may
  refuse to load it. Keep the permissions tight.
- **Rollback:** USBGuard is not in the script's `--rollback` managed-file list, so
  rollback leaves it alone. Recover by hand (stop and disable the service), which
  restores normal USB behavior immediately:
  ```bash
  # systemd
  systemctl disable --now usbguard
  # OpenRC
  rc-service usbguard stop; rc-update del usbguard
  # optional: remove the policy and/or the package
  rm -f /etc/usbguard/rules.conf
  emerge --ask=n --depclean sys-apps/usbguard
  ```
  Stopping the service is enough to get your USB devices working again; removing the
  policy file and package is optional cleanup.

## Script reference

- **Step:** `13` - `step_13_usbguard` (opt-in; prompts unless `--yes`)
- **Flags:** `--usbguard`
- **Managed files:** `/etc/usbguard/rules.conf` (generated from connected devices,
  `chmod 600`; not tracked by `--rollback`)

---
[← Previous: fail2ban](13-fail2ban.md) · [Handbook index](README.md) · [Next: AppArmor →](15-apparmor.md)

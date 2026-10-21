# GPU drivers

> Install a complete graphics stack for your card: the `VIDEO_CARDS` token, Mesa,
> Vulkan, hardware video decode (VA-API), and optionally OpenCL/compute. Mirrors the
> script's step 24 (`--gpu`).

## What the script automates

`step_24_gpu` detects your GPU vendor with `lspci`, sets `VIDEO_CARDS` in `make.conf`,
writes the needed per-package USE flags, and installs the driver stack for Intel, AMD,
or NVIDIA (proprietary or the FOSS `nouveau`). It optionally adds the OpenCL/compute
layer. Doing it by hand is the same four moves: pick the token, set USE, install, rebuild.

## Concepts

A Linux GPU stack has layers, and on Gentoo you opt into them explicitly:

- **Kernel driver (DRM):** `i915`/`xe` (Intel), `amdgpu` (AMD), `nouveau` or the
  proprietary `nvidia` module. Usually built by your kernel; for AMD it also needs
  firmware blobs from `sys-kernel/linux-firmware`.
- **`VIDEO_CARDS`** in `make.conf` is the switch that tells Mesa and friends *which*
  user-space drivers to build (`intel`, `amdgpu radeonsi`, `nouveau`, or `nvidia`).
  Changing it means rebuilding the graphics packages.
- **Mesa** provides OpenGL and (with the `vulkan` USE) Vulkan for the open drivers
  (Intel ANV / Iris, AMD RADV / radeonsi, nouveau NVK). The proprietary NVIDIA driver
  ships its own GL/Vulkan instead of Mesa.
- **VA-API** is hardware video decode/encode. Intel uses a separate media driver
  (`libva-intel-media-driver`, the iHD driver); AMD gets it from Mesa's `vaapi` USE;
  NVIDIA bridges it with `nvidia-vaapi-driver`.
- **Compute (OpenCL/CUDA):** Intel uses `intel-compute-runtime` (the NEO stack); AMD
  can use Mesa's lightweight `rusticl`; NVIDIA's OpenCL/CUDA ship with the driver.

## Do it by hand

The examples below assume you know your vendor (`lspci | grep -Ei 'vga|3d|display'`).
Follow the block for your card.

### Intel (iGPU: Iris Xe, UHD, ...)

```bash
# root
# 1. VIDEO_CARDS token
grep -q '^VIDEO_CARDS=' /etc/portage/make.conf \
  && sed -i 's/^VIDEO_CARDS=.*/VIDEO_CARDS="intel"/' /etc/portage/make.conf \
  || echo 'VIDEO_CARDS="intel"' >> /etc/portage/make.conf

# 2. Make sure Mesa builds Vulkan
echo 'media-libs/mesa vulkan' > /etc/portage/package.use/40-gpu

# 3. Install the stack: GL/Vulkan, loader+tools, VA-API (iHD), diagnostics,
#    and OpenCL (NEO) for compute.
emerge --ask=n media-libs/mesa media-libs/vulkan-loader dev-util/vulkan-tools \
  x11-apps/mesa-progs media-libs/libva-intel-media-driver media-video/libva-utils \
  dev-libs/intel-compute-runtime dev-util/clinfo
```

Skip the last line's `intel-compute-runtime dev-util/clinfo` if you do not need
OpenCL (the script's `--no-gpu-compute`). Note: Intel's OpenCL kernel JIT is slow on
integrated GPUs, which matters for tools like hashcat.

### AMD (Radeon)

```bash
# root
# 1. VIDEO_CARDS: amdgpu (kernel/DRM glue) + radeonsi (Mesa GL/Vulkan)
grep -q '^VIDEO_CARDS=' /etc/portage/make.conf \
  && sed -i 's/^VIDEO_CARDS=.*/VIDEO_CARDS="amdgpu radeonsi"/' /etc/portage/make.conf \
  || echo 'VIDEO_CARDS="amdgpu radeonsi"' >> /etc/portage/make.conf

# 2. Mesa USE: Vulkan (RADV), VA-API (video), opencl (rusticl)
echo 'media-libs/mesa vulkan vaapi opencl' > /etc/portage/package.use/40-gpu

# 3. rusticl needs to know which Gallium driver to expose for OpenCL
echo 'RUSTICL_ENABLE="radeonsi"' >> /etc/portage/make.conf

# 4. Install. amdgpu needs firmware blobs.
emerge --ask=n media-libs/mesa media-libs/vulkan-loader dev-util/vulkan-tools \
  x11-apps/mesa-progs sys-kernel/linux-firmware media-video/libva-utils dev-util/clinfo
```

For heavy GPGPU (not covered here) you would add ROCm separately; rusticl covers most
casual OpenCL needs.

### NVIDIA (proprietary driver)

**Warning:** The proprietary driver builds a **kernel module** (needs your kernel sources or a
dist-kernel), requires accepting the NVIDIA license, conflicts with `nouveau`, and
needs a **reboot**. Get it wrong and X may not start. Have a TTY/console ready.

```bash
# root
# 1. VIDEO_CARDS
grep -q '^VIDEO_CARDS=' /etc/portage/make.conf \
  && sed -i 's/^VIDEO_CARDS=.*/VIDEO_CARDS="nvidia"/' /etc/portage/make.conf \
  || echo 'VIDEO_CARDS="nvidia"' >> /etc/portage/make.conf

# 2. Accept the license (package.license drop-in)
echo 'x11-drivers/nvidia-drivers NVIDIA-r2' > /etc/portage/package.license/gpi-gpu

# 3. Blacklist nouveau and enable DRM modeset (needed for Wayland + clean console)
cat > /etc/modprobe.d/gpi-nvidia.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
options nvidia_drm modeset=1
EOF

# 4. Install the driver + Vulkan loader/tools + optional VA-API bridge + diagnostics
emerge --ask=n media-libs/vulkan-loader dev-util/vulkan-tools x11-apps/mesa-progs \
  x11-drivers/nvidia-drivers media-video/nvidia-vaapi-driver media-video/libva-utils dev-util/clinfo

# 5. Make NVIDIA the active GL provider
eselect opengl set nvidia
```

OpenCL/CUDA ship with the driver; the full CUDA toolkit
(`dev-util/nvidia-cuda-toolkit`) is a separate, large, opt-in install. Reboot after
installing so `nouveau` is unloaded and the `nvidia` modules load cleanly.

### nouveau (FOSS NVIDIA)

```bash
# root
grep -q '^VIDEO_CARDS=' /etc/portage/make.conf \
  && sed -i 's/^VIDEO_CARDS=.*/VIDEO_CARDS="nouveau"/' /etc/portage/make.conf \
  || echo 'VIDEO_CARDS="nouveau"' >> /etc/portage/make.conf
echo 'media-libs/mesa vulkan' > /etc/portage/package.use/40-gpu   # NVK is experimental
emerge --ask=n media-libs/mesa media-libs/vulkan-loader dev-util/vulkan-tools \
  x11-apps/mesa-progs sys-kernel/linux-firmware media-video/libva-utils
```

### Final step for every vendor: rebuild what changed

Changing `VIDEO_CARDS` (and Mesa USE) means the graphics packages must be rebuilt to
pick up the new drivers:

```bash
# root
emerge --ask=n --update --deep --newuse @world
```

## Verify

```bash
# root (or your user, inside a graphical session for the GL/Vulkan ones)
glxinfo -B | grep -i 'renderer'      # OpenGL renderer: should name your GPU, not "llvmpipe"
vulkaninfo --summary                 # lists your Vulkan device(s)
vainfo                               # VA-API: lists supported decode/encode profiles
clinfo -l                            # OpenCL platforms/devices (if you installed compute)
```

Seeing your GPU (e.g. `Mesa Intel(R) Iris(R) Xe Graphics`) and `Accelerated: yes`
means hardware acceleration is live. `llvmpipe` means you fell back to software.

## Pitfalls and rollback

- **`VIDEO_CARDS` set but no `@world` rebuild** → the new driver is not actually built.
  Always rebuild.
- **NVIDIA: X dies after install** → usually `nouveau` was not blacklisted, modeset is
  off, or you forgot to reboot. Check `/etc/modprobe.d/gpi-nvidia.conf` and
  `eselect opengl list`.
- **Auto-detection oddity:** a naive `grep ati` matches "VGA comp**ati**ble
  controller", so vendor detection must use word boundaries (the script does).
- **Rollback:** restore `make.conf` from backup and remove the drop-ins:
  ```bash
  # root
  cp -a /etc/portage/make.conf.gpi.bak /etc/portage/make.conf
  rm -f /etc/portage/package.use/40-gpu /etc/portage/package.license/gpi-gpu \
        /etc/modprobe.d/gpi-nvidia.conf
  ```
  The script's `--rollback` removes exactly those three drop-ins and restores
  `make.conf`. (It does not uninstall the driver packages; do that manually if needed.)

## Script reference

- **Step:** `24` - `step_24_gpu` (+ `_gpu_resolve_vendor`)
- **Flags:** `--gpu`, `--gpu-vendor auto|intel|amd|nvidia|nouveau|none`,
  `--no-gpu-vulkan`, `--no-gpu-vaapi`, `--gpu-compute` / `--no-gpu-compute`
- **Managed files:** `/etc/portage/make.conf` (`VIDEO_CARDS`, and `RUSTICL_ENABLE` for
  AMD), `/etc/portage/package.use/40-gpu`, `/etc/portage/package.license/gpi-gpu`
  (NVIDIA), `/etc/modprobe.d/gpi-nvidia.conf` (NVIDIA)

---
[← Previous: Desktop stack](18-desktop-stack.md) · [Handbook index](README.md) · [Next: Overlays / repositories →](20-overlays.md)

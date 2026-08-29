# Omarchy on WSL

Omarchy can be built into an importable WSL image on top of the official [Arch Linux WSL rootfs](https://gitlab.archlinux.org/archlinux/archlinux-wsl). The image boots to a plain shell — **the desktop never starts on its own** — and `startx` brings the Hyprland session up as a window on the Windows desktop through WSLg.

This is a development and evaluation target, not a supported install path. It exists so a Windows workstation can run this checkout without a VM or a spare machine.

## Building

```bash
omarchy dev wsl build --output ~/omarchy.wsl
```

Everything runs inside Docker, so the command needs no root on the host and cannot touch the host system. It downloads the official rootfs from `https://geo.mirror.pkgbuild.com/wsl/latest/archlinux.wsl` (cached under `$XDG_CACHE_HOME/omarchy/wsl`, verified against the published `.SHA256`), imports it into a scratch Docker image, provisions it, and repacks the result.

By default the checkout is copied to `/usr/local/share/omarchy` and `/etc/omarchy.conf` points `OMARCHY_PATH` at it — the same overlay `omarchy-dev-link` sets up, so the image runs the code you are editing. `--no-dev-link` leaves the released `/usr/share/omarchy` in place instead.

The released `omarchy` and `omarchy-settings` packages are installed either way. They ship the files at fixed system paths that `OMARCHY_PATH` does not cover: `/etc/skel`, the systemd units, `/usr/share/uwsm/env.d/10-omarchy`.

The output is a gzip tar of the root filesystem, with the root of the archive at the root of the filesystem. Gzip is mandatory, not a preference: WSL1 unpacks images with a bsdtar that cannot read zstd, which is why Microsoft rejected zstd for the official Arch image.

## Importing

```powershell
wsl --install --from-file C:\path\to\omarchy.wsl
```

Or, to control the install location:

```powershell
wsl --import Omarchy C:\wsl\omarchy C:\path\to\omarchy.wsl
```

On first run `/etc/oobe.sh` asks for a UNIX username, creates the account at uid 1000, and runs `omarchy-provision-user --first-install` as that user. `[oobe] defaultUid = 1000` in `/etc/wsl-distribution.conf` is what makes WSL log in as that account from then on, so `/etc/wsl.conf` deliberately carries no `[user] default` — a name pinned at build time would be wrong for everyone who picks a different one.

The image ships with no password hashes in `/etc/shadow`, which Microsoft requires of a distributable image. Windows owns the authentication boundary, so there is no password for `sudo` to prompt for; `/etc/sudoers.d/omarchy-wsl` grants `%wheel` passwordless sudo to match.

## What the image contains

`bin/omarchy-apply-wsl` is the WSL counterpart of `bin/omarchy-apply-system`, and `install/wsl/all.sh` is its ordered step list. It deliberately does not call `omarchy-apply-system`: five of that script's steps assume hardware WSL does not have, and there is no skip mechanism anywhere under `install/`.

| Skipped step | Why |
| --- | --- |
| `install/config/increase-lockout-limit.sh` | Rewrites `/etc/pam.d/sddm-autologin` unguarded; sddm is not installed |
| `install/config/enable-services.sh` | Eleven unconditional `systemctl enable`, several for packages the image drops, one of them sddm |
| `install/config/firewall.sh` | ufw filters nothing behind the Windows host's NAT |
| `install/config/snapper.sh` | Assumes a Btrfs root and limine |
| `install/config/docker.sh` | Docker Desktop already integrates with WSL and would fight a second daemon |
| `install/config/locate.sh` | `PRUNE_BIND_MOUNTS = "no"` would send `updatedb` through `/mnt/c` and index the whole Windows drive |
| `install/hardware/all.sh` | Every step of it — GPU, laptop, ASUS, fingerprint, Wi-Fi |
| `install/login/all.sh` | Just `login/sddm.sh` |
| `install/post-install/localdb.sh` | A `updatedb` run whose index is stale the moment the image is imported |

### Packages

`install/wsl/packages.sh` subtracts `install/wsl/omarchy-wsl-skip.packages` from `install/omarchy-base.packages`. It is a skip list rather than a second manifest so a package added to the base list reaches WSL without a second edit; `test/shell.d/wsl-image-test.sh` holds every skip entry to a package that actually exists in the base list.

Dropped: the display manager and boot splash, Bluetooth, printing and mDNS, the firewall, Docker, the power/backlight/DDC/Thunderbolt stack, and the kernel module and wireless regulatory helpers. The skip list carries the reasoning inline.

Added for WSL only: `librsvg` (an SVG delegate for ImageMagick, so the Windows shortcut icon can be rendered from `logo.svg`) and `sudo` (the base rootfs ships it, but the image depends on it).

### Services

`install/wsl/services.sh` is the inverse of `install/config/enable-services.sh`. It sets `multi-user.target` as the default, masks `sddm.service`, and masks the units Microsoft documents as breaking WSL — including `NetworkManager` and `systemd-resolved`, which are exactly what the hardware path enables. WSL supplies the interface and writes `/etc/resolv.conf` itself.

Every call uses `systemctl --root=/`. The build container has no systemd on the bus, and unlike an `arch-chroot` install systemd cannot tell it is not the real root, so a plain `systemctl mask` there fails with "System has not been booted with systemd". With `--root=` it is a pure file operation, which is all that matters for symlinks that take effect on the next boot.

`sddm` is masked even though the package is not installed. It is the only thing that ever starts the compositor, so a later `pacman -S sddm` must not be able to bring the desktop up at boot behind the user's back.

## Starting the desktop

```bash
startx
```

`install/wsl/wslg.sh` installs `/usr/local/bin/startx` as a small wrapper that execs `omarchy-launch-wsl-session`. There is no X server involved despite the name — `startx` is simply where people reach for a desktop from a WSL shell. `xorg-xinit` is not installed and `/usr/local/bin` precedes `/usr/bin`, so nothing is shadowed.

The launcher exports the WSLg environment, forces aquamarine's nested Wayland backend, and then runs the exact line from `default/wayland-sessions/omarchy.desktop`:

```bash
uwsm start -g -1 -e -D Hyprland hyprland.desktop
```

Going through uwsm is what sources `/usr/share/uwsm/env.d/10-omarchy` (and so sets `OMARCHY_PATH`) and lets `default/hypr/autostart.lua` bring up the shell, first-run provisioning, and the rest.

The same environment is installed at `/etc/profile.d/omarchy-wslg.sh` for ordinary shells, so individual GUI apps opened from a prompt find the WSLg sockets too.

### The DRM render node

**Hyprland needs a DRM render node, and stock WSL2 kernels do not have one.** Hyprland's backend (aquamarine) allocates buffers through GBM, which needs a render node even when nesting inside another compositor — which is the mode that puts Hyprland in a WSLg window. WSL2 exposes Microsoft's `/dev/dxg` and no DRM device at all: on a stock kernel `/dev/dri` does not exist.

So on a stock kernel, everything except the full session works. The CLI, themes, config and individual GUI apps over WSLg are all fine; `startx` is not.

`startx --diagnose` reports what is present and what is missing without starting anything.

To get a render node, build a WSL2 kernel carrying the community [dxgkrnl DRM patches](https://github.com/0deep/wsl-dxgkrnl-drm-patches):

```bash
omarchy dev wsl kernel --output ~/bzImage
```

That builds `microsoft/WSL2-Linux-Kernel` at `linux-msft-wsl-6.6.y` with the patches applied, in Docker, seeding `.config` from the running WSL kernel when there is one. It installs nothing and changes no Windows configuration — it prints the `.wslconfig` snippet to apply by hand:

```ini
[wsl2]
kernel=C:\Users\<you>\bzImage
```

Then, from Windows rather than from inside WSL (it ends every distribution):

```powershell
wsl --shutdown
```

Even with the render node present, Mesa's GBM loader still has to find a DRI driver matching the `dxgkrnl` DRM driver name. That part is unproven; if it does not resolve, `startx --diagnose` is the honest answer and the rest of the image is unaffected.

## Files

| Path | Role |
| --- | --- |
| `bin/omarchy-dev-wsl-build` | Builds the `.wsl` image in Docker |
| `bin/omarchy-dev-wsl-kernel` | Builds a DRM-enabled WSL2 kernel in Docker |
| `bin/omarchy-apply-wsl` | Root-owned system setup inside the image |
| `bin/omarchy-launch-wsl-session` | What `startx` runs |
| `install/wsl/all.sh` | The ordered step list |
| `install/wsl/omarchy-wsl-skip.packages` | Packages subtracted from the base manifest |
| `default/wsl/wsl.conf` | `/etc/wsl.conf` — systemd, interop, resolv.conf generation |
| `default/wsl/wsl-distribution.conf` | `/etc/wsl-distribution.conf` — OOBE, shortcut, terminal profile |
| `default/wsl/oobe.sh` | `/etc/oobe.sh` — first-run account creation |
| `default/wsl/terminal-profile.json` | Windows Terminal profile and colour scheme |

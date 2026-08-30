# Omarchy on WSL

Omarchy can be built into an importable WSL image on top of the official [Arch Linux WSL rootfs](https://gitlab.archlinux.org/archlinux/archlinux-wsl). The image boots to a plain shell — **the desktop never starts on its own** — and `startx` brings the Hyprland session up as a window on the Windows desktop through WSLg.

This is a development and evaluation target, not a supported install path. It exists so a Windows workstation can run this checkout without a VM or a spare machine.

## Building

```bash
omarchy dev wsl build --output ~/omarchy.wsl
```

Everything runs inside Docker, so the command needs no root on the host and cannot touch the host system. It downloads the official rootfs from `https://geo.mirror.pkgbuild.com/wsl/latest/archlinux.wsl` (cached under `$XDG_CACHE_HOME/omarchy/wsl`, verified against the published `.SHA256`), imports it into a scratch Docker image, provisions it, and repacks the result.

The build container is capped at half the machine — half the CPUs and half the memory — so a build does not make the host unusable while it runs. `--help` prints the numbers it resolved for the machine you are on.

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

Added for WSL only: `librsvg` (an SVG delegate for ImageMagick, so the Windows shortcut icon can be rendered from `logo.svg`), `sudo` (the base rootfs ships it, but the image depends on it), and the session's own runtime — `seatd`, `wayvnc` and `tigervnc`, all three explained under [The DRM device](#the-drm-device) and [The window](#the-window).

### Services

`install/wsl/services.sh` is the inverse of `install/config/enable-services.sh`. It sets `multi-user.target` as the default, masks `sddm.service`, enables `seatd.service`, and masks the units Microsoft documents as breaking WSL — including `NetworkManager` and `systemd-resolved`, which are exactly what the hardware path enables. WSL supplies the interface and writes `/etc/resolv.conf` itself.

Every call uses `systemctl --root=/`. The build container has no systemd on the bus, and unlike an `arch-chroot` install systemd cannot tell it is not the real root, so a plain `systemctl mask` there fails with "System has not been booted with systemd". With `--root=` it is a pure file operation, which is all that matters for symlinks that take effect on the next boot.

`sddm` is masked even though the package is not installed. It is the only thing that ever starts the compositor, so a later `pacman -S sddm` must not be able to bring the desktop up at boot behind the user's back.

## Starting the desktop

```bash
startx
```

`install/wsl/wslg.sh` installs `/usr/local/bin/startx` as a small wrapper that execs `omarchy-launch-wsl-session`. There is no X server involved despite the name — `startx` is simply where people reach for a desktop from a WSL shell. `xorg-xinit` is not installed and `/usr/local/bin` precedes `/usr/bin`, so nothing is shadowed.

The launcher points aquamarine at the VKMS device, unsets `WAYLAND_DISPLAY`, and then runs the exact line from `default/wayland-sessions/omarchy.desktop`:

```bash
uwsm start -g -1 -e -D Hyprland hyprland.desktop
```

Going through uwsm is what sources `/usr/share/uwsm/env.d/10-omarchy` (and so sets `OMARCHY_PATH`) and lets `default/hypr/autostart.lua` bring up the shell, first-run provisioning, and the rest.

It starts in the background rather than replacing the launcher, because the session still has to be given somewhere to draw and something to show it in. Once `hyprctl` answers, the launcher creates a headless output, serves it with wayvnc on the loopback, and opens a VNC viewer as an ordinary WSLg client. Closing that window ends the session.

The same environment is installed at `/etc/profile.d/omarchy-wslg.sh` for ordinary shells, so individual GUI apps opened from a prompt find the WSLg sockets too.

### The DRM device

**Hyprland needs a DRM device with a display attached, and stock WSL2 kernels have none.** Aquamarine wants a device it can both allocate GBM buffers on and find a CRTC in. WSL2 exposes Microsoft's `/dev/dxg`, which is not a DRM device at all: on a stock kernel `/dev/dri` does not exist.

So on a stock kernel, everything except the full session works. The CLI, themes, config and individual GUI apps over WSLg are all fine; `startx` is not.

`startx --diagnose` reports what is present and what is missing without starting anything.

The device Omarchy uses is VKMS, the kernel's virtual KMS driver. It is a complete DRM device with no hardware behind it, which is exactly the shape needed here: it supplies the allocator fd and a CRTC, and nothing is ever scanned out of it. To get one, build a WSL2 kernel with it turned on:

```bash
omarchy dev wsl kernel --output ~/bzImage
```

That builds `microsoft/WSL2-Linux-Kernel` at `linux-msft-wsl-6.6.y` in Docker, seeding `.config` from the branch's own `Microsoft/config-wsl` and adding `CONFIG_DRM_VKMS=y`. The seed is deliberately the upstream default rather than the running kernel's `/proc/config.gz`: once the machine boots a kernel this command built, seeding from the running one would be self-referential and any `olddefconfig` drift would compound across rebuilds.

VKMS has to be built in rather than left as a module, which in turn forces `CONFIG_DRM_GEM_SHMEM_HELPER=y` — kconfig will quietly demote a built-in symbol back to a module rather than let it depend on one, so the build asserts both survived. Nothing autoloads modules here anyway; see the `modprobe` note below.

Like the image build the kernel build is capped at half the machine, and `--jobs` defaults to match that cap rather than to `nproc`: `--cpus` is a CFS quota, so a container still *sees* every core and an unmatched `make -j` would oversubscribe the quota it has been given.

The kernel build container is Debian bookworm, the one place in this repo that is deliberately not Arch. Linux 6.6 is from late 2023 and its in-tree `tools/` build compiles with `-Werror`, so a current compiler fails it on warnings that did not exist when the tree was written — Arch's GCC 15 stops at `libbpf.c: assignment discards 'const' qualifier`. Bookworm's GCC 12 is contemporaneous with 6.6. Nothing from that container reaches the image.

The build emits two artifacts: the kernel itself, and a `-modules.tar.gz` beside it. Both are needed. The stock WSL kernel leaves most of itself as modules and ships them inside the distribution image, so replacing only the `bzImage` silently deletes every `=m` feature — the modules on disk belong to a version string that no longer exists. Docker is usually the first casualty, because `CONFIG_BRIDGE` and `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE` are both modules and `dockerd` will not start without them.

The command installs nothing and changes no Windows configuration — it prints the `.wslconfig` snippet to apply by hand:

```ini
[wsl2]
kernel=C:\\Users\\<you>\\bzImage
```

Backslashes are escaped: `.wslconfig` reads the value as an escaped string, so a single-backslash path does not resolve and WSL silently boots its own kernel instead.

The `kernel=` setting is global: every distribution on the machine reboots onto it, not just Omarchy. So unpack the modules into each of them:

```bash
sudo tar -C / -xzf ~/bzImage-modules.tar.gz
```

Unpacking them is necessary but not sufficient. The kernel loads a module on first use by running `/sbin/modprobe`, and under WSL2 that runs in the utility VM's own root rather than the distribution's, where neither `modprobe` nor `/lib/modules` exists — so nothing loads on demand and every module has to be named up front. Docker is again the clearest case: it needs `nft_compat` for the `iptables` nft backend plus `xt_addrtype`, `xt_MASQUERADE`, `xt_conntrack` and `bridge`, and without them `dockerd` fails with `Extension addrtype revision 0 not supported, missing kernel module?` or, from the `DOCKER-CT` chain, `Extension conntrack revision 0 not supported`. Record them so they load at boot:

```bash
printf '%s\n' bridge nft_compat xt_addrtype xt_MASQUERADE xt_conntrack | sudo tee /etc/modules-load.d/wsl-kernel.conf
```

Every build from this command reports the same release string, so a rebuild overwrites the previous build's modules rather than landing beside them. Unpack the tarball on every rebuild: the version magic still matches, so `modprobe` will load a module compiled against a different config without complaint.

Then, from Windows rather than from inside WSL (it ends every distribution):

```powershell
wsl --shutdown
```

**No DRM render node may be present.** Community kernel patches exist that give `dxgkrnl` a DRM driver, and they are actively harmful here: they add a `renderD` node that Mesa has no driver for, aquamarine prefers it over the KMS fd anyway, and then every buffer import against it fails. The desktop draws, but screen capture hangs and window resizes never apply. Omarchy's kernel deliberately does not carry those patches, so `/dev/dri` holds `card0` alone. `/dev/dxg` is a separate char device and is untouched, so WSL's own GPU passthrough is unaffected. `startx --diagnose` calls out a stray `renderD*` for this reason.

Rendering is entirely software. There is no GPU here Mesa can drive, so the launcher sets `LIBGL_ALWAYS_SOFTWARE=1` and `GALLIUM_DRIVER=llvmpipe`; without them EGL dies with `DRI2: failed to load driver`.

`seatd` is how aquamarine opens the device. On hardware that is logind's job, but logind manages seats it finds on a real machine and WSL has none, so `install/wsl/services.sh` enables `seatd.service` and `install/wsl/groups.sh` records the `seat`, `video` and `render` groups for the account the OOBE creates.

### The window

VKMS is the allocator, not the display. Its own output is disabled, and the desktop lives on a headless output the launcher creates at startup:

```bash
hyprctl output create headless
```

The reason is resizing. wayvnc will only resize an output whose name starts with `HEADLESS-`, and VKMS cannot take a custom mode in any case — with no EDID it offers the fixed `drm_add_modes_noedid` list and nothing else. A headless output accepts whatever size the viewer window asks for.

`install/wsl/hypr.sh` is what disables the VKMS output, by appending to `/etc/skel/.config/hypr/monitors.lua`:

```lua
hl.monitor({ output = "Virtual-1", disabled = true })
```

That has to be config rather than a runtime `hyprctl` call: `hyprctl reload` re-enables a monitor that was only disabled at runtime, and Omarchy reloads on every theme change. `/etc/skel` is where `omarchy-settings` ships the file, `useradd -m` copies the tree when the OOBE creates the account, and `omarchy-reinstall-configs` re-applies it — all without touching the tracked `config/hypr/monitors.lua` that `omarchy-update`'s `git pull` would later conflict on.

The session is then served and shown:

```bash
wayvnc -o HEADLESS-1 127.0.0.1 5900
vncviewer -SecurityTypes None -RemoteResize=1 127.0.0.1:5900
```

wayvnc binds the loopback only. WSL2 forwards localhost from Windows, so nothing is gained by binding wider and an unauthenticated desktop would be on the LAN.

The viewer is an ordinary WSLg X11 client, which is what makes this a real window on the Windows desktop and what makes the whole approach work. Nesting Hyprland directly in WSLg's Weston does not: that Weston is 9.0.0 and advertises `wl_compositor` v5 against the v6 aquamarine binds. Plain X11 drawing needs no dmabuf and negotiates no Wayland protocol versions.

Dragging the window edge resizes the desktop to match. The new size is stored immediately but applied on the next frame, so it lands within a second or two while anything is redrawing — the bar clock is enough — and waits for input in a fully static session.

## Files

| Path | Role |
| --- | --- |
| `bin/omarchy-dev-wsl-build` | Builds the `.wsl` image in Docker |
| `bin/omarchy-dev-wsl-kernel` | Builds a VKMS-enabled WSL2 kernel in Docker |
| `bin/omarchy-apply-wsl` | Root-owned system setup inside the image |
| `bin/omarchy-launch-wsl-session` | What `startx` runs: the session, wayvnc, and the viewer |
| `install/wsl/all.sh` | The ordered step list |
| `install/wsl/omarchy-wsl-skip.packages` | Packages subtracted from the base manifest |
| `default/wsl/wsl.conf` | `/etc/wsl.conf` — systemd, interop, resolv.conf generation |
| `default/wsl/wsl-distribution.conf` | `/etc/wsl-distribution.conf` — OOBE, shortcut, terminal profile |
| `default/wsl/oobe.sh` | `/etc/oobe.sh` — first-run account creation |
| `default/wsl/terminal-profile.json` | Windows Terminal profile and colour scheme |

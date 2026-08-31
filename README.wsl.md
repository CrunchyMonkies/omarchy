# Omarchy on WSL

Omarchy builds into an importable WSL image. The CLI, themes and configuration all work the way they do on hardware, and the full Hyprland desktop runs in a window on the Windows desktop.

The desktop never starts on its own. `start-omarchy` is the only way in.

For how any of this works — the DRM device, the session model, the VNC path — see [`docs/wsl.md`](docs/wsl.md). This file is the order to do things in.

## Quickstart

From PowerShell on Windows:

```powershell
irm https://github.com/CrunchyMonkies/omarchy/releases/latest/download/Install-Omarchy.ps1 -OutFile Install-Omarchy.ps1
.\Install-Omarchy.ps1
```

That fetches the image and the kernel from the latest release, verifies both against its `SHA256SUMS`, sets up `.wslconfig`, imports the image and unpacks the modules. The **first launch of the distribution installs Omarchy itself** — it asks for what it needs, then downloads several gigabytes, so give it a network connection and some time. Then `omarchy setup wsl viewer` and `start-omarchy` inside the distribution.

You can build the image yourself instead and pass it with `-ImagePath`; step 2 covers that.

The rest of this file is that in full, plus what to do when a piece of it does not work.

## What you need

- WSL 2 with WSLg (`wsl --version` reports both; if that command is not recognised, run `wsl --install` and `wsl --update`)
- A network connection for the first launch, which is where Omarchy is actually installed
- About 25 GB where the distribution will live
- Docker and about 20 GB more, only if you build the image yourself rather than downloading it

Nothing on the Windows side needs administrator rights.

## 1. Get the kernel

Stock WSL2 kernels expose Microsoft's `/dev/dxg` and no DRM device at all, so Hyprland has nothing to render on. Everything except the desktop works on a stock kernel; `start-omarchy` does not.

**From a release** — `bzImage` and `bzImage-modules.tar.gz` are attached to every [release](https://github.com/CrunchyMonkies/omarchy/releases), and `Install-Omarchy.ps1` fetches them for you. Nothing to do here.

**Or build it**, if you want a different branch or do not trust a binary you did not produce:

```bash
omarchy dev wsl kernel --output ~/bzImage
```

Builds `microsoft/WSL2-Linux-Kernel` with VKMS turned on, in a Debian container, and writes `~/bzImage` and `~/bzImage-modules.tar.gz`. This takes **hours**. The container is capped at half the machine so the host stays usable; `--jobs` and `--branch` override the defaults.

Pass it later with `-KernelPath`.

## 2. Get the image

`omarchy-<tag>.wsl` is attached to every [release](https://github.com/CrunchyMonkies/omarchy/releases), and `Install-Omarchy.ps1` fetches it for you. Nothing to do here.

**Or build it**, to run the code in your checkout:

```bash
omarchy dev wsl build --output ~/omarchy.wsl
```

Builds on top of the official Arch Linux WSL rootfs, overlaying this checkout at `/usr/local/share/omarchy` so the image runs the code you have. Pass `--no-dev-link` to ship the released `/usr/share/omarchy` instead, which is what a release build does.

Takes a few minutes and needs no root on the host — everything happens inside Docker. What it produces is a bootstrap: the setup screen, the metadata Windows reads, and little else. The desktop, the tools and the configuration are installed by the first launch, not baked in. That is what keeps the tarball under GitHub's 2 GiB limit for a release asset; `--assert-max-size` holds it there.

Pass it later with `-ImagePath`.

## 3. Install on Windows

### With the installer

From PowerShell:

```powershell
irm https://github.com/CrunchyMonkies/omarchy/releases/latest/download/Install-Omarchy.ps1 -OutFile Install-Omarchy.ps1
.\Install-Omarchy.ps1
```

Add `-ImagePath C:\Users\<you>\omarchy.wsl` to import an image you built rather than the release's.

| Option | What it does |
| --- | --- |
| `-ImagePath` | the `.wsl` you built — **required**, there is no published image |
| `-KernelPath` | install a locally built `bzImage` instead of the release's |
| `-Tag 202608.31.0` | take the kernel from a specific release instead of the latest |
| `-Name` | the name to register the distribution under (default `Omarchy`) |
| `-Location` | where the distribution is stored (default `%USERPROFILE%\WSL\Omarchy`) |
| `-SkipKernel` | import the image only — the CLI works, `start-omarchy` does not |
| `-Force` | replace an existing distribution, or an existing `kernel=` line |

It verifies the kernel against the release's `SHA256SUMS` and stops before installing anything if that fails. The image is taken on trust, because you built it.

The script lives at [`install/wsl/windows/Install-Omarchy.ps1`](install/wsl/windows/Install-Omarchy.ps1) and is published as a release asset so the URL above always matches the release it takes the kernel from.

### By hand

The same thing, step by step.

**1. Install the kernel.** Copy `bzImage` where Windows can read it, and point `.wslconfig` at it. **The backslashes are escaped** — a single-backslash path does not resolve and WSL quietly boots its own kernel instead, which looks exactly like a kernel that built wrong:

```ini
[wsl2]
kernel=C:\\Users\\<you>\\bzImage
```

Then, from Windows rather than from inside WSL:

```powershell
wsl --shutdown
```

**2. Import the image.**

```powershell
wsl --install --from-file C:\Users\<you>\omarchy.wsl --location C:\Users\<you>\WSL\Omarchy --name Omarchy
```

On first launch Omarchy's setup screen runs: your account name, prefilled from your Windows sign-in, your git identity, and whether to include the preinstalled applications and the AI coding agents. Then it installs — several gigabytes over the network, so it takes a while, behind a progress bar.

If it fails partway, most likely on a network that went away, nothing is lost: the next shell you open offers to pick up where it left off, and `sudo /etc/oobe.sh` does the same on demand. The log is `/var/log/omarchy-install.log`.

**3. Unpack the kernel modules.** The `kernel=` setting is **global**: every distribution on the machine now boots this kernel, and a `bzImage` alone is not a drop-in replacement — the stock WSL kernel keeps most of itself as modules. Unpack them into **every** distribution:

```bash
sudo tar -C / -xzf /mnt/c/Users/<you>/bzImage-modules.tar.gz
printf '%s\n' bridge nft_compat xt_addrtype xt_MASQUERADE xt_conntrack | sudo tee /etc/modules-load.d/wsl-kernel.conf
```

Nothing autoloads modules under WSL, which is why they have to be named up front. Without them Docker will not start.

Every kernel build reports the same release string, so a rebuild overwrites the previous build's modules rather than landing beside them. Unpack the tarball on every rebuild: the version magic still matches, so `modprobe` will load a module compiled against a different config without complaint.

**Checkpoint.** After another `wsl --shutdown`, `/dev/dri` must contain `card0` **and nothing else**. A `renderD*` node means a kernel carrying the community dxgkrnl DRM patches, and buffer imports fail against it. `docker info` should also succeed, which proves the modules loaded.

## 4. Set up the Windows side

```bash
omarchy setup wsl viewer
```

The desktop is served over VNC and shown in a client. Windows ships no VNC client, so this fetches two — TurboVNC and TigerVNC, both pinned by version and SHA256 — into `%LOCALAPPDATA%\Omarchy`, and creates an **Omarchy Desktop** shortcut on your Windows desktop.

TurboVNC is the one the desktop uses, because it is the only one that grabs the keyboard in a window. Without a grab Windows keeps `SUPER` and none of the keybindings reach the session. Its installer is unpacked rather than run, so no VNC *server* is installed on Windows and nothing asks for elevation.

This is the one step the image cannot do for you: it runs in a build container with no Windows to write to.

Without it the desktop still opens, in the viewer inside WSL. That one cannot reach the Windows clipboard and never receives `SUPER`.

## 5. Start the desktop

Double-click **Omarchy Desktop**, or run:

```bash
start-omarchy
```

Closing the window ends the session.

- **Keybindings** work — `SUPER + RETURN` opens a terminal. The viewer grabs the keyboard so `SUPER` reaches the session; **CTRL-ALT-SHIFT-G** toggles that off when you want Windows shortcuts back.
- **Clipboard** works both ways, including UTF-8.
- **Resizing** the window resizes the desktop.
- **The pointer** is drawn by the compositor into the image, so there is exactly one.

## When something is wrong

```bash
start-omarchy --diagnose
```

It reports what the session needs and what this machine has, without starting anything, and names the fix for whichever piece is missing.

## How this differs from Omarchy on hardware

- **No systemd user session.** `user@1000.service` cannot start under WSL — its cgroup is held populated by processes WSL keeps in another PID namespace, so systemd's `clone3(CLONE_INTO_CGROUP)` fails with `EBUSY` forever, on a stock Arch WSL distribution too. `start-omarchy` is therefore the session leader instead of uwsm, and `uwsm-app` is shimmed so applications still launch. One consequence: the six user units under `default/systemd/user/` never start, and first-run provisioning reports that step as failed. All six are optional or hardware-shaped.
- **No idle lock.** A distributable WSL image carries no password hashes, so a lock screen could never be answered. Idle is disabled in the image. `omarchy toggle idle` turns it back on, and here that is a way to lock yourself out.
- **No display manager, Bluetooth, printing, firewall, or power management.** The image drops them; the skip list carries the reasoning inline.
- **Software rendering.** There is no GPU here Mesa can drive.

## What had to be fixed

The four points above are the ones you notice. The list below is the whole of it — every workaround, shim, patch and deliberate omission that stands between a stock Arch WSL rootfs and a working Hyprland desktop, with the file that carries each one. [`docs/wsl.md`](docs/wsl.md) explains the reasoning at length; this is the index.

One rule shapes all of it: **WSL knowledge is quarantined.** It lives in `install/wsl/` and the `*-wsl-*` commands, and `/usr/local/bin` precedes `/usr/bin` so the real binary is shadowed rather than removed — that is what keeps thirty call sites from growing a WSL condition each. Exactly three fixes live outside that boundary, and they are marked **(shared)** below.

### Kernel and DRM

| Fix | Where | Why |
| --- | --- | --- |
| `CONFIG_DRM_VKMS=y`, built in rather than a module | `bin/omarchy-dev-wsl-kernel` | Stock WSL2 kernels expose `/dev/dxg` and no DRM device. It cannot be a module: the kernel runs `/sbin/modprobe` in the utility VM's root, where neither it nor `/lib/modules` exists, so nothing would ever load it |
| `CONFIG_DRM_GEM_SHMEM_HELPER=y` forced alongside it | `bin/omarchy-dev-wsl-kernel` | kconfig drags VKMS back down to a module rather than let a built-in symbol depend on one |
| Assertion on `CONFIG_DRM`, `CONFIG_DXGKRNL`, `CONFIG_DRM_GEM_SHMEM_HELPER`, `CONFIG_DRM_VKMS` after `olddefconfig` | `bin/omarchy-dev-wsl-kernel` | The shmem helper fails silently; an upstream change must not quietly leave the kernel without a usable DRM device |
| `.config` seeded from `Microsoft/config-wsl`, never `/proc/config.gz` | `bin/omarchy-dev-wsl-kernel` | Seeding from the running kernel is self-referential once the machine boots a kernel this script built, and `olddefconfig` drift compounds |
| Built in a Debian bookworm container, not Arch | `bin/omarchy-dev-wsl-kernel` | Linux 6.6's in-tree `tools/` builds with `-Werror`; Arch's GCC 15 stops at `libbpf.c: assignment discards 'const' qualifier`. Bookworm's GCC 12 is contemporaneous with 6.6 |
| Modules shipped beside the `bzImage`, and five named in `/etc/modules-load.d/wsl-kernel.conf` | `bin/omarchy-dev-wsl-kernel` | The stock kernel keeps most of itself as modules, so a `bzImage` alone silently drops every `=m` option. `dockerd` notices first: it needs `bridge` and `xt_addrtype` |
| Container capped at half the machine, `--jobs` defaulting to the cap | `bin/omarchy-dev-wsl-kernel` | `--cpus` is a CFS quota, so a container still *sees* every core and an unmatched `make -j` oversubscribes the quota it was given |
| Backslashes doubled in every `.wslconfig` path printed | `bin/omarchy-dev-wsl-kernel` | `.wslconfig` reads `kernel=` as an escaped string; a single-backslash path silently boots the stock kernel |
| No community dxgkrnl DRM patches, and a detector for a stray render node | `bin/omarchy-launch-wsl-session` | Those patches add a `renderD` node Mesa has no driver for; aquamarine prefers it over the KMS fd and every buffer import fails. The desktop draws, but capture hangs and resizes never apply |
| KMS detection requires a connector entry (`card0-Virtual-1`), not just a card node | `bin/omarchy-launch-wsl-session` | dxgkrnl registers a render-only node with nothing to scan out to, which aquamarine rejects with "does not support kms" |
| `AQ_DRM_DEVICES` and `AQ_NO_MODIFIERS=1` exported | `bin/omarchy-launch-wsl-session` | Points aquamarine at the VKMS node rather than leaving it to probe |
| `LIBGL_ALWAYS_SOFTWARE=1`, `GALLIUM_DRIVER=llvmpipe` | `bin/omarchy-launch-wsl-session` | There is no GPU Mesa can drive; without being told so EGL dies with `DRI2: failed to load driver` |
| `seatd` installed and enabled in place of logind | `install/wsl/packages.sh`, `install/wsl/services.sh` | Hyprland reaches the device through libseat. logind manages seats it finds on a real machine, and WSL has none |
| `seat`, `video` and `render` recorded for the deferred first-boot account | `install/wsl/groups.sh` | The image creates its user at first boot, so the groups have to be recorded rather than granted |
| `start-omarchy --diagnose` | `bin/omarchy-launch-wsl-session` | On a stock kernel everything *except* the session works, so the failure needs explaining rather than reporting |

### Session and systemd

`systemd --user` cannot run here at all. `user@1000.service` fails with `Failed to spawn executor: Device or resource busy` every time, because its leftover cgroup children list PID 0 — processes in a PID namespace WSL holds open, which cannot be reaped — and `clone3(CLONE_INTO_CGROUP)` returns `EBUSY` against a populated cgroup. A stock Arch WSL distribution fails identically. Everything in this section follows from that.

| Fix | Where | Why |
| --- | --- | --- |
| `start-omarchy` shimmed into `/usr/local/bin` to run `omarchy-launch-wsl-session` | `install/wsl/wslg.sh` | `start-omarchy` is what people reach for, there is no X server to start, and uwsm cannot be the session leader |
| `uwsm-app` shimmed to run the command under `setsid --fork` | `install/wsl/uwsm.sh` | Omarchy launches everything through `uwsm-app`, which asks `wayland-wm-app-daemon.service` for a scope. Without the shim the desktop starts and can launch nothing |
| `uwsm stop` translated to `hyprctl dispatch 'hl.dsp.exit()'` | `install/wsl/uwsm.sh` | The Lua config wants the dispatcher form; plain `hyprctl dispatch exit` is a syntax error under it, returns 7, and leaves the session running |
| `systemd-run --user` shimmed, `--user` only | `install/wsl/systemd-run.sh` | Five commands schedule through it and fail before starting anything. `omarchy-launch-browser` passes `StandardError=null`, so the browser simply never appeared. The system manager works and must not be intercepted |
| `--on-active` spans translated to a `sleep`, not discarded | `install/wsl/systemd-run.sh` | Three of the five callers are timers. Collapsing them would reboot the machine out from under the command that asked and fire every reminder at once |
| Compositor started as `env -u DISPLAY XDG_SESSION_TYPE=wayland dbus-run-session -- start-hyprland` | `bin/omarchy-launch-wsl-session` | `dbus-run-session` replaces the user manager's `dbus.socket`; `start-hyprland` is Hyprland's own watchdog launcher |
| Session environment sourced by the launcher | `bin/omarchy-launch-wsl-session` | uwsm reads `/usr/share/uwsm/env.d/10-omarchy`, which is where `OMARCHY_PATH`, `TERMINAL` and `EDITOR` come from. `wsl -d Omarchy start-omarchy` is not a login shell |
| `dbus-update-activation-environment` run without `--systemd` | `bin/omarchy-launch-wsl-session` | `autostart.lua` runs it with `--systemd`, which fails here — and then the portal backends activate with no `WAYLAND_DISPLAY` and cannot reach the compositor |
| Compositor socket found by diffing `wayland-N` before and after start | `bin/omarchy-launch-wsl-session` | `autostart.lua` publishes it into the user manager, and wayvnc needs it. WSLg's own `wayland-0` is already there |
| `HYPRLAND_INSTANCE_SIGNATURE` recovered from the newest `$XDG_RUNTIME_DIR/hypr/*` | `bin/omarchy-launch-wsl-session` | Only the compositor and its children have it, and this command is its parent |
| `WAYLAND_DISPLAY` unset before start | `bin/omarchy-launch-wsl-session` | aquamarine picks its nested Wayland backend whenever it sees one, and WSLg's Weston is 9.0.0 — `wl_compositor` v5 against v6 binds |
| Teardown through the Lua dispatcher with a 10 s watchdog, and a refusal to start a second session | `bin/omarchy-launch-wsl-session` | One VNC port, one headless output |
| `systemctl --root=/` for every call | `install/wsl/services.sh` | The build container has no systemd on the bus, and unlike an `arch-chroot` install systemd cannot tell it is not the real root |
| `multi-user.target` as default | `install/wsl/services.sh` | WSL boots to the user's shell; nothing may pull in a graphical target |
| `sddm.service` masked although sddm is not installed | `install/wsl/services.sh` | It is the only thing that ever starts the compositor, and a later `pacman -S sddm` must not bring the desktop up at boot |
| Eleven units masked: `systemd-resolved`, `systemd-networkd`(+socket), `NetworkManager`(+`-wait-online`), four `systemd-tmpfiles-*`, `tmp.mount` | `install/wsl/services.sh` | Microsoft documents these as breaking WSL. NetworkManager and resolved are exactly what the hardware path enables; WSL supplies the interface and `/etc/resolv.conf` itself |
| Nine `omarchy-apply-system` steps skipped, via a parallel step list | `bin/omarchy-apply-wsl`, `install/wsl/all.sh` | Those steps assume hardware WSL does not have, and there is no skip mechanism under `install/` |
| **(shared)** first-run user units skip themselves when no user manager is running | `install/user/first-run/enable-user-units.sh` | Completion is recorded only when every step succeeds, so one failure replayed the whole first-run sequence — welcome notification included — on every login |
| **(shared)** the Wi-Fi prompt checks for a wireless interface first | `install/user/first-run/wifi.sh` | It appeared on every login, after up to a minute in `nm-online` waiting for a daemon that is masked |
| `systemd=true` in `/etc/wsl.conf` | `default/wsl/wsl.conf` | uwsm, the user units and every masked unit assume PID 1 is systemd |

### Display and VNC

| Fix | Where | Why |
| --- | --- | --- |
| The VKMS output `Virtual-1` disabled from config, not at runtime | `install/wsl/hypr.sh` | `hyprctl reload` re-enables a monitor disabled at runtime, and Omarchy reloads on every theme change. Written to `/etc/skel` so `omarchy-update`'s `git pull` has nothing to conflict on |
| A headless output created at startup and used as the desktop | `bin/omarchy-launch-wsl-session` | wayvnc refuses to resize any output not named `HEADLESS-*`, and VKMS has no EDID so it offers only the fixed `drm_add_modes_noedid` list |
| **A patched neatvnc**, announcing `ExtendedDesktopSize` as soon as the client's encodings are known | `install/wsl/patches/neatvnc-announce-desktop-size.patch`, `install/wsl/neatvnc.sh` | A client learns the server can resize only by receiving that rect. Stock neatvnc sends it too late, and TurboVNC decides at its first framebuffer update and never revisits — logging `Disabling automatic desktop resizing because the server doesn't support it` |
| The Arch PKGBUILD rewritten in place: `pkgrel` bumped, `source`, `b2sums` and `prepare()` extended | `install/wsl/neatvnc.sh` | A bumped `pkgrel` stops a plain `-Syu` silently dropping the patch. Applying it in `prepare()` means a silently unpatched neatvnc cannot reach the image |
| The version tag read from `pacman -Si`, not from what is installed | `install/wsl/neatvnc.sh` | After one run the installed version carries our own `pkgrel` and names no upstream tag |
| wayvnc bound to `127.0.0.1:5900` with `--name=Omarchy` | `bin/omarchy-launch-wsl-session` | WSL2 forwards localhost, so binding wider only puts an unauthenticated desktop on the LAN. Without `--name` the window is titled "WayVNC" |
| The RFB desktop name retitled to follow focus, throttled to 1 s | `bin/omarchy-hyprland-vnc-title-watch` **(shared)** | The name is otherwise fixed for the session, leaving one window standing in for the whole desktop unable to say what is in it. neatvnc spends a pending framebuffer request on each update, so chasing every event costs about 40% of throughput |
| The compositor's cursor turned off, via `hyprctl eval` | `bin/omarchy-launch-wsl-session` | A headless output has no cursor plane, so Hyprland composites the pointer into the frame wayvnc captures — and wayvnc forwards a cursor too, so the viewer shows two. `hyprctl keyword` does not work against the Lua config |
| TurboVNC preferred, then TigerVNC on Windows, then the viewer inside WSL | `bin/omarchy-launch-wsl-session` | TurboVNC is the only one that grabs the keyboard in a window ([TigerVNC #1899](https://github.com/TigerVNC/tigervnc/issues/1899)); the in-WSL one cannot reach the Windows clipboard |
| TurboVNC started through `javaw.exe` with `-Djava.library.path=` at its own `java/` directory | `bin/omarchy-launch-wsl-session` | What `vncviewer.bat` does, minus the console window. The helper DLL is what implements the grab |
| The address written `127.0.0.1::5900` | `bin/omarchy-launch-wsl-session` | A single colon means a display number, so `127.0.0.1:5900` would be port 11800 |
| `-Scale 100` pinned | `bin/omarchy-launch-wsl-session` | The viewer persists parameters between runs, and any automatic scaling silently disables desktop resizing |
| `-noToolbar` rather than `-Toolbar 0`, and clipboard parameters left at their defaults | `bin/omarchy-launch-wsl-session` | Booleans take no value — `-Toolbar 0` prints usage and exits — and `-RecvClipboard 1` makes the viewer read the `1` as a hostname |
| `SetDesktopSize failed: 4` documented as a false alarm | `bin/omarchy-launch-wsl-session` | Result 4 is neatvnc's "request forwarded", not a refusal |
| TurboVNC, TigerVNC and innoextract pinned by version and SHA256 | `bin/omarchy-setup-wsl-viewer` | Neither publisher signs the download, so pinning is the only integrity check available |
| TurboVNC's Inno Setup installer unpacked rather than run, with a forked innoextract | `bin/omarchy-setup-wsl-viewer` | Running it would install a VNC *server* on Windows and ask for elevation. The Arch innoextract (1.9) cannot read Inno Setup 6.x |
| Leftover UltraVNC files removed | `bin/omarchy-setup-wsl-viewer` | It was tried before TurboVNC, cannot resize the remote desktop, and is not coming back |
| The shortcut targets `wslg.exe -d <distro> --cd ~ -- bash -lc start-omarchy`, and refuses to guess the distribution name | `bin/omarchy-setup-wsl-viewer` | `wslg.exe` launches without a console window. `defaultName` is the name the image *asked* for, not necessarily the one it got |
| The Windows icon rendered from `logo.svg` at 256 down to 16, largest first | `install/wsl/image.sh` | So the large Start menu tiles are not upscaled from a smaller frame. Needs the `librsvg` addition |

### Input, keyboard and clipboard

| Fix | Where | Why |
| --- | --- | --- |
| `resolve_binds_by_sym = true` appended to `/etc/skel/.config/hypr/input.lua` | `install/wsl/hypr.sh` | Hyprland matches keybindings by keycode. The only keyboard here is wayvnc's virtual one, which carries its own keymap, so no binding fires — while typed text still arrives, making it look like the bindings are broken rather than the matching |
| `-noServerKeyMap` passed to TurboVNC | `bin/omarchy-launch-wsl-session` | On the scan-code path the right `SUPER` loses its extended bit: `E0 5C` becomes `0x5C`, which is `KEY_KPJPCOMMA`, arriving with `NoSymbol` and setting no modifier ([TurboVNC #494](https://github.com/TurboVNC/turbovnc/issues/494)) |
| `-GrabKeyboard Always`, and the `CTRL-ALT-SHIFT-G` hint printed at launch | `bin/omarchy-launch-wsl-session` | Windows keeps `SUPER` unless the viewer grabs the keyboard, and you need a way to get Windows shortcuts back |
| A Windows-native viewer preferred, and TigerVNC's clipboard options named explicitly | `bin/omarchy-launch-wsl-session` | wayvnc carries the selection both ways and neatvnc's extended clipboard is what carries UTF-8 — plain RFB cut text is latin-1 — but a viewer inside WSL bridges that to Xwayland's selection, not to Windows |

### Audio

| Fix | Where | Why |
| --- | --- | --- |
| `PULSE_SERVER` pointed at `unix:/mnt/wslg/PulseServer` | `install/wsl/wslg.sh` | Sound leaves the machine through WSLg's PulseAudio RDP sink |
| `alsa-plugins` installed and `/etc/asound.conf` routing the default device to pulse | `install/wsl/audio.sh`, `install/wsl/packages.sh` | `/dev/snd` carries a timer and no card, so every ALSA application fails with `cannot find card '0'` — quietly. On hardware `pipewire-alsa` bridges this, but PipeWire's user services cannot run without a user manager |
| `start-omarchy --diagnose` reports the PulseAudio socket | `bin/omarchy-launch-wsl-session` | WSLg only tries at distribution start, and when it fails there is no second path to fall back to |

### Environment and locale

| Fix | Where | Why |
| --- | --- | --- |
| `/etc/profile.d/omarchy-wslg.sh` exporting `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `DISPLAY`, `PULSE_SERVER` | `install/wsl/wslg.sh` | WSLg publishes its sockets under `/mnt/wslg`, but Windows injects the matching environment only into the shell it starts itself |
| `DISPLAY` unset for the compositor specifically, and `XDG_SESSION_TYPE=wayland` forced | `bin/omarchy-launch-wsl-session` | Inside the session `:0` is a *foreign* display whose windows appear on the Windows desktop. Electron tries X11 whenever `DISPLAY` is set and `XDG_SESSION_TYPE` is not `wayland` — VS Code ran as six processes with no window |
| `en_US.UTF-8` generated, and an ungenerated `LANG` refused rather than passed on | `install/wsl/locale.sh`, `bin/omarchy-launch-wsl-session` | The image ships `/etc/locale.gen` entirely commented out, and WSL's `/init` hands the Windows locale straight to the session. `setlocale()` then fails in everything it launches |
| `DONT_PROMPT_WSL_INSTALL=1` in `/etc/profile.d` | `install/wsl/vscode.sh` | VS Code's launcher greps `/proc/version` for `Microsoft`, matches, and blocks on `read -r YN`. That breaks installing (stderr discarded) and launching (empty stdin read as "no") alike |
| `[interop] enabled`, `appendWindowsPath` in `/etc/wsl.conf` | `default/wsl/wsl.conf` | Every `cmd.exe`, `powershell.exe` and `javaw.exe` call above depends on it |

### Packages

`install/wsl/packages.sh` subtracts `install/wsl/omarchy-wsl-skip.packages` from `install/omarchy-base.packages`. It is a skip list rather than a second manifest, so a package added to the base list reaches WSL without a second edit, and `test/shell.d/wsl-image-test.sh` holds every skip entry to a package that actually exists.

| Dropped | Why |
| --- | --- |
| `sddm`, `plymouth` | The display manager is the only thing that ever starts the compositor, and there is no bootloader to splash |
| `bluez`, `bluez-tools`, `bluez-utils` | No Bluetooth controller is passed through to the WSL VM |
| `cups*`, `system-config-printer`, `avahi`, `nss-mdns` | Printing and mDNS belong to Windows on this machine |
| `ufw`, `ufw-docker` | WSL networking is NAT'd by the host, so a guest firewall filters nothing |
| `docker`, `docker-buildx`, `docker-compose`, `lazydocker` | Docker Desktop already integrates with WSL and a second daemon would fight it |
| `power-profiles-daemon`, `brightnessctl`, `ddcutil`, `asdcontrol`, `bolt` | No battery, ACPI profile, backlight, DDC/CI or Thunderbolt |
| `kernel-modules-hook`, `wireless-regdb` | The kernel comes from Windows, and the regulatory database applies to radios WSL does not expose |
| `tzupdate` | WSL syncs the clock with the Windows host |

| `qemu-user-static-binfmt` | Foreign-architecture emulation for a machine that runs one architecture, and the largest package in the manifest |
| `plocate` | Both the `locate` config step and the `updatedb` run are skipped, so no database is ever built |
| `man-db` | `install/wsl/pacman-noextract.sh` keeps the man pages out, so there is nothing to index. `tldr` stays |

Subtracting a name only declines to ask for it. `sddm`, `plymouth`, `avahi` and `wireplumber` arrive anyway, because the `omarchy` and `omarchy-settings` packages depend on them and the image cannot skip those two — they ship the files at fixed system paths that `OMARCHY_PATH` does not cover. That is why `install/wsl/services.sh` masks `sddm.service`: the mask, not the skip list, is what keeps the desktop from starting on its own.

Added for WSL only: `sudo` (absent from the Arch WSL rootfs), `seatd`, `wayvnc`, `tigervnc` and `alsa-plugins`.

`install/wsl/omarchy-wsl-defer.packages` is a fourth list and a conditional one: the applications the setup screen offers to skip, subtracted only when it is told to. It has to stay identical to the list `omarchy-install-preinstalls` restores, or the way back is partial.

`install/wsl/omarchy-wsl-bootstrap.packages` is a third list, and a much shorter one: `sudo`, `gum` and `ttfx`, the only packages the image carries before the first run installs everything else. `install/wsl/image.sh` and `install/wsl/neatvnc.sh` each need a toolchain for one step — ImageMagick for the shortcut icon, `base-devel` for the neatvnc build — and `install/helpers/transient-packages.sh` takes both back out afterwards, along with everything they dragged in.

### What a distributable image may contain

| Fix | Where | Why |
| --- | --- | --- |
| No password hashes in `/etc/shadow`, asserted before packing, with passwordless sudo for `wheel` | `install/wsl/image.sh`, `bin/omarchy-dev-wsl-build` | Microsoft requires it, and WSL authenticates through Windows rather than PAM. Without the drop-in the first `sudo` in a fresh install would be unanswerable |
| Idle locking disabled by seeding `stay-awake` in `/etc/skel` | `install/wsl/idle.sh` | With no password the lock screen can never be answered, and `omarchy-restart-shell` does not rescue it — `allow_session_lock_restore` lets the fresh shell re-acquire the lock |
| `.dockerenv`, `etc/resolv.conf`, `etc/hosts` and `etc/hostname` deleted from the archive | `bin/omarchy-dev-wsl-build` | Docker synthesizes all four in every container, and Microsoft's spec requires the archive carry no `resolv.conf` |
| `/etc/machine-id` truncated; pacman cache, sync database, journal, logs and root history cleared | `bin/omarchy-dev-wsl-build` | Otherwise every import shares the build container's machine id |
| Packed with gzip, never zstd | `bin/omarchy-dev-wsl-build` | WSL1 unpacks images with a bsdtar that cannot read zstd, which is why Microsoft rejected zstd for the official Arch image |
| `generateResolvConf` on, paired with the masked `systemd-resolved` | `default/wsl/wsl.conf` | So the two cannot fight over the file |
| No `[user] default`; `[oobe] defaultUid = 1000` and `defaultName = Omarchy` instead | `default/wsl/wsl.conf`, `default/wsl/wsl-distribution.conf` | A pinned name would be wrong for anyone who picks a different one, and `wsl --install --from-file` needs a name to register under |
| `/etc/oobe.sh` always exits 0 | `default/wsl/oobe.sh` | WSL refuses to open a shell at all on a non-zero exit, leaving no way in to fix anything |
| The setup screen offered by `/etc/oobe.sh` and never depended on | `default/wsl/oobe.sh`, `bin/omarchy-provision-wsl-owner` | A terminal it cannot draw on, a missing gum or a bug in it must still leave an account behind, so the plain path stays as the fallback |
| No password, hostname, timezone or keyboard layout asked for | `bin/omarchy-provision-wsl-owner` | WSL owns all four. The layout in particular is applied by Windows before the keysym reaches the session, so asking again would apply a second one |
| The desktop installed by `/etc/oobe.sh` rather than baked in | `install/wsl/all-image.sh`, `install/wsl/all-setup.sh` | Baking it in put the tarball past 5 GB gzipped, more than a GitHub release asset may be. The image carries the setup screen; the first launch downloads the rest |
| Setup resumed from `/etc/profile.d/omarchy-wsl-setup.sh` when `provisioning/pending` survives | `install/wsl/image.sh`, `default/wsl/setup-resume.sh` | WSL runs the OOBE command exactly once, and it has to exit 0 either way, so a first run that lost the network needs some other way back |
| Man pages, texinfo, `/usr/share/doc` and every locale but `en_US` excluded through `NoExtract` | `install/wsl/pacman-noextract.sh` | Nothing else strips them, and a later `pacman -Syu` would put them back. Applied twice, because `install/post-install/pacman.sh` restores the shipped `pacman.conf` over them |
| The UNIX name derived from the Windows one by conservative mapping only, otherwise prompting | `default/wsl/oobe.sh` | Windows allows names `useradd` will not. Silently stripping letters would name the account something the user never chose |
| Re-entrancy guarded on the pending marker rather than uid 1000, and the `docker` group refused at first run | `default/wsl/oobe.sh` | WSL re-runs the OOBE after some upgrades. The marker rather than the account, so a run that failed after creating it still resumes; `docker` is root-equivalent |
| A Windows Terminal profile shipped to `/usr/lib/wsl/terminal-profile.json` | `default/wsl/terminal-profile.json`, `install/wsl/image.sh` | Windows Terminal is the front end, and `[windowsterminal] ProfileTemplate` in `wsl-distribution.conf` points at it. Written before that file, so the icon it names already exists |

### Building in a container

| Fix | Where | Why |
| --- | --- | --- |
| `DisableSandboxFilesystem` inserted into `[options]` and reverted before packing, with an assertion that it did not leak | `bin/omarchy-dev-wsl-build` | pacman confines its downloads with Landlock and Docker's seccomp profile refuses those syscalls, so every transaction dies at "the Landlock ruleset could not be applied". It goes into `[options]`, not appended, where it would belong to the last repository and be ignored |
| The pacman keyring rebuilt with `pacman-key --init` and `--populate` | `bin/omarchy-dev-wsl-build` | The official Arch WSL rootfs deletes its keyring on purpose and rebuilds it in the OOBE hook this image replaces |
| The Omarchy signing key received and locally signed by hand | `bin/omarchy-dev-wsl-build` | `omarchy-update-keyring` cannot run yet, because the `omarchy` package is not installed |
| `omarchy` and `omarchy-settings` installed even when overlaying a checkout | `bin/omarchy-dev-wsl-build` | They ship files at fixed system paths — `/etc/skel`, systemd units, `/usr/share/uwsm/env.d` — that `OMARCHY_PATH` does not cover |
| The dev-link `secure_path` drop-in written after `omarchy-apply-wsl` | `bin/omarchy-dev-wsl-build` | The base rootfs carries no sudo, so `visudo` does not exist until `install/wsl/bootstrap.sh` has run |
| `omarchy-apply-wsl` run with no `--install-user` | `bin/omarchy-apply-wsl` | The image is provisioned without an account, the way a deferred-provisioning ISO install is, because the name belongs to whoever imports it |
| `makepkg` run as a throwaway `omarchy-build` account | `install/wsl/neatvnc.sh` | It refuses to run as root, and provisioning is root |

## Releasing

Tags are calendar versions, `YYYYMM.DD.N`:

```bash
git tag "$(date -u +%Y%m.%d.0)"
git push origin "$(date -u +%Y%m.%d.0)"
```

Pushing one runs [`.github/workflows/release.yml`](.github/workflows/release.yml), which runs the test suites, builds the image, and publishes it alongside the installer, a source tarball and a `SHA256SUMS`. Run it with `workflow_dispatch` and `dry_run` to build everything into a workflow artifact without publishing anything.

The image build passes `--assert-max-size 2147483648`, GitHub's limit for one release asset. If something that belongs to the setup phase starts being baked into the image, the workflow fails there rather than at the upload.

The kernel is published, since it is small and takes hours to build. [`.github/workflows/wsl-kernel.yml`](.github/workflows/wsl-kernel.yml) builds it and attaches `bzImage` and `bzImage-modules.tar.gz` to a release that already exists, merging them into that release's `SHA256SUMS`. Run it by hand; it only needs rerunning when the WSL2 kernel branch moves.

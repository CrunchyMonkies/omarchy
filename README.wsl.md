# Omarchy on WSL

Omarchy builds into an importable WSL image. The CLI, themes and configuration all work the way they do on hardware, and the full Hyprland desktop runs in a window on the Windows desktop.

The desktop never starts on its own. `startx` is the only way in.

For how any of this works — the DRM device, the session model, the VNC path — see [`docs/wsl.md`](docs/wsl.md). This file is the order to do things in.

## What you need

- WSL 2 with WSLg (`wsl --version`)
- Docker on the machine you build from, for both the kernel and the image
- About 50 GB free while building

## 1. Build a kernel

Stock WSL2 kernels expose Microsoft's `/dev/dxg` and no DRM device at all, so Hyprland has nothing to render on. Everything except the desktop works on a stock kernel; `startx` does not.

```bash
omarchy dev wsl kernel --output ~/bzImage
```

That builds `microsoft/WSL2-Linux-Kernel` with VKMS turned on. It takes a while and prints what to do next when it finishes.

Copy the kernel where Windows can read it, and point `.wslconfig` at it. **The backslashes are escaped** — a single-backslash path does not resolve and WSL quietly boots its own kernel instead, which looks exactly like a kernel that built wrong:

```ini
[wsl2]
kernel=C:\\Users\\<you>\\bzImage
```

Unpack the modules into **every** distribution on the machine, because `kernel=` is global:

```bash
sudo tar -C / -xzf ~/bzImage-modules.tar.gz
printf '%s\n' bridge nft_compat xt_addrtype xt_MASQUERADE xt_conntrack | sudo tee /etc/modules-load.d/wsl-kernel.conf
```

Nothing autoloads modules under WSL, which is why they have to be named up front. Without them Docker will not start.

Then, from Windows rather than from inside WSL:

```powershell
wsl --shutdown
```

Confirm it took: `/dev/dri` must contain `card0` **and nothing else**. A `renderD*` node means a kernel carrying the community dxgkrnl DRM patches, and buffer imports fail against it.

## 2. Build and import the image

```bash
omarchy dev wsl build --output ~/omarchy.wsl
```

Copy the `.wsl` somewhere Windows can read, then from Windows:

```powershell
wsl --install --from-file C:\Users\<you>\omarchy.wsl --location C:\Users\<you>\WSL\Omarchy --name Omarchy
```

On first launch the OOBE creates your account, named after your Windows sign-in, and finishes provisioning. There is nothing to answer unless your Windows name contains characters a UNIX name cannot.

## 3. Set up the Windows side

```bash
omarchy setup wsl viewer
```

The desktop is served over VNC and shown in a client. Windows ships no VNC client, so this fetches TigerVNC's standalone viewer — pinned version, pinned SHA256 — into `%LOCALAPPDATA%\Omarchy`, and creates an **Omarchy Desktop** shortcut on your Windows desktop.

This is the one step the image cannot do for you: it runs in a build container with no Windows to write to.

Without it the desktop still opens, in the viewer inside WSL. That one cannot reach the Windows clipboard.

## 4. Start the desktop

Double-click **Omarchy Desktop**, or run:

```bash
startx
```

Closing the window ends the session.

- **Clipboard** works both ways, including UTF-8.
- **Resizing** the window resizes the desktop. The viewer logs `SetDesktopSize failed: 4` when it does; that is misleading — result 4 means *request forwarded*, and the resize is applied.
- **The pointer** is drawn by the viewer, so it does not lag.

## When something is wrong

```bash
startx --diagnose
```

It reports what the session needs and what this machine has, without starting anything, and names the fix for whichever piece is missing.

## How this differs from Omarchy on hardware

- **No systemd user session.** `user@1000.service` cannot start under WSL — its cgroup is held populated by processes WSL keeps in another PID namespace, so systemd's `clone3(CLONE_INTO_CGROUP)` fails with `EBUSY` forever, on a stock Arch WSL distribution too. `startx` is therefore the session leader instead of uwsm, and `uwsm-app` is shimmed so applications still launch. One consequence: the six user units under `default/systemd/user/` never start, and first-run provisioning reports that step as failed. All six are optional or hardware-shaped.
- **No idle lock.** A distributable WSL image carries no password hashes, so a lock screen could never be answered. Idle is disabled in the image. `omarchy toggle idle` turns it back on, and here that is a way to lock yourself out.
- **No display manager, Bluetooth, printing, firewall, or power management.** The image drops them; the skip list carries the reasoning inline.
- **Software rendering.** There is no GPU here Mesa can drive.

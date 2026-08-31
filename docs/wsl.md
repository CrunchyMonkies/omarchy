# Omarchy on WSL

This is how the WSL image works. For the order to do things in — build a kernel, import, set up the Windows side, start the desktop — see [`README.wsl.md`](../README.wsl.md).

Omarchy can be built into an importable WSL image on top of the official [Arch Linux WSL rootfs](https://gitlab.archlinux.org/archlinux/archlinux-wsl). The image boots to a plain shell — **the desktop never starts on its own** — and `start-omarchy` brings the Hyprland session up as a window on the Windows desktop through WSLg.

This is a development and evaluation target, not a supported install path. It exists so a Windows workstation can run this checkout without a VM or a spare machine.

## Building

Releases carry a built image, so this is for running the code in your checkout rather than the released one. `README.wsl.md` covers the whole path. `.github/workflows/wsl-kernel.yml` builds the kernel separately, because that takes hours and only changes when the WSL2 kernel branch moves.

```bash
omarchy dev wsl build --output ~/omarchy.wsl
```

Everything runs inside Docker, so the command needs no root on the host and cannot touch the host system. It downloads the official rootfs from `https://geo.mirror.pkgbuild.com/wsl/latest/archlinux.wsl` (cached under `$XDG_CACHE_HOME/omarchy/wsl`, verified against the published `.SHA256`), imports it into a scratch Docker image, provisions it, and repacks the result.

The build container is capped at half the machine — half the CPUs and half the memory — so a build does not make the host unusable while it runs. `--help` prints the numbers it resolved for the machine you are on.

By default the checkout is copied to `/usr/local/share/omarchy` and `/etc/omarchy.conf` points `OMARCHY_PATH` at it — the same overlay `omarchy-dev-link` sets up, so the image runs the code you are editing. `--no-dev-link` leaves the released `/usr/share/omarchy` in place instead.

The released `omarchy` and `omarchy-settings` packages are installed either way. They ship the files at fixed system paths that `OMARCHY_PATH` does not cover: `/etc/skel`, the systemd units, `/usr/share/uwsm/env.d/10-omarchy`.

The output is a gzip tar of the root filesystem, with the root of the archive at the root of the filesystem. Gzip is mandatory, not a preference: WSL1 unpacks images with a bsdtar that cannot read zstd, which is why Microsoft rejected zstd for the official Arch image.

`--assert-max-size` fails the build when the packed image is larger than a given number of bytes. The release workflow passes 2 GiB, GitHub's limit for a single release asset, so a step that starts baking the desktop back into the image fails there rather than at the upload.

### Two phases

The image used to carry the whole desktop, and gzipped to around 5 GB — more than twice what a release asset may be, which is why the image was not published at all for a while. So the install is split, and `bin/omarchy-apply-wsl` selects a phase:

| Phase | Runs | List | Does |
| --- | --- | --- | --- |
| `--image` | `omarchy dev wsl build`, in the container | `install/wsl/all-image.sh` | `NoExtract` directives, the bootstrap packages, the locale, and the metadata Windows reads at import time |
| `--setup` | `/etc/oobe.sh`, on the machine that imported the image | `install/wsl/all-setup.sh` | Syncing the package databases, then everything else: the package set, the neatvnc build, and every configuration step |

With neither flag both run in order, which is what an in-place re-apply on an installed machine wants; `install/wsl/all.sh` is that pair.

Every step in `install/wsl/` was already idempotent — `install/wsl/hypr.sh` and `install/wsl/groups.sh` check before appending, `install/wsl/idle.sh` and `install/wsl/services.sh` write the same thing every time — so the split needed no change to any of them, and a setup phase that fails halfway can simply be run again. That matters, because the phase runs over the network on a machine Omarchy does not control.

The setup phase begins with `install/wsl/pacman-sync.sh`, which is not optional. The image ships with `/var/lib/pacman/sync` emptied — an index is stale the moment the tarball is downloaded — so until it has synced, every name in `install/wsl/packages.sh` resolves to `error: target not found` and the install fails at its first step. It refreshes the keyring first, because an image months old carries an `archlinux-keyring` that may predate a maintainer key rotation, and then upgrades what the image already carries: installing current packages alongside build-time ones is the partial upgrade Arch warns about, and an image is the one case where that is guaranteed rather than hypothetical.

`install/wsl/image.sh` writes `/var/lib/omarchy/provisioning/pending`, the same marker `install/provisioning/omarchy-provision-owner.service` gates on for a deferred-provisioning install on hardware, and `/etc/oobe.sh` clears it only when both the setup phase and `omarchy-provision-user` succeeded. While it is there, `/etc/profile.d/omarchy-wsl-setup.sh` offers to finish setup on the next interactive login — WSL runs the OOBE command exactly once, and it must exit 0 whatever happened, so without that a first run interrupted by a network drop would need the image re-imported.

## Importing

```powershell
wsl --install --from-file C:\path\to\omarchy.wsl
```

Or, to control the install location:

```powershell
wsl --import Omarchy C:\wsl\omarchy C:\path\to\omarchy.wsl
```

On first run `/etc/oobe.sh` hands off to `bin/omarchy-provision-wsl-owner` — the setup screen, below — which asks its questions, installs Omarchy, creates the account at uid 1000 and runs `omarchy-provision-user --first-install` as that user. `[oobe] defaultUid = 1000` in `/etc/wsl-distribution.conf` is what makes WSL log in as that account from then on, so `/etc/wsl.conf` deliberately carries no `[user] default` — a name pinned at build time would be wrong for everyone who picks a different one.

`/etc/oobe.sh` names `OMARCHY_SETUP_CONTEXT` when it runs `omarchy-provision-user`. Without it that command assumes an ISO chroot, and `install/user/mise-work.sh` then looks for a bundled Node tarball under `/opt/packages` — a path only the ISO has — and fails the whole finalization. Naming any other context sends it to the network for Node, which is what WSL wants. Every WSL image built before this failed there, silently, because the first run swallowed the failure rather than reporting it.

The image ships with no password hashes in `/etc/shadow`, which Microsoft requires of a distributable image. Windows owns the authentication boundary, so there is no password for `sudo` to prompt for; `/etc/sudoers.d/omarchy-wsl` grants `%wheel` passwordless sudo to match.

### The setup screen

`bin/omarchy-provision-wsl-owner` is the same screen the first boot on hardware draws: the logo running a `ttfx` ColorShift, the `gum` prompts, the summary table, and the 34-cell progress bar with its rotating tips. It is the same screen because it is the same code — `install/provisioning/setup-ui.sh` holds all of it, and `bin/omarchy-provision-owner` sources the same file. `install/provisioning/setup-form.sh` was already that arrangement for the questions, and the two are meant to be sourced together: the form calls `notice()`, which the UI defines.

The library leaves two things to its caller, because they are the parts that genuinely differ. `scale_console_font` is the framebuffer console's problem and defaults to nothing, so only `omarchy-provision-owner` overrides it. `setup_progress` moves the bar, and each caller measures against its own phases — LUKS re-keying on hardware, a package download here.

What the WSL screen does not ask is as deliberate as what it does:

| Not asked | Why |
| --- | --- |
| Password | The image carries no `/etc/shadow` hashes, Windows owns the login boundary, and `/etc/sudoers.d/omarchy-wsl` grants `%wheel` passwordless sudo to match |
| Hostname | WSL names the distribution |
| Timezone | WSL syncs the clock from the Windows host, which is why `tzupdate` is on the skip list |
| Keyboard layout | Windows applies the layout before the keysym reaches the session. The viewer sends keysyms rather than scan codes, and wayvnc's virtual keyboard carries its own keymap — a compositor `kb_layout` here would either do nothing or apply a second layout on top of the first. It is the same fact `install/wsl/hypr.sh` resolves bindings by symbol for |
| LUKS, SDDM, the console font, the VT palette | No encrypted root, no display manager, and Windows Terminal is not a framebuffer console |

What it does ask is the account — the username prefilled from the Windows sign-in through `OMARCHY_USERNAME_DEFAULT`, since WSL ties the distribution to that account anyway — the git identity, and two questions about the size of the download, which on a machine where nothing is installed yet is the whole cost of a first run:

- **the preinstalled applications**, wired to `install/wsl/omarchy-wsl-defer.packages` and, when declined, to the `preinstalls-removed` marker `bin/omarchy-remove-preinstalls` already writes and `default/hypr/helpers.lua` already reads. `omarchy-install-preinstalls` is the way back, so the deferred list has to stay identical to the one that command restores; `test/shell.d/wsl-oobe-test.sh` holds the two together.
- **the AI coding agents**, wired to `OMARCHY_SKIP_AGENT_CLIS` in `install/user/mise.sh`. `omarchy-install-agent-clis` is the way back.

Every step in `run_provisioning` checks its own status rather than leaving it to `set -e`. `run_setup` is called from a `while !` in `main`, and bash disables errexit for the whole dynamic extent of a command whose status is being tested — the function, and the background job it runs in. An earlier version relied on errexit there and sailed past a failed install: it created the account, ran the user setup against packages that were not installed, cleared the pending marker and reported that Omarchy was ready. `test/shell.d/wsl-oobe-test.sh` drives all five failure positions to hold that shut.

`/etc/oobe.sh` offers the screen and never depends on it. A terminal it cannot draw on, a missing `gum` or a bug in it all fall through to the plain path that asks nothing and installs everything, because the one thing that must not happen there is a user left with no account.

## What the image contains

`bin/omarchy-apply-wsl` is the WSL counterpart of `bin/omarchy-apply-system`, and `install/wsl/all-image.sh` and `install/wsl/all-setup.sh` are its ordered step lists. It deliberately does not call `omarchy-apply-system`: five of that script's steps assume hardware WSL does not have, and there is no skip mechanism anywhere under `install/`.

What the tarball itself contains is much less than what an installed machine does — see [Two phases](#two-phases). Everything below describes the installed result.

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

Dropped: the display manager and boot splash, Bluetooth, printing and mDNS, the firewall, Docker, the power/backlight/DDC/Thunderbolt stack, the kernel module and wireless regulatory helpers, foreign-architecture emulation, `plocate` for an index nothing builds, and `man-db` for pages `NoExtract` keeps out. The skip list carries the reasoning inline.

Not everything on it actually goes. Subtracting a name only declines to ask for it, and `sddm`, `plymouth`, `avahi` and `wireplumber` are dependencies of `omarchy` and `omarchy-settings`, which the image installs whatever else it skips — they ship the files at fixed system paths `OMARCHY_PATH` does not cover. The entries stay because the reasoning still holds and a package that drops the dependency should take effect at once, but they are not what protects anything. For `sddm` that protection is the mask in `install/wsl/services.sh`.

Added for WSL only: `sudo` (absent from the official Arch WSL rootfs) and the session's own runtime — `seatd` and `wayvnc`, both explained under [The DRM device](#the-drm-device) and [The window](#the-window).

`install/wsl/omarchy-wsl-bootstrap.packages` is a third and much shorter list: `sudo`, `gum` and `ttfx`, all the image phase installs. Everything else arrives with the setup phase.

Two steps need a toolchain for a single operation and have no use for it afterwards — `install/wsl/image.sh` renders the Windows `.ico` with ImageMagick, `install/wsl/neatvnc.sh` builds a package with `base-devel`. `install/helpers/transient-packages.sh` installs each, then removes what the install actually added, taken as the difference between two `pacman -Qq` queries rather than assumed from the names asked for, since most of the weight is dependencies. The neatvnc leaf then checks `neatvnc`, `wayvnc` and `hyprland` survived, because an over-eager prune would otherwise only show up in the session, long after the build looked fine.

### Documentation and locales

`install/wsl/pacman-noextract.sh` adds `NoExtract` directives to `[options]` for `usr/share/man`, `usr/share/info`, `usr/share/doc`, `usr/share/gtk-doc` and every `usr/share/locale` but `en_US`. Nothing in the install path strips those afterwards, and doing it through pacman rather than with `rm` means a later `pacman -Syu` does not put them back.

`usr/share/i18n` is deliberately not on the list: `locale-gen` reads its locale definitions and charmaps from there, so excluding it would leave the image unable to generate the one locale it needs.

It runs twice. The image phase writes the directives before anything is installed, and the setup phase writes them again after `install/post-install/pacman.sh`, which restores the shipped `pacman.conf` over the top of them. The script checks for its own marker first, so a third run costs nothing.

### Services

`install/wsl/services.sh` is the inverse of `install/config/enable-services.sh`. It sets `multi-user.target` as the default, masks `sddm.service`, enables `seatd.service`, and masks the units Microsoft documents as breaking WSL — including `NetworkManager` and `systemd-resolved`, which are exactly what the hardware path enables. WSL supplies the interface and writes `/etc/resolv.conf` itself.

Enabling is not starting, and that distinction only started mattering with the phase split. While this step ran in the build container there was no next boot to wait for — the image had not started yet, and every symlink took effect when someone imported it. It runs on a booted machine now, during the first run, so `seatd` would be enabled but not running, `/run/seatd.sock` would not exist, and `start-omarchy` in that same session would die at `CBackend::create() failed!` until the distribution was restarted. So when `/run/systemd/system` says systemd is really running, the step reloads the manager, starts `seatd`, and stops any masked unit that was already up — leaving the machine in the state a reboot would.

Every call uses `systemctl --root=/`. The build container has no systemd on the bus, and unlike an `arch-chroot` install systemd cannot tell it is not the real root, so a plain `systemctl mask` there fails with "System has not been booted with systemd". With `--root=` it is a pure file operation, which is all that matters for symlinks that take effect on the next boot.

`sddm` is masked even though the package is not installed. It is the only thing that ever starts the compositor, so a later `pacman -S sddm` must not be able to bring the desktop up at boot behind the user's back.

## Starting the desktop

```bash
start-omarchy
```

`install/wsl/wslg.sh` installs `/usr/local/bin/start-omarchy` as a small wrapper that execs `omarchy-launch-wsl-session`. There is no X server involved despite the name — `start-omarchy` is simply where people reach for a desktop from a WSL shell. `xorg-xinit` is not installed and `/usr/local/bin` precedes `/usr/bin`, so nothing is shadowed.

The launcher points aquamarine at the VKMS device, unsets `WAYLAND_DISPLAY`, and starts the compositor under its own D-Bus session bus:

```bash
dbus-run-session -- Hyprland
```

On hardware that line is `uwsm start -g -1 -e -D Hyprland hyprland.desktop`, from `default/wayland-sessions/omarchy.desktop`, which is what SDDM runs. WSL cannot use it — see [No systemd user session](#no-systemd-user-session) below.

It starts in the background rather than replacing the launcher, because the session still has to be given somewhere to draw and something to show it in. Once `hyprctl` answers, the launcher creates a headless output, serves it with wayvnc on the loopback, and opens a VNC viewer as an ordinary WSLg client. Closing that window ends the session.

### No systemd user session

**`systemd --user` does not work on Arch under WSL.** `user@1000.service` fails with `Failed to spawn executor: Device or resource busy`, every time, on a freshly imported image. `user@0` — root — starts fine; only the login account is affected.

The reason is visible in the cgroup tree. `user@1000.service` has leftover children (`init.scope`, `session.slice/dbus.service`, `session.slice/at-spi-dbus-bus.service`) whose `cgroup.procs` list **PID 0**: processes belonging to a PID namespace WSL holds open, which cannot be reaped and whose cgroups cannot be removed. systemd spawns services with `clone3(CLONE_INTO_CGROUP)`, which requires the target cgroup to be a leaf and returns `EBUSY` against a populated one. Nothing inside the distribution can clear it. A stock `archlinux` WSL distribution fails identically, so this is not something Omarchy causes or can fix.

That rules out uwsm, whose whole job is driving systemd user units. So on WSL `start-omarchy` is the session leader instead, and takes on what uwsm would have done:

- **The session environment.** uwsm sources `/usr/share/uwsm/env.d/10-omarchy`, which is where `OMARCHY_PATH`, `TERMINAL` and `EDITOR` come from. The launcher reads `default/bash/env-bootstrap` and `default/uwsm/default` itself. A login shell already has `OMARCHY_PATH` from `/etc/profile.d/omarchy.sh`; `wsl -d Omarchy start-omarchy` is not a login shell, which is why the launcher cannot assume it.
- **The session bus.** Normally `dbus.socket` in the user manager. `dbus-run-session` is the standalone equivalent.
- **The activation environment.** `default/hypr/autostart.lua` runs `dbus-update-activation-environment --systemd --all`, which needs the user manager. The launcher runs the same command without `--systemd` once the compositor's socket exists, so the `xdg-desktop-portal` backends are activated knowing which display to talk to.
- **The compositor's socket name.** `autostart.lua` publishes it into the user manager, and wayvnc needs it. With no manager to ask, the launcher lists the `wayland-N` sockets before starting Hyprland and takes whichever one appears afterwards. WSLg's own `wayland-0` is already in the first list.

`graphical-session.target` is never reached, so the six user units in `default/systemd/user/` that `install/user/first-run/enable-user-units.sh` enables do not start. That step now skips itself when no user manager is running, rather than failing: `omarchy-provision-first-run` writes its completion marker only when every step succeeded, so a single failure replayed the whole first-run sequence — welcome notification included — on every single login. All six units are optional or hardware-shaped — `bt-agent` (no bluez in the image), `omarchy-recover-internal-monitor`, `omarchy-sleep-lock` (no logind suspend here), `omarchy-migrate-notify`, `omarchy-fcitx5`, `omarchy-crash-watch` — so the desktop is unaffected.

### No idle lock

The image ships with idle locking off, seeded as `/etc/skel/.local/state/omarchy/indicators/stay-awake` by `install/wsl/idle.sh`.

It has to be. Microsoft requires a distributable WSL image to carry no password hashes, which is why `/etc/sudoers.d/omarchy-wsl` grants passwordless sudo — and it equally means the lock screen can never be answered. `passwd -S` reports the account as `L`. A session that locks on idle is one you cannot get back into, and `omarchy-restart-shell` does not rescue it: `allow_session_lock_restore` lets the fresh shell re-acquire the lock, so the only way out is ending the session.

The idle service has no off switch for the lock timeout on its own — `secondsFromConfig` treats `0` as *lock immediately*, not never — so the marker that `omarchy-toggle-idle` writes is the mechanism. `omarchy toggle idle` still flips it back on, which on WSL is a way to lock yourself out.

### No Wi-Fi prompt

`install/user/first-run/wifi.sh` offers to configure wireless when the machine cannot reach the network. It now checks for a wireless interface first, so it stays quiet here: the image has none, the network belongs to the Windows host, and `install/wsl/services.sh` masks NetworkManager anyway. Without that check the prompt appeared on every login, after spending up to a minute in `nm-online` waiting for a daemon that is masked.

### Launching applications

Omarchy launches every application through `uwsm-app`, which asks `wayland-wm-app-daemon.service` to put it in its own systemd user scope: `o.launch()` in `default/hypr/helpers.lua`, the menu, the shell's app library, and around thirty commands in `bin/`. With no user manager that daemon does not exist, and the desktop would come up able to launch nothing at all.

`install/wsl/uwsm.sh` shims both `uwsm-app` and `uwsm` into `/usr/local/bin`, which precedes `/usr/bin` — the same mechanism as the `start-omarchy` shim, and for the same reason: WSL knowledge stays in `install/wsl/` rather than becoming a condition in thirty call sites. `uwsm-app` drops the options up to the first `--` and runs the command directly under `setsid --fork`, returning immediately the way the real one does, with output sent to the journal. `uwsm stop` becomes `hyprctl dispatch exit`; anything else falls through to the real `uwsm`.

The same environment is installed at `/etc/profile.d/omarchy-wslg.sh` for ordinary shells, so individual GUI apps opened from a prompt find the WSLg sockets too.

Five commands go further and ask the user manager for a scope of their own, through `systemd-run --user`: `omarchy-launch-browser`, `omarchy-menu-share`, `omarchy-system-shutdown`, `omarchy-system-reboot` and `omarchy-reminder`. Those fail before they start anything, and `omarchy-launch-browser` passes `--property=StandardError=null`, so the browser simply never appeared and nothing was written anywhere — the failure had no symptom but absence.

`install/wsl/systemd-run.sh` shims it the same way, with two things it must get right. **Only `--user` is intercepted**; without that flag the call goes straight to `/usr/bin/systemd-run`, because the *system* manager works here and `omarchy-sudo-passwordless` schedules its timers against it. And **`--on-active` is translated, not discarded**: three of the five callers are timers, where the shutdown and reboot paths use the delay to return before the machine goes down and `omarchy-reminder` schedules minutes ahead. A shim that collapsed those to "run now" would reboot the machine out from under the command that asked and fire every reminder immediately — worse than not running them. The spans become a `sleep` before the command, and output goes to the journal rather than nowhere, so the next failure of this kind is visible.

**VS Code refuses to start quietly inside WSL.** Its launcher, `/usr/share/code/bin/code`, greps `/proc/version` for `Microsoft` — which matches, since WSL2 kernels are `microsoft-standard-WSL2` — then prints a notice recommending the Windows build and blocks on `read -r YN`. That breaks installing and launching alike: `omarchy-theme-set-vscode` runs `code --list-extensions` with stderr discarded, so `omarchy-install-editor-vscode` stops dead after the packages land with nothing on screen to explain why, and `code.desktop` is `Exec=code %F`, so launching under `uwsm-app` hands the prompt an empty stdin, which it reads as "no". `install/wsl/vscode.sh` sets `DONT_PROMPT_WSL_INSTALL=1` in `/etc/profile.d` — the launcher's own escape hatch, named in the message it prints. `/etc/profile.d` reaches both, because the desktop shortcut starts the session with `bash -lc start-omarchy` and everything `uwsm-app` launches inherits from there.

**The session does not inherit WSLg's `DISPLAY`.** `/etc/profile.d/omarchy-wslg.sh` sets `DISPLAY=:0` so a GUI app started from a plain shell finds WSLg's X server, which is right for that case and wrong inside the session: there `:0` is a *foreign* display, belonging to a server whose windows appear on the Windows desktop rather than in the Omarchy one, and no Xwayland runs in the session to take the name back. An X11 client launched from the desktop connects there and its window simply never arrives. VS Code showed this plainly — six processes running, no window, nothing in any log — because Electron tries X11 first whenever `DISPLAY` is set and `XDG_SESSION_TYPE` is not `wayland`, and with no display manager here nothing sets the latter.

`bin/omarchy-launch-wsl-session` therefore starts the compositor as `env -u DISPLAY XDG_SESSION_TYPE=wayland dbus-run-session -- start-hyprland`. Toolkits then choose Wayland, and Hyprland supplies its own Xwayland for whatever still needs X. The launcher keeps its own `DISPLAY`, because a viewer inside WSL is itself an X11 client of WSLg.

### Audio

**WSL has no sound hardware.** `/dev/snd` carries a timer and nothing else, so there is no card for ALSA to open and no device for PipeWire to drive. Sound leaves the machine through WSLg, which runs a PulseAudio server with an RDP sink that plays on the Windows side; `install/wsl/wslg.sh` points `PULSE_SERVER` at its socket.

That covers applications speaking PulseAudio. It does not cover ALSA, and an ALSA application in that state does not fail loudly — it starts, draws its interface and plays silence, with `cannot find card '0'` buried where nobody looks. cliamp is one: it links `libasound` directly. On hardware the bridge comes from `pipewire-alsa`, but PipeWire's user services cannot run here at all without a systemd user manager, so `install/wsl/packages.sh` installs `alsa-plugins` for ALSA's own pulse plugin and `install/wsl/audio.sh` writes `/etc/asound.conf` pointing the default device at it.

All of this depends on WSLg actually running, and WSLg only tries when the distribution starts. When its daemon fails there is no audio at all and no second path to fall back to, so `start-omarchy --diagnose` reports the PulseAudio server alongside everything else. `/mnt/wslg/stderr.log` records why WSLg failed; restarting the distribution is what retries it.

### Keybindings

**Hyprland matches keybindings by keycode, and that does not work here.** The only keyboard in a WSL session is the virtual one wayvnc creates for the VNC client, and it carries its own keymap, so the keycodes never line up and not one binding fires. Typed text still reaches applications, which makes it look like the bindings are broken rather than the matching — a session where `SUPER + RETURN` does nothing but typing works is this, every time.

`install/wsl/hypr.sh` appends `hl.config({ input = { resolve_binds_by_sym = true } })` to `/etc/skel/.config/hypr/input.lua`, which matches on the symbol the client actually sent. Without it the desktop has no working keybindings at all, whichever VNC client is used.

`SUPER` also has to survive the trip from Windows, which is a separate problem: Windows keeps that key for itself unless the viewer grabs the keyboard. TurboVNC does, in a window — see below.

**The viewer sends keysyms, not scan codes.** RFB has no keyboard-layout negotiation; it has two key transports. X11 keysyms name the key outright and are layout independent, while the QEMU Extended Key Event sends raw scan codes for the server's keymap to interpret. TurboVNC prefers the scan-code path by default, and on that path it transmits the **right** Windows key with the extended bit dropped: `E0 5C` becomes plain `0x5C`, which is qnum 92, which is `KEY_KPJPCOMMA` — arriving as keycode 103 with `NoSymbol` and setting no modifier, so no binding fires. The left key is unaffected. `omarchy-launch-wsl-session` therefore passes `-noServerKeyMap`, and both Super keys work. Reported upstream as [TurboVNC #494](https://github.com/TurboVNC/turbovnc/issues/494).

### The DRM device

**Hyprland needs a DRM device with a display attached, and stock WSL2 kernels have none.** Aquamarine wants a device it can both allocate GBM buffers on and find a CRTC in. WSL2 exposes Microsoft's `/dev/dxg`, which is not a DRM device at all: on a stock kernel `/dev/dri` does not exist.

So on a stock kernel, everything except the full session works. The CLI, themes, config and individual GUI apps over WSLg are all fine; `start-omarchy` is not.

`start-omarchy --diagnose` reports what is present and what is missing without starting anything.

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

**No DRM render node may be present.** Community kernel patches exist that give `dxgkrnl` a DRM driver, and they are actively harmful here: they add a `renderD` node that Mesa has no driver for, aquamarine prefers it over the KMS fd anyway, and then every buffer import against it fails. The desktop draws, but screen capture hangs and window resizes never apply. Omarchy's kernel deliberately does not carry those patches, so `/dev/dri` holds `card0` alone. `/dev/dxg` is a separate char device and is untouched, so WSL's own GPU passthrough is unaffected. `start-omarchy --diagnose` calls out a stray `renderD*` for this reason.

**The compositor renders in software; applications render on the GPU.** The split is not a preference — the compositor cannot use the GPU here, and the reason is worth recording because it is not obvious.

WSL does share the host GPU, through `/dev/dxg`. That is a char device, not a DRM one, which is why the render-node rule above leaves it untouched; Mesa's `d3d12` driver drives it, and WSL mounts the host half at `/usr/lib/wsl/lib` and puts it on the linker path itself through `/etc/ld.so.conf.d/ld.wsl.conf`. Mesa will not find it unaided — with no DRM render node there is nothing to auto-detect from — so the driver has to be named, and `gpu_render_available()` checks for `/dev/dxg`, `d3d12_dri.so`, `libd3d12core.so` and `libdxcore.so` before naming it.

The compositor cannot be pointed at it. It allocates its buffers through GBM on the VKMS device, and a GBM device inherits whichever driver Mesa was told to use — so naming `d3d12` asks Mesa to allocate a VKMS buffer with a driver that cannot address VKMS:

```
GBM: Failed to allocate a GBM buffer: bo null
Couldn't allocate a gbm buffer with size [1920, 1080] and format XR24
Swapchain: Failed acquiring a buffer
```

The desktop then draws nothing at all: a viewer connects and reports zero rects. This is the same wall the `dxgkrnl` render node hit, one step earlier — there the dmabuf import failed, here the allocation does. llvmpipe allocates on VKMS because it renders into the buffer it was handed.

An application has no such constraint. It renders into its own buffer and hands the compositor a finished surface, so nothing of its has to live on VKMS. `/usr/local/bin/uwsm-app` is where they are given the GPU: Omarchy launches every application through it, so the switch sits at that one chokepoint rather than at thirty call sites, and it acts on the `OMARCHY_WSL_GPU` marker the session launcher sets when the GPU is really there. Without a GPU, or with `OMARCHY_WSL_SOFTWARE_RENDER=1`, everything renders in software as it always did, and `startomarchy --diagnose` names which piece is missing.

There is no Vulkan. `/usr/share/vulkan/icd.d` does not exist, so `vulkan-icd-loader` has no driver behind it. Hyprland renders with GLES, so the session does not care, but anything that asks for Vulkan will not find it.

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

Neither viewer needs dmabuf and neither negotiates a Wayland protocol version, which is why showing the session over VNC works at all. Nesting Hyprland directly in WSLg's Weston does not: that Weston is 9.0.0 and advertises `wl_compositor` v5 against the v6 aquamarine binds.

**The viewer runs on Windows, and the session does not start without one.** `omarchy setup wsl viewer` fetches two, into `%LOCALAPPDATA%\Omarchy`, and the launcher prefers TurboVNC, then TigerVNC.

There used to be a third: the `tigervnc` viewer inside WSL, reached when neither Windows one was found. It is gone, and the package with it. That viewer never receives `SUPER`, so the desktop it opened had no working keybindings — and it was reached silently, which made a missing viewer look like a broken desktop. A session nobody can drive is worse than no session, so the launcher now refuses and says why.

Which of two reasons matters, because they need opposite fixes. If nothing was recorded and `cmd.exe` did not answer, interop is down and the viewer may well be installed — `wsl --shutdown` is the fix. If the directory resolved but holds no viewer, `omarchy setup wsl viewer` is. `startomarchy --diagnose` reports the same distinction.

The launcher finds that directory from a path `omarchy-setup-wsl-viewer` records at `~/.local/state/omarchy/wsl-viewer-dir`, falling back to asking Windows only when nothing is recorded or what was recorded has gone. It used to ask Windows every time, and that needs interop: one `cmd.exe` call coming back empty was enough to drop a session into the unusable viewer while TurboVNC sat installed all along.

TurboVNC is the one the desktop uses, because it is the only one that **grabs the keyboard in a window** (`-GrabKeyboard Always`). Without a grab, Windows keeps `SUPER` and every Omarchy binding is dead; TigerVNC grabs only in full screen ([upstream #1899](https://github.com/TigerVNC/tigervnc/issues/1899)). **CTRL-ALT-SHIFT-G** toggles the grab when you want Windows shortcuts back.

Both are pinned by version and SHA256, since neither publisher signs the download. TurboVNC ships only an Inno Setup installer, so `omarchy-setup-wsl-viewer` fetches a pinned `innoextract` and **unpacks** it rather than running it: running it would put a VNC *server* on the Windows machine and ask for elevation. Its viewer is Java and carries its own JRE, so the whole tree is installed rather than a single file.

Two of its parameters bite. Booleans take no value — `-Toolbar 0` prints usage and exits, `-noToolbar` is correct — and `-RecvClipboard 1` makes the viewer read the `1` as the hostname and sit on a connection dialog.

The reason to prefer the Windows one is the clipboard. wayvnc already carries the selection both ways over `ext_data_control_manager_v1`, and neatvnc implements the extended clipboard, which is what carries UTF-8 — plain RFB cut text is latin-1. But a viewer running inside WSL bridges that to Xwayland's selection, not to the Windows clipboard. A native client bridges it to Windows.

**The cursor is drawn once, by the viewer.** A headless output has no hardware cursor plane, so Hyprland composites the pointer straight into the framebuffer that wayvnc captures — and wayvnc forwards the cursor to the client as well, so the viewer shows two. `hide_compositor_cursor()` in `bin/omarchy-launch-wsl-session` turns the compositor's cursor off (`hyprctl eval`, since `hyprctl keyword` does not work against the Lua config) and the launcher passes `-AlwaysCursor=1 -CursorType=System`, so the client draws the only pointer, locally and without a round trip. It is called on the TigerVNC branches and only those: TurboVNC hides its own pointer and expects the composited one.

Dragging the window edge resizes the desktop to match, and only a `HEADLESS-*` output is eligible, which is why the VKMS one is not the desktop.

That needs a patched neatvnc, built by `install/wsl/neatvnc.sh`. A VNC client only learns the server can resize by receiving an `ExtendedDesktopSize` rect, and stock neatvnc sends one only when the desktop actually resizes or when a client asks for a resize — while the first updates it sends are standalone cursor and desktop-name rects. TurboVNC decides at its first framebuffer update and never revisits it, logging `Disabling automatic desktop resizing because the server doesn't support it`, so the desktop never follows the window. TigerVNC is unaffected only because it assumes support optimistically.

`install/wsl/patches/neatvnc-announce-desktop-size.patch` announces the layout as soon as the client's encodings are known, which is what the RFB spec expects. The leaf rebuilds the Arch package with that patch and a bumped `pkgrel`, so a plain `-Syu` does not silently drop it — but an upstream version bump will, until the patch lands upstream.

## Files

| Path | Role |
| --- | --- |
| `bin/omarchy-dev-wsl-build` | Builds the `.wsl` image in Docker |
| `bin/omarchy-dev-wsl-kernel` | Builds a VKMS-enabled WSL2 kernel in Docker |
| `bin/omarchy-apply-wsl` | Root-owned system setup inside the image |
| `bin/omarchy-provision-wsl-owner` | The first-run setup screen: the questions, the install, the account |
| `install/provisioning/setup-ui.sh` | The screen both first runs draw — greeter, chrome, progress bar |
| `install/wsl/omarchy-wsl-defer.packages` | The applications the first run may be told to skip |
| `bin/omarchy-launch-wsl-session` | What `start-omarchy` runs: the session, wayvnc, and the viewer |
| `install/wsl/uwsm.sh` | Shims `uwsm-app` and `uwsm`, which need a systemd user manager |
| `bin/omarchy-setup-wsl-viewer` | Fetches the Windows VNC viewer the desktop opens in |
| `install/wsl/all-image.sh` | The image phase's step list — what the tarball carries |
| `install/wsl/all-setup.sh` | The setup phase's step list — what the first run installs |
| `install/wsl/omarchy-wsl-skip.packages` | Packages subtracted from the base manifest |
| `install/wsl/omarchy-wsl-bootstrap.packages` | The few packages the image carries before the first run |
| `install/wsl/pacman-noextract.sh` | Keeps man pages, docs and other locales off the machine |
| `install/helpers/transient-packages.sh` | Installs a toolchain for one step and takes it back out |
| `default/wsl/setup-resume.sh` | `/etc/profile.d/omarchy-wsl-setup.sh` — finishes an interrupted first run |
| `default/wsl/wsl.conf` | `/etc/wsl.conf` — systemd, interop, resolv.conf generation |
| `default/wsl/wsl-distribution.conf` | `/etc/wsl-distribution.conf` — OOBE, shortcut, terminal profile |
| `default/wsl/oobe.sh` | `/etc/oobe.sh` — the setup phase and first-run account creation |
| `default/wsl/terminal-profile.json` | Windows Terminal profile and colour scheme |

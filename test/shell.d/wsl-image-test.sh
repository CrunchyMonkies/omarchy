#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_packages="$ROOT/install/omarchy-base.packages"
skip_packages="$ROOT/install/wsl/omarchy-wsl-skip.packages"
bootstrap_packages="$ROOT/install/wsl/omarchy-wsl-bootstrap.packages"

source "$ROOT/install/helpers/package-list.sh"

# The install runs in two phases now, and which phase a step belongs to is the
# whole point of the split, so the checks below name the list they expect a step
# in rather than searching both.
image_steps="$ROOT/install/wsl/all-image.sh"
setup_steps="$ROOT/install/wsl/all-setup.sh"
all_steps=$(cat "$image_steps" "$setup_steps")

# A skip entry that no longer names a real package is dead weight that silently
# stops protecting anything, so hold the list to the manifest it subtracts from.
unknown=$(comm -23 <(read_package_list "$skip_packages") <(read_package_list "$base_packages"))
[[ -z $unknown ]] || fail "every WSL skip entry exists in the base package list" "$unknown"
pass "every WSL skip entry exists in the base package list"

# The one requirement the whole image rests on: nothing may start the desktop
# on its own. sddm is the only thing that ever does.
grep -qx sddm <(read_package_list "$skip_packages") ||
  fail "the WSL image drops sddm so the desktop cannot auto-start"
pass "the WSL image drops sddm so the desktop cannot auto-start"

grep -q 'systemctl --root=/ mask sddm.service' "$ROOT/install/wsl/services.sh" ||
  fail "install/wsl/services.sh masks sddm.service"
pass "install/wsl/services.sh masks sddm.service"

grep -q 'systemctl --root=/ set-default multi-user.target' "$ROOT/install/wsl/services.sh" ||
  fail "install/wsl/services.sh boots to multi-user.target"
pass "install/wsl/services.sh boots to multi-user.target"

# The session reaches the VKMS device through libseat, and logind has no seat to
# offer it here. Without seatd running, start-omarchy cannot open /dev/dri/card0.
grep -q 'systemctl --root=/ enable seatd.service' "$ROOT/install/wsl/services.sh" ||
  fail "install/wsl/services.sh enables seatd.service"
pass "install/wsl/services.sh enables seatd.service"

# There is no display to scan out to, so the session is only reachable through
# wayvnc and a viewer. Both are WSL-only additions the base manifest never names.
for package in seatd wayvnc tigervnc; do
  grep -q "packages+=(.*\b$package\b.*)" "$ROOT/install/wsl/packages.sh" ||
    fail "install/wsl/packages.sh installs $package"
done
pass "install/wsl/packages.sh installs the session's seat and VNC packages"

# oobe.sh filters the recorded groups to ones that exist, so a name that never
# gets written here is dropped silently rather than failing the first boot.
for group in seat video render; do
  grep -q "wsl_session_groups=(.*\b$group\b.*)" "$ROOT/install/wsl/groups.sh" ||
    fail "install/wsl/groups.sh records the $group group"
done
pass "install/wsl/groups.sh records the session's device groups"

# wayvnc only resizes a HEADLESS-* output, so the VKMS one has to be off -- and
# off from config, since hyprctl reload re-enables a runtime-disabled monitor.
grep -q 'hl.monitor({ output = "Virtual-1", disabled = true })' "$ROOT/install/wsl/hypr.sh" ||
  fail "install/wsl/hypr.sh disables the VKMS output from config"
pass "install/wsl/hypr.sh disables the VKMS output from config"

# pacman confines downloads with Landlock, which Docker refuses. Without the
# opt-out the build dies at the first sync on any Landlock-capable host kernel;
# with it left in place, the image ships a config users should not have.
grep -qF "sed -i '/^\[options\]/a DisableSandboxFilesystem' /etc/pacman.conf" \
  "$ROOT/bin/omarchy-dev-wsl-build" ||
  fail "the build disables pacman's filesystem sandbox in the [options] section"

grep -q "the container-only pacman sandbox opt-out reached the image" \
  "$ROOT/bin/omarchy-dev-wsl-build" ||
  fail "the build fails if that opt-out reaches the image"
pass "the pacman sandbox opt-out is container-only"

# WSL has no working systemd user manager, so the launcher is the session leader
# and must not reach for one -- reading WAYLAND_DISPLAY back out of it is what it
# used to do, and that failed the session before the desktop ever drew.
! grep -q 'systemctl --user' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session does not depend on a systemd user manager"
grep -q 'dbus-run-session -- start-hyprland' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session starts the compositor under its own session bus"
pass "omarchy-launch-wsl-session owns the session without systemd --user"

# The desktop never starts on its own, so the image has to give users an entry
# point, and this shim is it. Nothing else installs one.
grep -q 'install -Dm755 /dev/stdin /usr/local/bin/start-omarchy ' "$ROOT/install/wsl/wslg.sh" ||
  fail "install/wsl/wslg.sh shims start-omarchy"
grep -q 'exec omarchy-launch-wsl-session' "$ROOT/install/wsl/wslg.sh" ||
  fail "the start-omarchy shim hands off to omarchy-launch-wsl-session"
pass "install/wsl/wslg.sh shims start-omarchy onto the session launcher"

# The old name was removed rather than aliased, so the shortcut and the shim
# have to agree -- a stale 'bash -lc startx' would start nothing.
grep -q "bash -lc start-omarchy" "$ROOT/bin/omarchy-setup-wsl-viewer" ||
  fail "the Windows shortcut starts the desktop with start-omarchy"
pass "the Windows shortcut and the shim agree on the entry point"

# Every application Omarchy launches goes through uwsm-app, which needs the user
# manager. Without these shims the desktop starts and can launch nothing.
for shim in uwsm-app uwsm; do
  grep -q "install -Dm755 /dev/stdin /usr/local/bin/$shim " "$ROOT/install/wsl/uwsm.sh" ||
    fail "install/wsl/uwsm.sh installs the $shim shim"
done
pass "install/wsl/uwsm.sh shims uwsm-app and uwsm"

# Five commands ask the user manager for a scope of their own. omarchy-launch-browser
# is the one that hurt: it passes StandardError=null, so a browser that never
# started left nothing behind to say so.
grep -q 'install -Dm755 /dev/stdin /usr/local/bin/systemd-run ' "$ROOT/install/wsl/systemd-run.sh" ||
  fail "install/wsl/systemd-run.sh installs the systemd-run shim"
pass "install/wsl/systemd-run.sh shims systemd-run"

# Only --user is broken. omarchy-sudo-passwordless schedules against the system
# manager, which works here, so a shim that swallowed every call would break it.
grep -q 'exec /usr/bin/systemd-run "$@"' "$ROOT/install/wsl/systemd-run.sh" ||
  fail "the systemd-run shim delegates when --user is absent"
pass "the systemd-run shim delegates when --user is absent"

# Three of the five callers are timers: shutdown and reboot return before the
# machine goes down, and omarchy-reminder schedules minutes ahead. Collapsing
# those to "run now" reboots the machine out from under the caller and fires
# every reminder immediately, with nothing to show the delay was dropped.
for form in '--on-active=\*)' '--on-active)'; do
  grep -q -- "$form" "$ROOT/install/wsl/systemd-run.sh" ||
    fail "the systemd-run shim handles the $form form of --on-active"
done
pass "the systemd-run shim handles both forms of --on-active"

# The span arithmetic itself, run rather than read: "2ms" ends in s and "5min"
# ends in n, so the case order is the only thing keeping the suffixes apart.
shim_source=$(sed -n "/^install -Dm755 .*systemd-run <<'SYSTEMD_RUN'$/,/^SYSTEMD_RUN$/p" \
  "$ROOT/install/wsl/systemd-run.sh" | sed '1d;$d')

for probe in "2ms 0" "5min 300" "2s 2" "5m 300" "1h 3600" "90 90"; do
  set -- $probe
  got=$(bash -c "${shim_source%%$'\n'user_scope=*}"$'\n'"span_to_seconds $1")
  [[ $got == "$2" ]] ||
    fail "the systemd-run shim reads the span $1 as $2 seconds" "got $got"
done
pass "the systemd-run shim converts systemd time spans correctly"

# VS Code's launcher greps /proc/version for Microsoft and then blocks on
# "read -r YN". That stops the install with no output and makes launching exit
# silently, since uwsm-app gives the prompt an empty stdin.
grep -q 'DONT_PROMPT_WSL_INSTALL=1' "$ROOT/install/wsl/vscode.sh" ||
  fail "install/wsl/vscode.sh answers VS Code's WSL prompt in advance"
grep -q 'install -Dm644 /dev/stdin /etc/profile.d/omarchy-wsl-vscode.sh' "$ROOT/install/wsl/vscode.sh" ||
  fail "install/wsl/vscode.sh installs the variable where login shells find it"
pass "install/wsl/vscode.sh answers VS Code's WSL install prompt"

# Belt and braces for the same class of bug: the theme sync cannot answer a
# prompt, so it must not be able to wait for one.
grep -q -- '--list-extensions </dev/null' "$ROOT/bin/omarchy-theme-set-vscode" ||
  fail "omarchy-theme-set-vscode cannot block listing extensions"
grep -q -- '--install-extension "$extension" </dev/null' "$ROOT/bin/omarchy-theme-set-vscode" ||
  fail "omarchy-theme-set-vscode cannot block installing an extension"
pass "omarchy-theme-set-vscode never waits on stdin"

# WSLg's DISPLAY belongs to a server outside the session. Left set, X11 clients
# launched from the desktop connect there and their windows never appear --
# VS Code runs with no window and nothing logged.
grep -q 'env -u DISPLAY XDG_SESSION_TYPE=wayland dbus-run-session -- start-hyprland' \
  "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "the compositor starts without WSLg's DISPLAY"
pass "the compositor does not inherit WSLg's DISPLAY"

# Both leaves have to actually run during the build.
for leaf in vscode systemd-run; do
  grep -q "wsl/$leaf.sh" "$setup_steps" ||
    fail "install/wsl/all-setup.sh runs $leaf.sh"
done
pass "install/wsl/all-setup.sh runs the vscode and systemd-run leaves"

# The viewer runs on Windows so the session can reach the Windows clipboard; an
# X11 viewer inside WSLg bridges to Xwayland instead. The fallback has to stay,
# because nothing on a fresh Windows install provides a VNC client.
grep -q 'windows_viewer_dir()' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session prefers a Windows viewer"
grep -q 'vncviewer -SecurityTypes None' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session still falls back to the viewer inside WSL"
pass "omarchy-launch-wsl-session prefers the Windows viewer and falls back"

# SourceForge publishes no signature for the download, so the pinned digest is
# the only integrity check there is. A version bump that forgets it is exactly
# what this catches.
grep -qE '^VIEWER_SHA256=[0-9a-f]{64}$' "$ROOT/bin/omarchy-setup-wsl-viewer" ||
  fail "omarchy-setup-wsl-viewer pins a sha256 for the download"
grep -qE '^VIEWER_VERSION=[0-9.]+$' "$ROOT/bin/omarchy-setup-wsl-viewer" ||
  fail "omarchy-setup-wsl-viewer pins a version"
pass "omarchy-setup-wsl-viewer pins both a version and a checksum"

# Both halves of the TurboVNC fetch are pinned: the installer, and the
# extractor that unpacks it. Neither publisher signs anything.
grep -qE '^TURBOVNC_SHA256=[0-9a-f]{64}$' "$ROOT/bin/omarchy-setup-wsl-viewer" ||
  fail "omarchy-setup-wsl-viewer pins a sha256 for TurboVNC"
grep -qE '^INNOEXTRACT_SHA256=[0-9a-f]{64}$' "$ROOT/bin/omarchy-setup-wsl-viewer" ||
  fail "omarchy-setup-wsl-viewer pins a sha256 for the extractor"
pass "omarchy-setup-wsl-viewer pins TurboVNC and its extractor"

# Running the installer would put a VNC server on the Windows machine and want
# elevation for its service. Only the viewer is taken out of it.
grep -q 'innoextract' "$ROOT/bin/omarchy-setup-wsl-viewer" ||
  fail "omarchy-setup-wsl-viewer unpacks the installer instead of running it"
pass "omarchy-setup-wsl-viewer unpacks the installer instead of running it"

# The only keyboard in the session is wayvnc's virtual one, which carries its
# own keymap, so keycode-matched bindings never fire. Without this the desktop
# has no working keybindings at all, whichever VNC client is used.
grep -q 'resolve_binds_by_sym' "$ROOT/install/wsl/hypr.sh" ||
  fail "install/wsl/hypr.sh makes Hyprland resolve keybindings by symbol"
pass "install/wsl/hypr.sh makes Hyprland resolve keybindings by symbol"

# On TurboVNC's scan-code path the right Super key arrives as the Japanese
# keypad comma and sets no modifier, so half the keyboard's bindings die.
grep -q 'noServerKeyMap' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session has the viewer send keysyms, not scan codes"
pass "omarchy-launch-wsl-session has the viewer send keysyms, not scan codes"

# Stock neatvnc never announces the screen layout at connect, so TurboVNC
# concludes the server cannot resize and disables it for the session.
[[ -f $ROOT/install/wsl/patches/neatvnc-announce-desktop-size.patch ]] ||
  fail "the neatvnc resize patch is present"
grep -q 'neatvnc-announce-desktop-size.patch' "$ROOT/install/wsl/neatvnc.sh" ||
  fail "install/wsl/neatvnc.sh applies the neatvnc resize patch"
pass "install/wsl/neatvnc.sh builds a neatvnc that announces the screen layout"

# The image build runs in a container with no Windows to write to, so the
# shortcut is the setup command's job or nobody's.
grep -q 'install_shortcut' "$ROOT/bin/omarchy-setup-wsl-viewer" ||
  fail "omarchy-setup-wsl-viewer creates the Windows desktop shortcut"
pass "omarchy-setup-wsl-viewer creates the Windows desktop shortcut"

# A headless output has no hardware cursor plane, so the compositor draws the
# cursor into the frame. TurboVNC hides its own pointer and expects exactly
# that; the TigerVNC viewers draw one of their own and would show two, so the
# compositor's is turned off for those and only those.
grep -q 'hide_compositor_cursor' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session hides the compositor cursor for the viewers that draw their own"
! grep -q 'invisible = true' "$ROOT/install/wsl/hypr.sh" ||
  fail "install/wsl/hypr.sh leaves the compositor cursor on for TurboVNC"
pass "the cursor is drawn once, whichever viewer runs"

# WSL has no sound hardware, so WSLg's PulseAudio is the only way audio leaves
# the machine. When WSLGd fails, the socket never appears and every player is
# silent with nothing on screen to say why -- which is how it went unnoticed.
grep -q 'wslg_audio_present()' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session can tell whether audio is available"
grep -q 'audio:.*wslg_audio_present' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "start-omarchy --diagnose reports audio"
pass "start-omarchy --diagnose reports whether audio is available"

# WSL has no sound card, so ALSA has nothing to open and an ALSA application
# starts, draws its interface and plays silence with no error to show for it --
# which is exactly how cliamp behaved. The pulse plugin is the route to WSLg's
# PulseAudio; on hardware pipewire-alsa does this, but pipewire's user services
# cannot run without a systemd user manager.
grep -q 'alsa-plugins' "$ROOT/install/wsl/packages.sh" ||
  fail "the WSL image installs the ALSA pulse plugin"
grep -q 'install -Dm644 /dev/stdin /etc/asound.conf' "$ROOT/install/wsl/audio.sh" ||
  fail "install/wsl/audio.sh routes ALSA somewhere"
grep -q 'pcm.!default { type pulse }' "$ROOT/install/wsl/audio.sh" ||
  fail "install/wsl/audio.sh sends ALSA to the pulse server"
grep -q 'wsl/audio.sh' "$setup_steps" ||
  fail "install/wsl/all-setup.sh runs audio.sh"
pass "ALSA applications are routed to WSLg's PulseAudio"

# The image generates no locales at all, and WSL's /init hands the Windows
# locale straight to the session -- so setlocale() fails in everything the
# desktop launches, which is how gtk-launch and foot both ended up complaining.
grep -q 'locale-gen' "$ROOT/install/wsl/locale.sh" ||
  fail "install/wsl/locale.sh generates the locales"
grep -q '/etc/locale.gen' "$ROOT/install/wsl/locale.sh" ||
  fail "install/wsl/locale.sh uncomments a locale in /etc/locale.gen"
grep -q 'en_US' "$ROOT/install/wsl/locale.sh" ||
  fail "install/wsl/locale.sh names the locale it generates"
grep -q 'wsl/locale.sh' "$image_steps" ||
  fail "install/wsl/all-image.sh runs locale.sh"
pass "the WSL image generates a locale"

# Generating one cannot cover every Windows locale, so the session must not
# pass on a LANG that resolves to nothing.
grep -q 'export LANG=C.UTF-8' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "the session falls back to a locale that exists"
pass "the session refuses to pass on an ungenerated LANG"

# "locale -a" writes en_US.UTF-8 as en_US.utf8, so a literal comparison against
# LANG never matches and the fallback would fire for a locale that is present.
locale_source=$(sed -n '/^normalized_locale()/,/^}/p' "$ROOT/bin/omarchy-launch-wsl-session")
norm() { bash -c "$locale_source"$'\n'"normalized_locale \"$1\""; }
[[ $(norm en_US.UTF-8) == "en_US.utf8" ]] ||
  fail "normalized_locale matches the spelling locale -a uses" "got: $(norm en_US.UTF-8)"
[[ $(norm C.UTF-8) == "C.utf8" ]] ||
  fail "normalized_locale handles C.UTF-8" "got: $(norm C.UTF-8)"
pass "normalized_locale matches the spelling locale -a uses"

# The desktop itself does not need WSLg running: the viewer is a Windows
# program and wayvnc serves it over the loopback. Only the mount is required,
# so this check must stay a directory test -- tightening it to demand a live
# WSLg would refuse to start a session that works perfectly well without one.
grep -A 2 '^wslg_present()' "$ROOT/bin/omarchy-launch-wsl-session" | grep -q '\[\[ -d /mnt/wslg \]\]' ||
  fail "wslg_present stays a mount check so the desktop starts without WSLg running"
pass "a dead WSLg does not stop the desktop starting"

# The viewer titles its window from the desktop name the server advertises.
# Unnamed, the one window standing in for the whole desktop is called WayVNC,
# after the transport. Nothing breaks if this regresses, which is why it is
# asserted rather than left to be noticed.
grep -q 'wayvnc --name="$VNC_DESKTOP_NAME"' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session names the VNC desktop"
grep -qE '^VNC_DESKTOP_NAME=.+' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session defines the desktop name"
pass "omarchy-launch-wsl-session names the VNC desktop"

# The title then follows focus, and the watcher has to be stopped with the
# session -- it outlives the compositor otherwise, holding a socat on a socket
# that has gone.
grep -q 'omarchy-hyprland-vnc-title-watch "$VNC_DESKTOP_NAME" &' \
  "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session starts the title watcher"
grep -q 'kill "$title_pid"' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session stops the title watcher on the way out"
pass "the title watcher is started with the session and stopped with it"

# It sets the name through wayvnc's control socket rather than restarting the
# server, which would drop the client mid-session.
grep -q 'wayvncctl set-desktop-name' "$ROOT/bin/omarchy-hyprland-vnc-title-watch" ||
  fail "the title watcher sets the name over the control socket"
# A window title is remote input: any web page chooses its own.
grep -q 'title=${title//\[\[:cntrl:\]\]/}' "$ROOT/bin/omarchy-hyprland-vnc-title-watch" ||
  fail "the title watcher strips control characters from the window title"
pass "the title watcher sets a sanitised name over the control socket"

# The name composition itself, run rather than read. Everything above the event
# loop is pure, so it can be lifted out and driven with a stubbed compositor.
title_source=$(sed -n '1,/^last_name=/p' "$ROOT/bin/omarchy-hyprland-vnc-title-watch" | sed '$d')

compose_title() {
  bash -c "
    hyprctl() { printf '%s' \"\$STUB\"; }
    $title_source
    desktop_name
  " watcher Omarchy
}

got=$(STUB='{"title":"New Tab - Chromium"}' compose_title)
[[ $got == "New Tab - Chromium — Omarchy" ]] ||
  fail "the title watcher names the focused window" "got: $got"

# No focused window: hyprctl returns null, and the desktop keeps its own name
# rather than being titled after nothing.
got=$(STUB='{}' compose_title)
[[ $got == "Omarchy" ]] ||
  fail "the title watcher falls back to the desktop name" "got: $got"

# A page that puts a newline in its title would otherwise put one on the wire.
got=$(STUB='{"title":"one\ttwo"}' compose_title)
[[ $got == "onetwo — Omarchy" ]] ||
  fail "the title watcher strips control characters" "got: $got"

# Long titles are cut rather than sent whole.
long=$(printf 'x%.0s' {1..200})
got=$(STUB="{\"title\":\"$long\"}" compose_title)
(( ${#got} < 120 )) ||
  fail "the title watcher caps the title length" "got ${#got} characters"
[[ $got == *"… — Omarchy" ]] ||
  fail "a cut title is marked as cut" "got: $got"
pass "the title watcher composes, sanitises and caps the desktop name"

# The image has no password hash, so a lock screen can never be answered. The
# idle cycle has to be off before it ever locks.
grep -q 'install -Dm644 /dev/null /etc/skel/.local/state/omarchy/indicators/stay-awake' \
  "$ROOT/install/wsl/idle.sh" ||
  fail "install/wsl/idle.sh disables idle locking, which cannot be unlocked here"
pass "install/wsl/idle.sh disables idle locking"

# omarchy-provision-first-run writes its completion marker only when every step
# succeeded, so one failing step replays the whole sequence -- and both of its
# notifications -- on every login. There is no systemd user manager here.
grep -q 'systemd/private' "$ROOT/install/user/first-run/enable-user-units.sh" ||
  fail "enable-user-units.sh skips when there is no systemd user manager"
pass "enable-user-units.sh skips when there is no systemd user manager"

# Nothing should invite the user to configure wireless on a machine with none.
grep -q 'has_wireless' "$ROOT/install/user/first-run/wifi.sh" ||
  fail "wifi.sh checks for a wireless device before offering to set one up"
pass "wifi.sh checks for a wireless device before offering to set one up"

# run_logged sources each path verbatim, so a typo here fails the whole install
# halfway through a build rather than at review time.
missing=""
while IFS= read -r leaf; do
  leaf_path="${leaf/\$OMARCHY_INSTALL/$ROOT/install}"
  [[ -f $leaf_path ]] || missing+="$leaf_path"$'\n'
done < <(sed -nE 's|^run_logged "([^"]+)"$|\1|p' <<<"$all_steps")
[[ -z $missing ]] || fail "the WSL phase lists reference only files that exist" "$missing"
pass "the WSL phase lists reference only files that exist"

# all.sh is what an in-place re-apply runs, and omarchy-apply-wsl selects a
# single phase from the same two files, so nothing may be reachable from one
# route and not the other.
for phase in all-image all-setup; do
  grep -q "wsl/$phase.sh" "$ROOT/install/wsl/all.sh" ||
    fail "install/wsl/all.sh runs both phases" "$phase"
  grep -q "wsl/$phase.sh" "$ROOT/bin/omarchy-apply-wsl" ||
    fail "omarchy-apply-wsl can select the $phase phase"
done
pass "both phases are reachable from all.sh and from omarchy-apply-wsl"

# The image ships no package databases on purpose -- an index is stale the moment
# it is downloaded -- so the setup phase has to sync before it can resolve a
# single name. Without this every package is "target not found" and the whole
# install fails at the first step, which is exactly what an imported image did.
sync_line=$(grep -n 'run_logged .*wsl/pacman-sync.sh' "$setup_steps" | cut -d: -f1)
packages_line=$(grep -n 'run_logged .*wsl/packages.sh' "$setup_steps" | cut -d: -f1)
[[ -n $sync_line && -n $packages_line ]] && (( sync_line < packages_line )) ||
  fail "the setup phase syncs the package databases before it installs anything"
grep -q 'rm -rf /var/lib/pacman/sync' "$ROOT/bin/omarchy-dev-wsl-build" ||
  fail "the build is still what empties them, which is why the sync has to exist"
pass "the setup phase syncs the databases the image deliberately does not carry"

# An image may be months old when it is imported, so its packages are too. The
# keyring has to be refreshed before anything is verified against it, and the
# image upgraded before current packages are installed alongside its old ones.
grep -q 'omarchy-update-keyring' "$ROOT/install/wsl/pacman-sync.sh" ||
  fail "the sync refreshes the keyring before downloading against it"
grep -q 'OMARCHY_UPDATE_PACMAN=1 pacman -Syu' "$ROOT/install/wsl/pacman-sync.sh" ||
  fail "the sync upgrades the image before installing alongside it"
pass "an old image refreshes its keys and upgrades itself before installing"

# The tarball is only small because the desktop is not in it. These are the
# steps that install or build it, and every one belongs to the setup phase.
for heavy in packages neatvnc; do
  grep -q "wsl/$heavy.sh" "$setup_steps" ||
    fail "install/wsl/all-setup.sh runs $heavy.sh"
  grep -q "wsl/$heavy.sh" "$image_steps" &&
    fail "install/wsl/all-image.sh does not bake $heavy.sh into the tarball"
done
pass "the package set and the neatvnc build stay out of the image"

grep -q 'omarchy-apply-wsl --first-install --image' "$ROOT/bin/omarchy-dev-wsl-build" ||
  fail "the build runs only the image phase"
pass "the build runs only the image phase"

grep -q 'omarchy-apply-wsl --first-install --setup' "$ROOT/default/wsl/oobe.sh" ||
  fail "oobe.sh runs the setup phase on the machine that imports the image"
pass "oobe.sh runs the setup phase on the machine that imports the image"

# Every bootstrap entry is something the setup screen cannot start without, so
# an entry that stopped being installed anywhere else is a mistake worth
# catching -- and each one has to come back with the full set, or an
# omarchy-apply-wsl on an installed machine would drop it.
for package in $(read_package_list "$bootstrap_packages"); do
  case $package in
    sudo) continue ;;  # a WSL-only addition in packages.sh, not the manifest
  esac
  grep -qx "$package" <(read_package_list "$base_packages") ||
    fail "the bootstrap package $package is in the base manifest too"
done
pass "every bootstrap package is installed again by the full set"

# gum draws every prompt on the setup screen and ttfx animates the logo. Lose
# either from the image and the first run has no interface at all.
for package in gum ttfx; do
  grep -qx "$package" <(read_package_list "$bootstrap_packages") ||
    fail "the image carries $package for the setup screen"
done
pass "the image carries the setup screen's gum and ttfx"

# Applied twice on purpose: before anything is installed, and again after
# install/post-install/pacman.sh restores the shipped pacman.conf over it.
grep -q 'wsl/pacman-noextract.sh' "$image_steps" ||
  fail "the image phase excludes documentation before installing anything"
noextract_line=$(grep -n 'run_logged .*wsl/pacman-noextract.sh' "$setup_steps" | cut -d: -f1)
pacman_line=$(grep -n 'run_logged .*post-install/pacman.sh' "$setup_steps" | cut -d: -f1)
[[ -n $noextract_line && -n $pacman_line ]] && (( noextract_line > pacman_line )) ||
  fail "the setup phase re-excludes documentation after post-install/pacman.sh"
pass "the NoExtract directives survive the pacman.conf restore"

# locale-gen reads its definitions from usr/share/i18n, so excluding that would
# leave the image with no generatable locale at all.
! grep '^NoExtract' "$ROOT/install/wsl/pacman-noextract.sh" | grep -q 'usr/share/i18n' ||
  fail "pacman-noextract.sh leaves usr/share/i18n alone for locale-gen"
grep -q '!usr/share/locale/en_US/\*' "$ROOT/install/wsl/pacman-noextract.sh" ||
  fail "pacman-noextract.sh keeps the locale install/wsl/locale.sh generates"
pass "the NoExtract locale rules keep what locale-gen and the session need"

# makepkg's toolchain is the better part of a gigabyte and has no use once
# neatvnc is built. The session is what would notice an over-eager prune, long
# after the build looked fine, so the step checks before it finishes.
grep -q 'omarchy_transient_packages_begin base-devel meson ninja' "$ROOT/install/wsl/neatvnc.sh" ||
  fail "install/wsl/neatvnc.sh installs the build toolchain transiently"
grep -q 'omarchy_transient_packages_end' "$ROOT/install/wsl/neatvnc.sh" ||
  fail "install/wsl/neatvnc.sh removes the build toolchain again"
grep -q 'for package in neatvnc wayvnc hyprland' "$ROOT/install/wsl/neatvnc.sh" ||
  fail "install/wsl/neatvnc.sh checks the prune did not take the session with it"
pass "the neatvnc build toolchain does not stay in the image"

# The prune arithmetic itself, run against a stubbed pacman rather than read.
# This is the piece that could quietly take the session out of the image, so the
# question is what it hands to pacman -Rns: the difference between the two
# queries, which is mostly dependencies, and nothing that was already there.
transient_dir=$(mktemp -d)
trap 'rm -rf "$transient_dir"' EXIT

cat >"$transient_dir/pacman" <<'STUB'
#!/bin/bash
case "$1" in
  -Qq)
    cat "$PACMAN_STATE"
    ;;
  -S)
    # --needed: install what is not already there, and its dependencies with it.
    for package in "$@"; do
      [[ $package == -* ]] && continue
      grep -qxF "$package" "$PACMAN_STATE" || printf '%s\n' "$package" >>"$PACMAN_STATE"
      for dependency in $(eval "printf '%s' \"\${DEPS_${package//-/_}:-}\""); do
        grep -qxF "$dependency" "$PACMAN_STATE" || printf '%s\n' "$dependency" >>"$PACMAN_STATE"
      done
    done
    ;;
  -Rns)
    shift
    for package in "$@"; do
      [[ $package == -* ]] && continue
      printf '%s\n' "$package" >>"$PACMAN_REMOVED"
      grep -vxF "$package" "$PACMAN_STATE" >"$PACMAN_STATE.new" || true
      mv "$PACMAN_STATE.new" "$PACMAN_STATE"
    done
    ;;
esac
exit 0
STUB
chmod +x "$transient_dir/pacman"

export PACMAN_STATE="$transient_dir/installed" PACMAN_REMOVED="$transient_dir/removed"
printf '%s\n' hyprland wayvnc neatvnc fakeroot glibc | sort >"$PACMAN_STATE"
: >"$PACMAN_REMOVED"

# base-devel drags in a toolchain, and fakeroot is both one of its members and
# already installed from the base manifest -- the overlap that used to make
# removing any of this awkward.
PATH="$transient_dir:$PATH" \
  DEPS_base_devel="gcc binutils make patch debugedit fakeroot" \
  DEPS_meson="python ninja" \
  bash -c '
    source "$1/install/helpers/transient-packages.sh"
    omarchy_transient_packages_begin base-devel meson ninja
    omarchy_transient_packages_end
  ' transient "$ROOT" >/dev/null

removed=$(sort -u "$PACMAN_REMOVED")

for package in base-devel meson ninja gcc binutils make patch debugedit python; do
  grep -qxF "$package" <<<"$removed" ||
    fail "the prune removes the toolchain and what it dragged in" "kept $package"
done
pass "the prune removes the toolchain and everything it dragged in"

for package in fakeroot hyprland wayvnc neatvnc glibc; do
  ! grep -qxF "$package" <<<"$removed" ||
    fail "the prune leaves what was already installed alone" "removed $package"
done
pass "the prune leaves what was already installed alone, fakeroot included"

# A step that installed nothing must remove nothing, rather than reach pacman
# -Rns with an empty argument list.
: >"$PACMAN_REMOVED"
PATH="$transient_dir:$PATH" bash -c '
  source "$1/install/helpers/transient-packages.sh"
  omarchy_transient_packages_begin hyprland
  omarchy_transient_packages_end
' transient "$ROOT" >/dev/null
[[ ! -s $PACMAN_REMOVED ]] ||
  fail "a step that installed nothing removes nothing" "$(<"$PACMAN_REMOVED")"
pass "a step that installed nothing removes nothing"

# The .ico is one file and ImageMagick is a large way to make it.
grep -q 'omarchy_transient_packages_begin imagemagick librsvg' "$ROOT/install/wsl/image.sh" ||
  fail "install/wsl/image.sh installs the icon renderer transiently"
grep -q 'omarchy_transient_packages_end' "$ROOT/install/wsl/image.sh" ||
  fail "install/wsl/image.sh removes the icon renderer again"
pass "the icon renderer does not stay in the image"

# `pacman -Scc --noconfirm` reads like it empties the cache and does not: -Scc
# asks "remove ALL files from cache? [y/N]", --noconfirm takes the default, and
# the default is no. It shipped 434 MB of packages in the image before anyone
# looked. The failure mode is silence, so the build asserts the result too.
! grep -q 'pacman -Scc' "$ROOT/bin/omarchy-dev-wsl-build" ||
  fail "the build does not clear the cache with a -Scc that answers itself no"
! grep -q 'pacman -Scc' "$ROOT/default/wsl/oobe.sh" ||
  fail "the first run does not clear the cache with a -Scc that answers itself no"
for caller in bin/omarchy-dev-wsl-build default/wsl/oobe.sh; do
  grep -q 'omarchy_clear_package_cache' "$ROOT/$caller" ||
    fail "$caller empties the package cache"
done
grep -q 'the package cache reached the image' "$ROOT/bin/omarchy-dev-wsl-build" ||
  fail "the build fails if the package cache reaches the image"
pass "the package cache is emptied, and the build checks that it was"

# The gate that keeps a regression from being noticed only when a release
# upload is rejected.
grep -q -- '--assert-max-size' "$ROOT/bin/omarchy-dev-wsl-build" ||
  fail "omarchy-dev-wsl-build can be held to a maximum image size"
grep -q -- '--assert-max-size' "$ROOT/.github/workflows/release.yml" ||
  fail "the release workflow holds the image to a maximum size"
pass "the image build is held to a size limit"

# Leaves are sourced, not executed; a shebang here is a sign the file was
# written to be run directly and will not behave the way run_logged expects.
shebanged=""
for leaf in "$ROOT"/install/wsl/*.sh; do
  if [[ $(head -n 1 "$leaf") == "#!"* ]]; then
    shebanged+="$leaf"$'\n'
  fi
done
[[ -z $shebanged ]] || fail "install/wsl leaves carry no shebang" "$shebanged"
pass "install/wsl leaves carry no shebang"

distribution_conf="$ROOT/default/wsl/wsl-distribution.conf"

# Without defaultName, `wsl --install --from-file` and double-click install both
# fail: WSL has no name to register the distribution under.
grep -qE '^defaultName = .+' "$distribution_conf" ||
  fail "wsl-distribution.conf names the distribution"
pass "wsl-distribution.conf names the distribution"

# oobe.sh creates the account at this uid; the two have to agree or the first
# shell opens as a user that does not exist.
grep -qE '^defaultUid = 1000$' "$distribution_conf" ||
  fail "wsl-distribution.conf logs in as uid 1000"
pass "wsl-distribution.conf logs in as uid 1000"

grep -qE '^DEFAULT_UID=1000$' "$ROOT/default/wsl/oobe.sh" ||
  fail "oobe.sh creates the account at uid 1000"
pass "oobe.sh creates the account at uid 1000"

# WSL refuses to open a shell at all when the OOBE command fails, so the user
# would have no way in to fix whatever went wrong. The setup phase runs before
# the account and is allowed to fail; the account is not.
grep -qE '^exit 0$' "$ROOT/default/wsl/oobe.sh" ||
  fail "oobe.sh always reports success to WSL"
pass "oobe.sh always reports success to WSL"

# WSL runs the OOBE command once. A setup that failed halfway has to be
# resumable without re-importing the image, and the marker is what says it is
# owed -- the same one omarchy-provision-owner.service gates on for hardware.
grep -q 'install -Dm644 -o root -g root /dev/null "$provisioning_dir/pending"' \
  "$ROOT/install/wsl/image.sh" ||
  fail "install/wsl/image.sh marks setup as still owed"
grep -q 'rm -f "$PROVISIONING_DIR/pending"' "$ROOT/default/wsl/oobe.sh" ||
  fail "oobe.sh clears the marker only once setup finished"
grep -q '/var/lib/omarchy/provisioning/pending' "$ROOT/default/wsl/setup-resume.sh" ||
  fail "the resume hook gates on the same marker"
grep -q '/etc/profile.d/omarchy-wsl-setup.sh' "$ROOT/install/wsl/image.sh" ||
  fail "install/wsl/image.sh installs the resume hook where login shells find it"
pass "a first run that fails halfway is resumed rather than re-imported"

grep -qE '^command = /etc/oobe.sh$' "$distribution_conf" ||
  fail "wsl-distribution.conf runs /etc/oobe.sh on first run"
pass "wsl-distribution.conf runs /etc/oobe.sh on first run"

# WSL binds the distribution to the Windows account that launched it, so the
# name here follows from there rather than being asked for.
grep -q 'cmd.exe /c "echo %USERNAME%"' "$ROOT/default/wsl/oobe.sh" ||
  fail "oobe.sh names the account after the Windows sign-in"
pass "oobe.sh names the account after the Windows sign-in"

[[ -x $ROOT/default/wsl/oobe.sh ]] ||
  fail "default/wsl/oobe.sh is executable"
pass "default/wsl/oobe.sh is executable"

# Windows Terminal silently ignores a profile template it cannot parse.
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
  "$ROOT/default/wsl/terminal-profile.json" ||
  fail "default/wsl/terminal-profile.json is valid JSON"
pass "default/wsl/terminal-profile.json is valid JSON"

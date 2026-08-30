#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_packages="$ROOT/install/omarchy-base.packages"
skip_packages="$ROOT/install/wsl/omarchy-wsl-skip.packages"

read_package_list() {
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' | sort -u
}

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
# offer it here. Without seatd running, startx cannot open /dev/dri/card0.
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

# Every application Omarchy launches goes through uwsm-app, which needs the user
# manager. Without these shims the desktop starts and can launch nothing.
for shim in uwsm-app uwsm; do
  grep -q "install -Dm755 /dev/stdin /usr/local/bin/$shim " "$ROOT/install/wsl/uwsm.sh" ||
    fail "install/wsl/uwsm.sh installs the $shim shim"
done
pass "install/wsl/uwsm.sh shims uwsm-app and uwsm"

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
done < <(sed -nE 's|^run_logged "([^"]+)"$|\1|p' "$ROOT/install/wsl/all.sh")
[[ -z $missing ]] || fail "install/wsl/all.sh references only files that exist" "$missing"
pass "install/wsl/all.sh references only files that exist"

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

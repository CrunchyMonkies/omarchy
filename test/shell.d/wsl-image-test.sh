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
grep -q 'dbus-run-session -- Hyprland' "$ROOT/bin/omarchy-launch-wsl-session" ||
  fail "omarchy-launch-wsl-session starts the compositor under its own session bus"
pass "omarchy-launch-wsl-session owns the session without systemd --user"

# Every application Omarchy launches goes through uwsm-app, which needs the user
# manager. Without these shims the desktop starts and can launch nothing.
for shim in uwsm-app uwsm; do
  grep -q "install -Dm755 /dev/stdin /usr/local/bin/$shim " "$ROOT/install/wsl/uwsm.sh" ||
    fail "install/wsl/uwsm.sh installs the $shim shim"
done
pass "install/wsl/uwsm.sh shims uwsm-app and uwsm"

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

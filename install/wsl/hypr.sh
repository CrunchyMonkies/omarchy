# The VKMS output exists to give Hyprland a device to allocate on, not to be
# looked at. wayvnc refuses to resize any output not named HEADLESS-*, and VKMS
# only offers a fixed mode list it cannot add to, so omarchy-launch-wsl-session
# drives a headless output instead and disables this one.
#
# It has to be disabled from config rather than a runtime hyprctl call, because
# hyprctl reload re-enables a monitor that was only disabled at runtime and
# Omarchy reloads on every theme change.
#
# /etc/skel is where omarchy-settings ships this file, and useradd -m copies the
# tree when the OOBE creates the user at first boot.
skel_monitors=/etc/skel/.config/hypr/monitors.lua

if [[ ! -f $skel_monitors ]]; then
  echo "Error: $skel_monitors is missing; omarchy-settings should have shipped it." >&2
  exit 1
fi

if ! grep -q 'output = "Virtual-1"' "$skel_monitors"; then
  cat >>"$skel_monitors" <<'MONITOR'

-- WSL: the desktop you see is a headless output that startx creates and wayvnc
-- resizes with the window. Virtual-1 is the VKMS device backing it, and having
-- it on as well would put a second, fixed-size monitor beside the real one.
hl.monitor({ output = "Virtual-1", disabled = true })
MONITOR
fi

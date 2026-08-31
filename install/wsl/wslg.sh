# WSLg publishes the Wayland, X11 and PulseAudio sockets under /mnt/wslg, but
# Windows only injects the matching environment into the shell it starts
# itself. Anything reached another way — wsl -d, a systemd user unit, an ssh
# command — has to be told where they are.

install -Dm644 /dev/stdin /etc/profile.d/omarchy-wslg.sh <<'PROFILE'
# Omarchy: point Wayland, X11 and audio clients at WSLg.
if [ -d /mnt/wslg ]; then
  export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}"
  export DISPLAY="${DISPLAY:-:0}"
  export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"
fi
PROFILE

# The entry point the image gives users: the desktop never starts on its own,
# and this is what brings it up. Resolve through PATH rather than linking to a
# fixed path, because the launcher lives in $OMARCHY_PATH/bin under a dev-linked
# checkout and in /usr/bin when it comes from the package.
install -Dm755 /dev/stdin /usr/local/bin/start-omarchy <<'START_OMARCHY'
#!/bin/bash

exec omarchy-launch-wsl-session "$@"
START_OMARCHY

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

# startx is what people reach for to get a desktop out of a WSL shell. There is
# no X server to start here, so hand off to the Wayland session launcher.
# xorg-xinit is not installed and /usr/local/bin precedes /usr/bin, so this
# shadows nothing. Resolve through PATH rather than linking to a fixed path:
# the launcher lives in $OMARCHY_PATH/bin under a dev-linked checkout and in
# /usr/bin when it comes from the package.
install -Dm755 /dev/stdin /usr/local/bin/startx <<'STARTX'
#!/bin/bash

exec omarchy-launch-wsl-session "$@"
STARTX

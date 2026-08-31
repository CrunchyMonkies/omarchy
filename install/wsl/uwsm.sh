# Omarchy launches every application through uwsm-app, which asks
# wayland-wm-app-daemon.service to put it in its own systemd user scope --
# o.launch() in default/hypr/helpers.lua, the menu, the shell's app library and
# some thirty commands in bin/. WSL has no working systemd user manager
# (docs/wsl.md explains why), so without these the desktop starts and then
# cannot launch anything.
#
# Shimmed rather than guarded at each call site, the same way start-omarchy
# is: WSL knowledge stays in install/wsl, and /usr/local/bin precedes
# /usr/bin so the real uwsm is shadowed without being removed.

install -Dm755 /dev/stdin /usr/local/bin/uwsm-app <<'UWSM_APP'
#!/bin/bash

# Run the command directly, since there is no user manager to hand it to.
#
# Options before the first -- only choose a unit type, which means nothing
# here. Only the first -- is consumed, so nested forms keep theirs:
# omarchy-launch-terminal runs
#   uwsm-app -- xdg-terminal-exec --app-id=org.omarchy.terminal -- $SHELL
while (($#)); do
  case "$1" in
    --)
      shift
      break
      ;;
    -*)
      shift
      ;;
    *)
      break
      ;;
  esac
done

(($#)) || exit 0

# The host GPU, for applications only. The session renders in software because
# the compositor allocates through GBM on VKMS and Mesa cannot allocate a VKMS
# buffer with the d3d12 driver -- omarchy-launch-wsl-session carries the whole
# story. An application has no such constraint: it renders into its own buffer
# and hands the compositor a finished surface.
#
# This is the point every application passes through, which is why the switch
# lives here rather than at thirty call sites. OMARCHY_WSL_GPU is set by the
# session launcher only when the GPU is actually there.
if [[ ${OMARCHY_WSL_GPU:-0} == 1 ]]; then
  unset LIBGL_ALWAYS_SOFTWARE
  export GALLIUM_DRIVER=d3d12
  # The same driver decodes video, which is what mpv and Chromium reach for.
  export LIBVA_DRIVER_NAME=d3d12
fi

# uwsm-app hands the app to a daemon and returns at once; callers rely on that,
# and one that captures output would otherwise block for the life of the app.
# The daemon puts the app's output in the journal, so systemd-cat does the same
# here -- the idiom omarchy-launch-shell already uses for the shell.
exec setsid --fork systemd-cat --identifier=uwsm-app "$@" >/dev/null 2>&1 </dev/null
UWSM_APP

install -Dm755 /dev/stdin /usr/local/bin/uwsm <<'UWSM'
#!/bin/bash

# Only the two subcommands Omarchy reaches for are answered here. Everything
# else falls through to the real uwsm, which is still installed.
case "${1:-}" in
  stop)
    # omarchy-system-logout ends the session with this. The Lua config wants the
    # dispatcher form; plain "hyprctl dispatch exit" is a syntax error under it.
    exec hyprctl dispatch 'hl.dsp.exit()'
    ;;
  app)
    # The generated desktop entry in omarchy-windows-vm uses "uwsm app --".
    shift
    exec uwsm-app "$@"
    ;;
  *)
    exec /usr/bin/uwsm "$@"
    ;;
esac
UWSM

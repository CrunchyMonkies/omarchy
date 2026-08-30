# Omarchy launches every application through uwsm-app, which asks
# wayland-wm-app-daemon.service to put it in its own systemd user scope --
# o.launch() in default/hypr/helpers.lua, the menu, the shell's app library and
# some thirty commands in bin/. WSL has no working systemd user manager
# (docs/wsl.md explains why), so without these the desktop starts and then
# cannot launch anything.
#
# Shimmed rather than guarded at each call site, the same way startx is: WSL
# knowledge stays in install/wsl, and /usr/local/bin precedes /usr/bin so the
# real uwsm is shadowed without being removed.

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
    # omarchy-system-logout ends the session with this.
    exec hyprctl dispatch exit
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

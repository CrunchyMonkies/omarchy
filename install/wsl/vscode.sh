# VS Code's own launcher refuses to start quietly inside WSL. Before doing
# anything, /usr/share/code/bin/code greps /proc/version for "Microsoft" and,
# finding it, prints a notice suggesting you install the Windows build instead
# and then blocks on "read -r YN" waiting for an answer.
#
# That stops both halves of using it here. omarchy-theme-set-vscode calls
# "code --list-extensions" with stderr discarded, so omarchy-install-editor-vscode
# stops dead after the packages land with nothing on screen to explain it; and
# code.desktop is "Exec=code %F", so launching under uwsm-app hands the prompt
# an empty stdin, which it reads as "no" and exits.
#
# DONT_PROMPT_WSL_INSTALL is the launcher's own documented escape hatch -- it
# names the variable in the message it prints.

install -Dm644 /dev/stdin /etc/profile.d/omarchy-wsl-vscode.sh <<'PROFILE'
# Omarchy: VS Code asks whether you really meant to install it inside WSL, and
# waits on stdin for an answer no caller here is in a position to give.
export DONT_PROMPT_WSL_INSTALL=1
PROFILE

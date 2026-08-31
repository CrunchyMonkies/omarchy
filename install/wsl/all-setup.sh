# The setup phase: the rest of Omarchy, run once on the user's machine by
# /etc/oobe.sh. Every step here is idempotent, because a first run that loses
# the network partway through is resumed by running the phase again rather than
# by re-importing the image.
run_logged "$OMARCHY_INSTALL/wsl/packages.sh"
run_logged "$OMARCHY_INSTALL/wsl/neatvnc.sh"
run_logged "$OMARCHY_INSTALL/config/theme-system.sh"
run_logged "$OMARCHY_INSTALL/config/browser-policy.sh"
run_logged "$OMARCHY_INSTALL/config/lockscreen-pam.sh"
run_logged "$OMARCHY_INSTALL/config/ssh-command-path.sh"
run_logged "$OMARCHY_INSTALL/config/ssh-keepalive.sh"
run_logged "$OMARCHY_INSTALL/wsl/services.sh"
run_logged "$OMARCHY_INSTALL/wsl/groups.sh"
run_logged "$OMARCHY_INSTALL/wsl/hypr.sh"
run_logged "$OMARCHY_INSTALL/wsl/idle.sh"
run_logged "$OMARCHY_INSTALL/wsl/wslg.sh"
run_logged "$OMARCHY_INSTALL/wsl/audio.sh"
run_logged "$OMARCHY_INSTALL/wsl/vscode.sh"
run_logged "$OMARCHY_INSTALL/wsl/uwsm.sh"
run_logged "$OMARCHY_INSTALL/wsl/systemd-run.sh"
run_logged "$OMARCHY_INSTALL/post-install/pacman.sh"
# After post-install/pacman.sh, which restores the shipped pacman.conf over it.
run_logged "$OMARCHY_INSTALL/wsl/pacman-noextract.sh"
run_logged "$OMARCHY_INSTALL/post-install/udev.sh"

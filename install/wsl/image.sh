# Stamp the WSL image metadata Windows reads at import time. See docs/wsl.md
# for what each file controls.

install -Dm644 -o root -g root "$OMARCHY_PATH/default/wsl/wsl.conf" /etc/wsl.conf
install -Dm644 -o root -g root "$OMARCHY_PATH/default/wsl/terminal-profile.json" \
  /usr/lib/wsl/terminal-profile.json
install -Dm755 -o root -g root "$OMARCHY_PATH/default/wsl/oobe.sh" /etc/oobe.sh

# The Start menu and Windows Terminal shortcut icon. ImageMagick renders every
# size Windows asks for into a single .ico; keep 256 first so the large tiles
# are not upscaled from a smaller frame.
magick -background none "$OMARCHY_PATH/logo.svg" \
  -define icon:auto-resize=256,128,64,48,32,16 /usr/lib/wsl/omarchy.ico
chmod 644 /usr/lib/wsl/omarchy.ico

# Written last so the [shortcut] icon it points at already exists.
install -Dm644 -o root -g root "$OMARCHY_PATH/default/wsl/wsl-distribution.conf" \
  /etc/wsl-distribution.conf

# The image ships with no password hashes in /etc/shadow — Microsoft requires
# that, and WSL authenticates the user through Windows rather than through PAM.
# So there is no password for sudo to prompt for; without this drop-in the
# first sudo in a fresh install would be unanswerable.
install -Dm440 -o root -g root /dev/stdin /etc/sudoers.d/omarchy-wsl <<'SUDOERS'
# WSL images carry no password hashes (a Microsoft requirement), so a password
# prompt here can never be satisfied. Windows owns the authentication boundary.
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
SUDOERS

visudo -cf /etc/sudoers.d/omarchy-wsl >/dev/null

# Stamp the WSL image metadata Windows reads at import time. See docs/wsl.md
# for what each file controls.
source "$OMARCHY_INSTALL/helpers/transient-packages.sh"

install -Dm644 -o root -g root "$OMARCHY_PATH/default/wsl/wsl.conf" /etc/wsl.conf
install -Dm644 -o root -g root "$OMARCHY_PATH/default/wsl/terminal-profile.json" \
  /usr/lib/wsl/terminal-profile.json
install -Dm755 -o root -g root "$OMARCHY_PATH/default/wsl/oobe.sh" /etc/oobe.sh

# The Start menu and Windows Terminal shortcut icon. ImageMagick renders every
# size Windows asks for into a single .ico; keep 256 first so the large tiles
# are not upscaled from a smaller frame.
#
# Both packages exist to produce this one file. The image carries the setup
# screen and little else, so they are installed for the render and removed
# again; the base manifest brings imagemagick back in the setup phase.
omarchy_transient_packages_begin imagemagick librsvg

magick -background none "$OMARCHY_PATH/logo.svg" \
  -define icon:auto-resize=256,128,64,48,32,16 /usr/lib/wsl/omarchy.ico
chmod 644 /usr/lib/wsl/omarchy.ico

omarchy_transient_packages_end

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

# The setup phase has not run yet: the image carries no desktop, no user and no
# configuration. This is the same marker omarchy-provision-owner.service gates
# on for a deferred-provisioning install on hardware, and /etc/oobe.sh clears it
# once setup finishes. While it is here, setup is owed.
provisioning_dir="${OMARCHY_PROVISIONING_DIR:-/var/lib/omarchy/provisioning}"
install -Dm644 -o root -g root /dev/null "$provisioning_dir/pending"

# WSL runs the OOBE command once and never again -- and /etc/oobe.sh has to exit
# 0 whatever happens, or the user gets no shell at all to fix anything from. So
# a setup that fails halfway, most likely on a network that went away, is picked
# up by the next login shell instead of needing the image re-imported.
install -Dm644 -o root -g root "$OMARCHY_PATH/default/wsl/setup-resume.sh" \
  /etc/profile.d/omarchy-wsl-setup.sh

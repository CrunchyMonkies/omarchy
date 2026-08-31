# WSL boots to the user's shell, so nothing here may pull in a graphical
# target. This is the WSL counterpart of install/config/enable-services.sh,
# which does the opposite for real hardware.

# --root=/ keeps systemctl to plain file operations on the unit tree. The build
# container has no systemd on the bus to talk to, and unlike an arch-chroot
# install systemd cannot tell it is not the real root, so without this every
# call below fails with "System has not been booted with systemd". The symlinks
# are what matter either way; they take effect on the next boot.
systemctl --root=/ set-default multi-user.target

# Hyprland reaches the VKMS device through libseat. logind is what answers on
# hardware, but it manages seats it finds on a real machine and WSL has none,
# so seatd has to be the backend here.
systemctl --root=/ enable seatd.service

# This is the only thing keeping the desktop from starting on its own. The sddm
# package is on install/wsl/omarchy-wsl-skip.packages, but the skip list can
# only decline to name a package, and the omarchy package depends on sddm -- so
# it is installed here whatever the list says. Masking the unit is what actually
# stops it, and it also covers a later pacman -S.
systemctl --root=/ mask sddm.service

# Units Microsoft documents as breaking WSL distributions. NetworkManager and
# systemd-resolved are on that list and are exactly what
# install/config/enable-services.sh enables on hardware — WSL supplies the
# interface and /etc/resolv.conf itself.
wsl_masked_units=(
  systemd-resolved.service
  systemd-networkd.service
  systemd-networkd.socket
  NetworkManager.service
  NetworkManager-wait-online.service
  systemd-tmpfiles-setup.service
  systemd-tmpfiles-setup-dev.service
  systemd-tmpfiles-setup-dev-early.service
  systemd-tmpfiles-clean.service
  systemd-tmpfiles-clean.timer
  tmp.mount
)

for unit in "${wsl_masked_units[@]}"; do
  systemctl --root=/ mask "$unit"
done

# Everything above writes symlinks and takes effect on the next boot. That was
# all this step ever needed while it ran in the build container, where there is
# no next boot to wait for -- the image had not started yet.
#
# It runs on a booted machine now: /etc/oobe.sh calls it during the first run.
# So the enable above leaves seatd enabled but not running, and startx in that
# same session finds no /run/seatd.sock, libseat has nothing to talk to and
# Hyprland dies at "CBackend::create() failed!". Telling someone their brand new
# desktop needs a restart first is not an answer, so start it here.
#
# /run/systemd/system is systemd's own marker for "I am the init system and I am
# running" -- the same condition the --root=/ above works around the absence of.
if [[ -d /run/systemd/system ]]; then
  # The unit tree changed underneath the running manager, which has no idea.
  systemctl daemon-reload

  systemctl start seatd.service

  # A masked unit already started earlier in this boot keeps running; masking
  # only stops the next start. Stop the ones that are up, so the first run
  # leaves the machine in the state a reboot would.
  for unit in sddm.service "${wsl_masked_units[@]}"; do
    if systemctl is-active --quiet "$unit"; then
      systemctl stop "$unit" || true
    fi
  done
fi

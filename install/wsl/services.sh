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

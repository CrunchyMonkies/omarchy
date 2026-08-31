# Give pacman something to install from.
#
# The image deliberately ships no package databases: bin/omarchy-dev-wsl-build
# wipes /var/lib/pacman/sync so the tarball carries no index that is stale the
# moment it is downloaded. In the build container that was fine, because the
# build had just synced. In the setup phase, on the machine that imported the
# image, nothing had -- and without this every name in install/wsl/packages.sh
# resolves to "error: target not found" and the install fails before it starts.

# The keys first. An image may be months old by the time anyone imports it, and
# an archlinux-keyring predating a maintainer key rotation cannot verify what it
# is about to download. omarchy-update-keyring is the existing command for this;
# it also syncs, but this step does not rely on that side effect.
omarchy-update-keyring

# Then upgrade what the image already carries, before installing anything new.
# Those packages are as old as the build, so installing current ones alongside
# them is the partial upgrade Arch warns about -- and an image is the one case
# where that is guaranteed rather than hypothetical.
#
# OMARCHY_UPDATE_PACMAN=1 because default/libalpm/hooks/00-omarchy-update-guard.hook
# otherwise refuses a direct -Syu, to keep people on `omarchy update`. This is
# Omarchy doing the upgrading, which is exactly what that flag is for.
env OMARCHY_UPDATE_PACMAN=1 pacman -Syu --noconfirm

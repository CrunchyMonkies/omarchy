# The image phase: everything the distributed .wsl tarball has to carry, and
# nothing else. omarchy-dev-wsl-build runs this in the container.
#
# The desktop is deliberately not here. Baking it in put the tarball past 5 GB
# gzipped -- more than a GitHub release asset may be -- so the setup phase
# downloads it on the user's machine instead, behind the first-run screen. What
# stays is what that screen needs to run at all.
run_logged "$OMARCHY_INSTALL/wsl/pacman-noextract.sh"
run_logged "$OMARCHY_INSTALL/wsl/bootstrap.sh"
run_logged "$OMARCHY_INSTALL/wsl/locale.sh"
run_logged "$OMARCHY_INSTALL/wsl/image.sh"

# The WSL install runs in two phases. omarchy-apply-wsl selects one with --image
# or --setup; with neither it runs both, which is what an in-place re-apply on an
# installed machine wants.
source "$OMARCHY_INSTALL/wsl/all-image.sh"
source "$OMARCHY_INSTALL/wsl/all-setup.sh"

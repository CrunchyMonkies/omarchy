# The packages the image carries so the first run has something to run with.
# install/wsl/packages.sh installs the rest on the user's machine.
source "$OMARCHY_INSTALL/helpers/package-list.sh"

mapfile -t packages < <(read_package_list "$OMARCHY_INSTALL/wsl/omarchy-wsl-bootstrap.packages")

if (( ${#packages[@]} == 0 )); then
  echo "Error: resolved an empty bootstrap package set" >&2
  exit 1
fi

echo "Installing ${#packages[@]} bootstrap packages"

omarchy-pkg-add "${packages[@]}"

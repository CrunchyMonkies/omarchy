# Packages a build step needs and the image should not keep.
#
# Two steps compile or render something once and have no use for the toolchain
# afterwards: install/wsl/neatvnc.sh needs makepkg's, and install/wsl/image.sh
# needs ImageMagick to turn logo.svg into a Windows .ico. Left behind, those are
# hundreds of megabytes in a tarball people download.
#
# Removal is scoped to what the install actually added, taken as the difference
# between two package queries rather than assumed from the names asked for --
# most of the weight is dependencies. pacman -Rns then drops those and any of
# their own dependencies nothing else needs, and refuses if something outside
# the set came to depend on one, which is the failure worth hearing about.

omarchy_transient_packages_begin() {
  OMARCHY_TRANSIENT_SNAPSHOT=$(mktemp)
  pacman -Qq | sort >"$OMARCHY_TRANSIENT_SNAPSHOT"
  pacman -S --needed --noconfirm "$@" >/dev/null
}

omarchy_transient_packages_end() {
  local added=()

  mapfile -t added < <(comm -13 "$OMARCHY_TRANSIENT_SNAPSHOT" <(pacman -Qq | sort))
  rm -f "$OMARCHY_TRANSIENT_SNAPSHOT"
  unset OMARCHY_TRANSIENT_SNAPSHOT

  (( ${#added[@]} )) || return 0

  echo "Removing ${#added[@]} packages installed only for this step"
  pacman -Rns --noconfirm "${added[@]}" >/dev/null
}

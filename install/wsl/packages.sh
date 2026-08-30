# Install the Omarchy package set minus what WSL cannot use. The skip list is
# subtracted from the base manifest rather than duplicating it, so a package
# added to install/omarchy-base.packages reaches WSL without a second edit.

read_package_list() {
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' | sort -u
}

base_list="$OMARCHY_INSTALL/omarchy-base.packages"
skip_list="$OMARCHY_INSTALL/wsl/omarchy-wsl-skip.packages"

mapfile -t packages < <(comm -23 <(read_package_list "$base_list") <(read_package_list "$skip_list"))

if (( ${#packages[@]} == 0 )); then
  echo "Error: resolved an empty package set from $base_list" >&2
  exit 1
fi

# WSL-only additions the base manifest has no reason to carry: on hardware the
# ISO supplies sudo and the shortcut icon is never built.
#   librsvg  - an SVG delegate for ImageMagick, so install/wsl/image.sh can
#              render the Windows shortcut icon from logo.svg
#   sudo     - the official Arch WSL rootfs ships it, but the image depends on
#              it (/etc/sudoers.d/omarchy-wsl, visudo) so name it explicitly
#   seatd    - how aquamarine opens the VKMS device. On hardware that is
#              logind's job, but WSL has no seat for logind to manage
#   wayvnc   - serves the session on 127.0.0.1, since there is no display to
#              scan out to. See omarchy-launch-wsl-session
#   tigervnc - the viewer that turns that into a WSLg window, over plain X11
packages+=(librsvg sudo seatd wayvnc tigervnc)

echo "Installing ${#packages[@]} packages ($(read_package_list "$skip_list" | wc -l) skipped as WSL-inert)"

omarchy-pkg-add "${packages[@]}"

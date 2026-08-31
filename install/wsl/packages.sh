# Install the Omarchy package set minus what WSL cannot use. The skip list is
# subtracted from the base manifest rather than duplicating it, so a package
# added to install/omarchy-base.packages reaches WSL without a second edit.
#
# This runs in the setup phase, on the user's machine, not in the image -- see
# install/wsl/all-image.sh for why.
source "$OMARCHY_INSTALL/helpers/package-list.sh"

base_list="$OMARCHY_INSTALL/omarchy-base.packages"
skip_list="$OMARCHY_INSTALL/wsl/omarchy-wsl-skip.packages"

mapfile -t packages < <(comm -23 <(read_package_list "$base_list") <(read_package_list "$skip_list"))

# The first run asked whether to include the preinstalled applications. Unlike
# the skip list this is a choice rather than a property of WSL, so it is applied
# here rather than folded into the skip list -- and omarchy-install-preinstalls
# is the way back.
if [[ ${OMARCHY_WSL_SKIP_PREINSTALLS:-0} == 1 ]]; then
  defer_list="$OMARCHY_INSTALL/wsl/omarchy-wsl-defer.packages"
  mapfile -t packages < <(comm -23 <(printf '%s\n' "${packages[@]}") <(read_package_list "$defer_list"))
fi

if (( ${#packages[@]} == 0 )); then
  echo "Error: resolved an empty package set from $base_list" >&2
  exit 1
fi

# WSL-only additions the base manifest has no reason to carry: on hardware the
# ISO supplies sudo and there is no VNC in the picture at all.
#   sudo     - absent from the official Arch WSL rootfs. Already installed by
#              install/wsl/bootstrap.sh; named again so a package set resolved
#              from this file alone is still complete
#   seatd    - how aquamarine opens the VKMS device. On hardware that is
#              logind's job, but WSL has no seat for logind to manage
#   wayvnc   - serves the session on 127.0.0.1, since there is no display to
#              scan out to. See omarchy-launch-wsl-session
#   tigervnc - the fallback viewer, used when no Windows one is installed. It
#              shows the session in a WSLg window but cannot reach the Windows
#              clipboard; omarchy-setup-wsl-viewer installs one that can
#   alsa-plugins - the ALSA pulse plugin, so ALSA applications reach WSLg's
#              PulseAudio. On hardware pipewire-alsa does this, but pipewire's
#              user services cannot run here. install/wsl/audio.sh routes to it
packages+=(sudo seatd wayvnc tigervnc alsa-plugins)

echo "Installing ${#packages[@]} packages ($(read_package_list "$skip_list" | wc -l) skipped as WSL-inert)"

omarchy-pkg-add "${packages[@]}"

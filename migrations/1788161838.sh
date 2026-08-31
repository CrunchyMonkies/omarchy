echo "Rename the WSL session entry point from startx to start-omarchy"

# install/wsl/wslg.sh now installs /usr/local/bin/start-omarchy. It used to
# install /usr/local/bin/startx, and nothing removes a shim that stopped being
# written -- so without this an upgraded image keeps both, and the old name goes
# on working when it is meant to be gone.
#
# Only the shim we wrote: it execs omarchy-launch-wsl-session and nothing else,
# so anything at that path with different contents belongs to somebody else and
# is left alone. xorg-xinit is not installed on the image, but it can be on a
# machine that is not one.
stale_shim=/usr/local/bin/startx

[[ -f $stale_shim ]] || exit 0
grep -q 'exec omarchy-launch-wsl-session' "$stale_shim" || exit 0

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# Machine-wide, so a second user on the same box finds it already done.
as_root rm -f "$stale_shim"

# The Windows shortcut still runs 'bash -lc startx'. Re-running the viewer setup
# rewrites it; say so rather than silently leaving a shortcut that no longer
# starts anything.
if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
  echo "  Run 'omarchy setup wsl viewer' to update the Omarchy Desktop shortcut."
fi

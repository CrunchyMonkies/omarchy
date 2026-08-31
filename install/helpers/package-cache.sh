# Empty pacman's package cache.
#
# Not `pacman -Scc --noconfirm`, which is what this replaced and which quietly
# does nothing: -Scc asks "Do you want to remove ALL files from cache? [y/N]",
# --noconfirm takes the default, and the default there is no. (-Sc, the other
# one, defaults to yes -- so the two read alike and behave oppositely.) The
# image shipped 434 MB of downloaded packages that way.
#
# rm rather than paccache -rk0, which would work but reaches for pacman-contrib
# to delete files this already knows the path of.
omarchy_clear_package_cache() {
  rm -rf /var/cache/pacman/pkg/*
}

# Keep documentation and other languages out of the image and off the machine.
#
# Nothing in the install path strips these afterwards, and on a full Omarchy
# package set they are a meaningful part of what a user downloads and stores:
# man pages, texinfo, /usr/share/doc, and a translation catalogue per language
# for everything that ships one. NoExtract drops them at extraction time, so a
# later pacman -Syu never puts them back either.
#
# usr/share/i18n is deliberately absent from the list -- install/wsl/locale.sh
# runs locale-gen, which reads its locale definitions and charmaps from there.
# man-db is on install/wsl/omarchy-wsl-skip.packages for the same reason this
# exists; tldr is in the base manifest and stays.
#
# Applied in both phases: the image phase writes it before anything is
# installed, and the setup phase writes it again after
# install/post-install/pacman.sh restores the shipped pacman.conf over it.

marker="# Omarchy: keep documentation and other languages out of the image"

if ! grep -qF "$marker" /etc/pacman.conf; then
  block=$(mktemp)

  # Exclusions first and the re-includes after: pacman reads the patterns in
  # order, so a ! that came first would be overridden by the * that followed it.
  cat >"$block" <<NOEXTRACT
$marker
NoExtract = usr/share/man/* usr/share/info/* usr/share/doc/* usr/share/gtk-doc/*
NoExtract = usr/share/locale/*
NoExtract = !usr/share/locale/locale.alias
NoExtract = !usr/share/locale/en/* !usr/share/locale/en_US/*
NOEXTRACT

  # Into [options], not appended: a directive after the last repository header
  # belongs to that repository and is silently ignored.
  sed -i "/^\[options\]/r $block" /etc/pacman.conf
  rm -f "$block"
fi

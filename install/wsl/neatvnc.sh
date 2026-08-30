# wayvnc's VNC library never tells a connecting client what the screen layout
# is. A client only learns the server can resize by receiving an
# ExtendedDesktopSize rect, and neatvnc sends one only when the desktop
# actually resizes or when a client asks for a resize -- while the first
# updates it does send are standalone cursor and desktop-name rects.
#
# TurboVNC decides at its first framebuffer update and never revisits it
# (CConn.java: "Disabling automatic desktop resizing because the server doesn't
# support it"), so the desktop never follows the window. TigerVNC is unaffected
# only because it assumes support optimistically.
#
# patches/neatvnc-announce-desktop-size.patch announces the layout as soon as
# the client's encodings are known, which is what the RFB spec expects. It is
# submitted upstream; this build carries it until it lands in Arch.

# The tag comes from the repository, not from what is installed: once this has
# run, the installed version carries our own pkgrel and names no upstream tag.
neatvnc_version=$(pacman -Si neatvnc | awk '/^Version/ { print $3; exit }')
neatvnc_patch="$OMARCHY_PATH/install/wsl/patches/neatvnc-announce-desktop-size.patch"
build_dir=/tmp/omarchy-neatvnc

# makepkg refuses to run as root and provisioning is root, so the build runs as
# a throwaway account that is removed again below.
build_user=omarchy-build

# base-devel is makepkg's own toolchain, not neatvnc's, so --nodeps below does
# not cover it and the base manifest does not carry it -- it lives in
# omarchy-other.packages, which the image never installs. Without it makepkg
# stops before building (no debugedit, since Arch's makepkg.conf keeps debug in
# OPTIONS) and then again inside prepare() (no patch). meson and ninja are
# neatvnc's, and base-devel does not include them.
#
# It stays in the image afterwards, as meson and ninja already did. Removing it
# would have to unpick a dependency tree that now overlaps the base manifest --
# fakeroot is in both.
pacman -S --needed --noconfirm base-devel meson ninja >/dev/null

useradd --system --create-home --home-dir /var/tmp/omarchy-build "$build_user"

rm -rf "$build_dir"
mkdir -p "$build_dir"
git clone --quiet https://gitlab.archlinux.org/archlinux/packaging/packages/neatvnc.git "$build_dir/neatvnc"
git -C "$build_dir/neatvnc" checkout --quiet "$neatvnc_version"

cp "$neatvnc_patch" "$build_dir/neatvnc/"

# Add the patch to the package source and apply it after the maintainer's own
# cherry-picks, and bump pkgrel so a plain -Syu does not silently drop it.
python3 - "$build_dir/neatvnc" <<'PYTHON'
import os, re, subprocess, sys

pkg_dir = sys.argv[1]
patch = "neatvnc-announce-desktop-size.patch"
pkgbuild = os.path.join(pkg_dir, "PKGBUILD")

digest = subprocess.run(["b2sum", os.path.join(pkg_dir, patch)],
                        capture_output=True, text=True, check=True).stdout.split()[0]

text = open(pkgbuild).read()

text, count = re.subn(r"^pkgrel=(\d+)$", lambda m: "pkgrel=%s.1" % m.group(1),
                      text, count=1, flags=re.M)
assert count == 1, "could not bump pkgrel"

text, count = re.subn(r"^(source=\((?:.|\n)*?)\)$", r"\1\n        %s)" % patch,
                      text, count=1, flags=re.M)
assert count == 1, "could not extend source()"

text, count = re.subn(r"^(b2sums=\((?:.|\n)*?)\)$", r"\1\n         '%s')" % digest,
                      text, count=1, flags=re.M)
assert count == 1, "could not extend b2sums()"

text, count = re.subn(r"^(prepare\(\) \{(?:.|\n)*?)\n\}$",
                      r'\1\n  patch -p1 < "$srcdir/%s"\n}' % patch,
                      text, count=1, flags=re.M)
assert count == 1, "could not extend prepare()"

open(pkgbuild, "w").write(text)
PYTHON

chown -R "$build_user:$build_user" "$build_dir"

# makepkg applies the patch in prepare(); a failure there fails the build, so a
# silently unpatched neatvnc cannot reach the image.
runuser -u "$build_user" -- bash -lc "cd '$build_dir/neatvnc' && makepkg -f --noconfirm --nodeps" >/dev/null

pacman -U --noconfirm "$build_dir"/neatvnc/neatvnc-*.pkg.tar.zst >/dev/null

userdel --remove "$build_user" >/dev/null 2>&1
rm -rf "$build_dir"

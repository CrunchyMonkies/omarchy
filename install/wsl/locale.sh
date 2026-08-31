# The image generates no locales at all: /etc/locale.gen ships entirely
# commented out, so only the built-in C, C.utf8 and POSIX exist. On hardware
# this never comes up because installing Arch generates them.
#
# WSL's /init hands the Windows locale straight to the processes it starts,
# and the desktop is one of them -- the shortcut runs "bash -lc start-omarchy"
# through it, so the session and every application it launches inherit
# LANG=en_US.UTF-8 or whatever Windows is set to. With no such locale here,
# setlocale() fails for all of them: gtk-launch reports "Locale not supported
# by C library", foot falls back to C.UTF-8, and anything less forgiving gets
# whatever glibc does when the locale it was told to use does not exist.
#
# Generating this one covers the common case. It cannot cover every Windows
# locale, so omarchy-launch-wsl-session also refuses to pass on a LANG that is
# not generated.

sed -i 's/^#\(en_US\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen

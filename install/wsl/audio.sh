# WSL has no sound hardware -- /dev/snd carries a timer and nothing else -- so
# ALSA has no card to open and every ALSA application fails with "cannot find
# card '0'". cliamp is one: it links libasound directly, so it starts, draws
# its interface and plays nothing, with no error anywhere the user can see.
#
# Sound leaves the machine through WSLg's PulseAudio RDP sink, which works
# (install/wsl/wslg.sh points PULSE_SERVER at it). What is missing is the route
# from ALSA to it. On hardware that comes from pipewire-alsa, in
# install/omarchy-other.packages; here pipewire's user services cannot run at
# all, since WSL has no systemd user manager, so ALSA's own pulse plugin --
# from alsa-plugins, added in install/wsl/packages.sh -- is what bridges them.

install -Dm644 /dev/stdin /etc/asound.conf <<'ASOUND'
# Omarchy: WSL has no sound card, so send ALSA to WSLg's PulseAudio server.
pcm.!default { type pulse }
ctl.!default { type pulse }
ASOUND

# Installed as /etc/profile.d/omarchy-wsl-setup.sh by install/wsl/image.sh.
#
# /etc/oobe.sh runs Omarchy's first-run setup, but WSL runs it exactly once and
# it must always exit 0, so a setup that failed partway leaves the machine with
# the marker still in place and no second chance of its own. This gives it one,
# on the next login shell that has a terminal to draw on.

if [ -f /var/lib/omarchy/provisioning/pending ] && [ -t 0 ] && [ -t 1 ]; then
  case $- in
    *i*)
      echo "Omarchy setup did not finish. Resuming it now."
      sudo /etc/oobe.sh
      ;;
  esac
fi

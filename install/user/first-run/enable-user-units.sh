#!/bin/bash

# Enable AND start the user systemd units we ship. Runs at first-run rather
# than at finalize-user time because the user manager isn't live during the
# ISO chroot — by first-run, the Hyprland/uwsm session is up and
# `systemctl --user enable --now` both writes the correct .wants symlinks
# (based on each unit's [Install]/WantedBy) and starts the services so the
# first session has bluetooth pairing, sleep lock, etc. live immediately
# instead of waiting for the next login. ConditionPath* in the unit files
# keep the enabled units inert on hardware they don't apply to.

set -euo pipefail

# Nothing to enable without a user manager to enable it in, and failing here
# would be worse than skipping: omarchy-provision-first-run writes its
# completion marker only when every step succeeded, so one failure replays the
# whole sequence -- both of its notifications included -- on every login.
user_manager_socket="${XDG_RUNTIME_DIR:-/run/user/$UID}/systemd/private"

if [[ ! -S $user_manager_socket ]]; then
  echo "No systemd user manager is running; skipping user units."
  exit 0
fi

systemctl --user daemon-reload
systemctl --user enable --now \
  bt-agent.service \
  omarchy-recover-internal-monitor.service \
  omarchy-sleep-lock.service \
  omarchy-migrate-notify.service \
  omarchy-fcitx5.service \
  omarchy-crash-watch.service

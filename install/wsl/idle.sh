# The image carries no password hash -- Microsoft requires that, which is also
# why /etc/sudoers.d/omarchy-wsl grants passwordless sudo. So the lock screen
# can never be answered: an idle lock is a session the user cannot get back
# into. omarchy-restart-shell does not rescue it either, because
# allow_session_lock_restore lets the fresh shell re-acquire the lock.
#
# The idle service has no off switch for the lock timeout on its own -- a
# timeout of 0 means lock immediately, not never -- so this seeds the marker
# omarchy-toggle-idle writes, which is what disables the idle cycle. Running
# 'omarchy toggle idle' turns it back on, and on WSL that is a way to lock
# yourself out; it is left reachable because it is the user's own choice.
install -Dm644 /dev/null /etc/skel/.local/state/omarchy/indicators/stay-awake

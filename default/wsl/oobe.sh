#!/bin/bash

# /etc/oobe.sh — WSL runs this once as root, before the first shell, on a
# freshly imported image. [oobe] defaultUid in /etc/wsl-distribution.conf is
# 1000, so this has to leave an account at uid 1000 behind.
#
# The image carries the setup screen and little else, so this is also where the
# rest of Omarchy is installed: install/wsl/all-setup.sh downloads and applies
# it, before the account exists, because those steps seed /etc/skel and record
# the groups the account is created with.
#
# omarchy-provision-wsl-owner is that screen -- the same greeter, prompts and
# progress bar the first boot on hardware draws. Everything below the call to it
# is the fallback for when it cannot run: a terminal it cannot draw on, a gum
# that is not there, a bug in it. The fallback asks nothing and installs
# everything, because the one thing that must not happen here is a user left
# with no account.
#
# WSL refuses to open a shell at all if this exits non-zero, which would leave
# the user with no way in to fix anything. So the account creation is the only
# hard requirement; everything after it is best effort and the script always
# reports success. A run that gets further than that but still fails leaves the
# pending marker in place, and /etc/profile.d/omarchy-wsl-setup.sh offers it
# again on the next login.

set -uo pipefail

DEFAULT_UID=1000
PROVISIONING_DIR=/var/lib/omarchy/provisioning

if [[ -f /etc/omarchy.conf ]]; then
  source /etc/omarchy.conf
fi
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
export PATH="$OMARCHY_PATH/bin:$PATH"

# Setup finished on an earlier run. WSL re-runs the OOBE command after some
# upgrades, and the resume hook calls this directly, so this is the guard both
# of them land on.
if [[ ! -f $PROVISIONING_DIR/pending ]]; then
  exit 0
fi

# Supplementary groups recorded by omarchy-apply-wsl's scripts, filtered to
# groups that actually exist. Mirrors user_groups() in omarchy-provision-owner,
# including its refusal to grant the root-equivalent docker group at first run.
user_groups() {
  local groups="wheel" group
  if [[ -f $PROVISIONING_DIR/groups ]]; then
    while IFS= read -r group; do
      [[ -n $group ]] || continue
      [[ $group == "docker" ]] && continue
      getent group "$group" >/dev/null || continue
      [[ ",$groups," == *",$group,"* ]] || groups+=",$group"
    done <"$PROVISIONING_DIR/groups"
  fi
  echo "$groups"
}

if omarchy-provision-wsl-owner; then
  exit 0
fi

# ── Fallback ─────────────────────────────────────────────────────────────────

echo "Continuing without the setup screen." >&2
echo >&2

if [[ -f $OMARCHY_PATH/logo.txt ]]; then
  cat "$OMARCHY_PATH/logo.txt"
  echo
fi

# The desktop, the tools and the configuration, none of which the image carries.
# Every step is idempotent, so a resumed run costs a re-check rather than a
# reinstall. Failing here is not fatal: the account below still gets made, so
# the user has a shell to retry from.
echo "Installing Omarchy. This downloads several gigabytes and takes a while."
echo

if omarchy-apply-wsl --first-install --setup; then
  setup_applied=1
else
  setup_applied=0
  echo "Warning: Omarchy setup did not complete." >&2
fi

# WSL ties the distribution to whoever is signed in to Windows, so the account
# here is named after that one rather than asked for. Interop is enabled in
# /etc/wsl.conf and this runs before any shell, so cmd.exe is what can answer;
# it prints a warning about the UNC working directory first, hence the tail.
#
# Windows allows names useradd will not: spaces, capitals, apostrophes,
# accents. Only the obvious mappings are made here -- case folded, spaces and
# dots to hyphens. Anything else falls through to the prompt, because silently
# stripping letters would name the account something the user never chose
# ("Ünïcode" is not "ncode").
windows_username() {
  local raw name

  raw=$(/mnt/c/Windows/System32/cmd.exe /c "echo %USERNAME%" 2>/dev/null | tail -1 | tr -d '\r\n')
  [[ $raw =~ ^[A-Za-z0-9\ ._-]+$ ]] || return 1

  name=${raw,,}
  name=${name//[ .]/-}

  [[ $name =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1

  echo "$name"
}

# A resumed run finds the account already there and picks up after it.
if getent passwd "$DEFAULT_UID" >/dev/null; then
  username=$(getent passwd "$DEFAULT_UID" | cut -d: -f1)
else
  username=$(windows_username) || username=""

  if [[ -n $username ]] && getent passwd "$username" >/dev/null; then
    username=""
  fi

  if [[ -n $username ]]; then
    echo "Creating your Omarchy user account as $username, to match your Windows sign-in."
    echo
  else
    echo "Creating your Omarchy user account."
    echo

    # useradd's own rules: start with a letter or underscore, then letters, digits,
    # underscores or hyphens. Reject anything it would reject, with a message.
    while [[ -z $username ]]; do
      read -rp "Enter a UNIX username: " username

      if [[ ! $username =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Invalid username. Use lowercase letters, digits, - and _, starting with a letter." >&2
        username=""
      elif getent passwd "$username" >/dev/null; then
        echo "That user already exists." >&2
        username=""
      fi
    done
  fi

  # No password is set. The image ships with no hashes in /etc/shadow (Microsoft
  # requires that), Windows owns the login boundary, and
  # /etc/sudoers.d/omarchy-wsl grants %wheel passwordless sudo to match.
  if ! useradd --uid "$DEFAULT_UID" --create-home --user-group \
       --groups "$(user_groups)" --shell /bin/bash "$username"; then
    echo "Error: failed to create user '$username'." >&2
    echo "Run 'wsl --terminate Omarchy' and start the distribution again to retry." >&2
    exit 1
  fi
fi

echo
echo "Finalizing Omarchy for $username..."

# The per-user setup /etc/skel cannot seed: xdg dirs, default browser, theme
# links, install/user/all.sh. Losing it is recoverable — the user can rerun
# 'omarchy-provision-user --force' — so it must not block the first shell.
#
# OMARCHY_SETUP_CONTEXT has to be named. Without it omarchy-provision-user
# assumes an ISO chroot, and install/user/mise-work.sh then looks for a bundled
# Node tarball in /opt/packages -- a path only the ISO has -- and fails the whole
# finalization. Any context that is not the ISO's or the hardware provisioner's
# sends it to the network for Node instead, which is what WSL wants.
if runuser -l "$username" -c \
   'OMARCHY_SETUP_CONTEXT=provision-wsl-owner omarchy-provision-user --first-install'; then
  user_provisioned=1
else
  user_provisioned=0
  echo "Warning: user finalization did not complete." >&2
  echo "Run 'omarchy-provision-user --force' once you are logged in." >&2
fi

# Several gigabytes of downloaded packages, of no further use once installed.
source "$OMARCHY_PATH/install/helpers/package-cache.sh"
omarchy_clear_package_cache

if (( setup_applied && user_provisioned )); then
  rm -f "$PROVISIONING_DIR/pending"

  cat <<'NOTE'

Omarchy is ready.

The desktop does not start on its own here. Run `start-omarchy` to bring up the
Hyprland session in a WSLg window, or just use the CLI from this shell.

NOTE
else
  cat <<'NOTE'

Omarchy setup did not finish. Open a new shell and it will offer to pick up
where it left off, or run `sudo /etc/oobe.sh` yourself. The log is at
/var/log/omarchy-install.log.

NOTE
fi

exit 0

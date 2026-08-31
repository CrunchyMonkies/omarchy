#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

owner="$ROOT/bin/omarchy-provision-wsl-owner"
oobe="$ROOT/default/wsl/oobe.sh"
defer_packages="$ROOT/install/wsl/omarchy-wsl-defer.packages"

source "$ROOT/install/helpers/package-list.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# The account is the one thing that must exist when WSL opens the first shell,
# so the branded screen is offered and never depended on. A terminal it cannot
# draw on, a gum that is not installed, or a bug in it all land on the same
# fallback.
grep -q '^if omarchy-provision-wsl-owner; then$' "$oobe" ||
  fail "oobe.sh runs the setup screen"
grep -q 'needs a terminal to draw on' "$owner" ||
  fail "the setup screen refuses a terminal it cannot draw on rather than spinning"
grep -q 'read -rp "Enter a UNIX username: "' "$oobe" ||
  fail "oobe.sh still carries the fallback that asks for a name itself"
grep -q 'omarchy-apply-wsl --first-install --setup' "$oobe" ||
  fail "the fallback still installs Omarchy"
grep -qE '^exit 0$' "$oobe" ||
  fail "oobe.sh always reports success to WSL"
pass "the branded screen is offered, and oobe.sh still finishes without it"

# WSL authenticates through Windows and the image carries no /etc/shadow hashes,
# so a password prompt here could never be satisfied.
! grep -q 'omarchy_prompt_password' "$owner" ||
  fail "the WSL setup screen asks for no password"
# WSL names the distribution and syncs the clock from the host.
for prompt in omarchy_prompt_hostname omarchy_prompt_timezone; do
  ! grep -q "$prompt" "$owner" || fail "the WSL setup screen does not ask for $prompt"
done
# The viewer sends keysyms, already resolved by the Windows layout, and wayvnc's
# virtual keyboard carries its own keymap -- which is why install/wsl/hypr.sh
# resolves bindings by symbol. A layout asked for here would apply a second one.
! grep -q 'omarchy_prompt_keyboard' "$owner" ||
  fail "the WSL setup screen does not ask for a keyboard layout Windows already applied"
pass "the WSL setup screen skips what WSL owns or does not have"

# What it does ask.
grep -q 'omarchy_prompt_username' "$owner" || fail "the setup screen asks for the username"
grep -q 'omarchy_prompt_identity' "$owner" || fail "the setup screen asks for the git identity"
grep -q 'OMARCHY_USERNAME_DEFAULT=$(windows_username)' "$owner" ||
  fail "the username field starts on the Windows sign-in name"
grep -q 'cmd.exe /c "echo %USERNAME%"' "$owner" ||
  fail "the setup screen reads the Windows sign-in name"
pass "the setup screen asks for the account and prefills it from Windows"

# Both extra questions are about the size of the first download, which is the
# whole cost of a first run on a machine where nothing is installed yet.
grep -q 'OMARCHY_WSL_SKIP_PREINSTALLS' "$owner" ||
  fail "declining the preinstalled applications reaches the package step"
grep -q 'OMARCHY_WSL_SKIP_PREINSTALLS' "$ROOT/install/wsl/packages.sh" ||
  fail "install/wsl/packages.sh honours the answer"
grep -q 'OMARCHY_SKIP_AGENT_CLIS' "$owner" ||
  fail "declining the agent CLIs reaches the user setup"
grep -q 'OMARCHY_SKIP_AGENT_CLIS' "$ROOT/install/user/mise.sh" ||
  fail "install/user/mise.sh honours the answer"
pass "both install questions reach the steps that answer them"

# Neither answer may be a dead end: each names a command that undoes it, and
# each of those has to exist and be routable.
for command in omarchy-install-preinstalls omarchy-install-agent-clis; do
  [[ -x $ROOT/bin/$command ]] || fail "$command exists so the answer can be changed later"
  grep -q "$command" "$owner" || fail "the setup screen names $command"
done
grep -q 'unset OMARCHY_SKIP_AGENT_CLIS' "$ROOT/bin/omarchy-install-agent-clis" ||
  fail "omarchy-install-agent-clis is not stopped by the opt-out it undoes"
pass "each declined answer names the command that changes it"

# omarchy-install-preinstalls reinstalls exactly what omarchy-remove-preinstalls
# drops, so the deferred list has to be that same set or the way back is partial.
removed=$(sed -n '/omarchy-pkg-drop/,/^fi$/p' "$ROOT/bin/omarchy-remove-preinstalls" |
  sed -e 's/omarchy-pkg-drop//' -e 's/\\//' -e 's/[[:space:]]//g' |
  grep -vE '^$|^fi$|^then$')
deferred=$(read_package_list "$defer_packages")

difference=$(comm -3 <(printf '%s\n' "$removed" | sort -u) <(printf '%s\n' "$deferred"))
[[ -z $difference ]] ||
  fail "the deferred list matches what omarchy-remove-preinstalls drops" "$difference"
pass "the deferred applications are exactly the ones the existing opt-out covers"

# Every deferred package has to be in the base manifest, or subtracting it does
# nothing and the answer silently means less than it says.
unknown=$(comm -23 <(printf '%s\n' "$deferred") \
  <(read_package_list "$ROOT/install/omarchy-base.packages"))
[[ -z $unknown ]] || fail "every deferred package exists in the base manifest" "$unknown"
pass "every deferred package exists in the base manifest"

# The web apps and TUI wrappers are Omarchy's own launchers rather than
# packages, so subtracting the list does not remove them -- and the marker that
# turns their keybindings and menu entries off is the same one
# omarchy-remove-preinstalls writes.
grep -q 'omarchy-webapp-remove-all' "$owner" ||
  fail "declining the preinstalls also drops the web app launchers"
grep -q 'omarchy-tui-remove-all' "$owner" ||
  fail "declining the preinstalls also drops the TUI wrappers"
grep -q 'preinstalls-removed' "$owner" ||
  fail "declining the preinstalls writes the marker the bindings and menu read"
grep -q 'preinstalls-removed' "$ROOT/default/hypr/helpers.lua" ||
  fail "the marker is what the keybindings read"
pass "declining the preinstalls leaves no launcher for something that is not there"

# The same -Scc that answered itself no in the build would answer itself no
# here, over a cache several times the size.
! grep -q 'pacman -Scc' "$owner" ||
  fail "the setup screen does not clear the cache with a -Scc that answers itself no"
grep -q 'omarchy_clear_package_cache' "$owner" ||
  fail "the setup screen empties the package cache it filled"
pass "the setup screen empties the package cache it filled"

# The progress bands cover the phases run_provisioning actually announces, and
# nothing else -- a phase with no band falls to the catch-all and the bar stalls.
phases=$(sed -n 's/^  echo \([a-z]*\) >"$STATE_FILE"$/\1/p' "$owner" | sort -u)
for phase in $phases; do
  grep -qE "^    $phase\)" "$owner" ||
    fail "the progress bands cover the $phase phase"
done
[[ -n $phases ]] || fail "run_provisioning announces its phases"
pass "every announced phase has a progress band"

# The bands themselves, run rather than read: monotonic, inside the phase, and
# never arriving before the work does.
band_probe() {
  OMARCHY_PATH="$ROOT" bash -c '
    source "$1/install/provisioning/setup-ui.sh"
    owner=$1/bin/omarchy-provision-wsl-owner
    eval "$(sed -n "/^phase_band()/,/^}$/p" "$owner")"
    eval "$(sed -n "/^setup_progress()/,/^}$/p" "$owner")"
    SETUP_PHASE="" SETUP_PHASE_T0=0 PHASE_BASE=-1
    SETUP_TOTAL=19 FINALIZE_TOTAL=12
    STATE_FILE=$2 LOG_FILE=/dev/null
    for t in 0 5 30 120 600; do
      NOW=$t
      setup_progress
      printf "%s " "$SETUP_POS"
    done
  ' band "$ROOT" "$1"
}

printf 'setup' >"$tmp_dir/state"
read -r -a positions <<<"$(band_probe "$tmp_dir/state")"

previous=0
for position in "${positions[@]}"; do
  (( position >= previous )) || fail "the bar never goes backwards" "${positions[*]}"
  previous=$position
done
(( positions[0] >= 10 )) || fail "the bar starts inside the first band" "${positions[*]}"
(( positions[-1] < 700 )) ||
  fail "time alone never carries the bar past the phase it is in" "${positions[*]}"
(( positions[-1] > positions[0] )) || fail "the bar moves while it waits" "${positions[*]}"
pass "the bar moves, never backwards, and never past the phase it is in"

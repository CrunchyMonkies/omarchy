#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

base_packages="$ROOT/install/omarchy-base.packages"
skip_packages="$ROOT/install/wsl/omarchy-wsl-skip.packages"

read_package_list() {
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$1" | grep -v '^$' | sort -u
}

# A skip entry that no longer names a real package is dead weight that silently
# stops protecting anything, so hold the list to the manifest it subtracts from.
unknown=$(comm -23 <(read_package_list "$skip_packages") <(read_package_list "$base_packages"))
[[ -z $unknown ]] || fail "every WSL skip entry exists in the base package list" "$unknown"
pass "every WSL skip entry exists in the base package list"

# The one requirement the whole image rests on: nothing may start the desktop
# on its own. sddm is the only thing that ever does.
grep -qx sddm <(read_package_list "$skip_packages") ||
  fail "the WSL image drops sddm so the desktop cannot auto-start"
pass "the WSL image drops sddm so the desktop cannot auto-start"

grep -q 'systemctl --root=/ mask sddm.service' "$ROOT/install/wsl/services.sh" ||
  fail "install/wsl/services.sh masks sddm.service"
pass "install/wsl/services.sh masks sddm.service"

grep -q 'systemctl --root=/ set-default multi-user.target' "$ROOT/install/wsl/services.sh" ||
  fail "install/wsl/services.sh boots to multi-user.target"
pass "install/wsl/services.sh boots to multi-user.target"

# run_logged sources each path verbatim, so a typo here fails the whole install
# halfway through a build rather than at review time.
missing=""
while IFS= read -r leaf; do
  leaf_path="${leaf/\$OMARCHY_INSTALL/$ROOT/install}"
  [[ -f $leaf_path ]] || missing+="$leaf_path"$'\n'
done < <(sed -nE 's|^run_logged "([^"]+)"$|\1|p' "$ROOT/install/wsl/all.sh")
[[ -z $missing ]] || fail "install/wsl/all.sh references only files that exist" "$missing"
pass "install/wsl/all.sh references only files that exist"

# Leaves are sourced, not executed; a shebang here is a sign the file was
# written to be run directly and will not behave the way run_logged expects.
shebanged=""
for leaf in "$ROOT"/install/wsl/*.sh; do
  if [[ $(head -n 1 "$leaf") == "#!"* ]]; then
    shebanged+="$leaf"$'\n'
  fi
done
[[ -z $shebanged ]] || fail "install/wsl leaves carry no shebang" "$shebanged"
pass "install/wsl leaves carry no shebang"

distribution_conf="$ROOT/default/wsl/wsl-distribution.conf"

# Without defaultName, `wsl --install --from-file` and double-click install both
# fail: WSL has no name to register the distribution under.
grep -qE '^defaultName = .+' "$distribution_conf" ||
  fail "wsl-distribution.conf names the distribution"
pass "wsl-distribution.conf names the distribution"

# oobe.sh creates the account at this uid; the two have to agree or the first
# shell opens as a user that does not exist.
grep -qE '^defaultUid = 1000$' "$distribution_conf" ||
  fail "wsl-distribution.conf logs in as uid 1000"
pass "wsl-distribution.conf logs in as uid 1000"

grep -qE '^DEFAULT_UID=1000$' "$ROOT/default/wsl/oobe.sh" ||
  fail "oobe.sh creates the account at uid 1000"
pass "oobe.sh creates the account at uid 1000"

grep -qE '^command = /etc/oobe.sh$' "$distribution_conf" ||
  fail "wsl-distribution.conf runs /etc/oobe.sh on first run"
pass "wsl-distribution.conf runs /etc/oobe.sh on first run"

[[ -x $ROOT/default/wsl/oobe.sh ]] ||
  fail "default/wsl/oobe.sh is executable"
pass "default/wsl/oobe.sh is executable"

# Windows Terminal silently ignores a profile template it cannot parse.
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' \
  "$ROOT/default/wsl/terminal-profile.json" ||
  fail "default/wsl/terminal-profile.json is valid JSON"
pass "default/wsl/terminal-profile.json is valid JSON"

# Group membership the session needs to reach the VKMS device: seat to talk to
# seatd, video and render for the DRM node itself. Recorded for provisioning
# first-boot user creation and factory reset, granted directly when the install
# user already exists (the WSL image creates its user at first boot instead).
provisioning_dir="${OMARCHY_PROVISIONING_DIR:-/var/lib/omarchy/provisioning}"
mkdir -p "$provisioning_dir"

wsl_session_groups=(seat video render)

for group in "${wsl_session_groups[@]}"; do
  grep -qxF "$group" "$provisioning_dir/groups" 2>/dev/null || echo "$group" >>"$provisioning_dir/groups"

  if [[ -n ${OMARCHY_INSTALL_USER:-} ]] && getent passwd "$OMARCHY_INSTALL_USER" >/dev/null; then
    usermod -aG "$group" "$OMARCHY_INSTALL_USER"
  fi
done

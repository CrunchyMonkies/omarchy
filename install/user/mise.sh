# The agent CLIs. Each one is a download, and together they are the longest part
# of a first run -- so the WSL first-run screen offers to skip them, and
# omarchy-install-agent-clis is how they arrive later.
if [[ ${OMARCHY_SKIP_AGENT_CLIS:-0} == 1 ]]; then
  echo "Skipping the agent CLIs; run omarchy-install-agent-clis to install them."
  return 0 2>/dev/null || exit 0
fi

omarchy-mise-install codex
omarchy-mise-install claude
omarchy-mise-install crush
omarchy-mise-install antigravity-cli agy
omarchy-mise-install gh
omarchy-mise-install copilot
omarchy-mise-install opencode
omarchy-mise-install npm:playwright playwright
omarchy-mise-install pi
omarchy-mise-install github:can1357/oh-my-pi omp
omarchy-mise-install npm:@xai-official/grok grok
omarchy-mise-install npm:@kitlangton/ghui ghui
omarchy-mise-install aqua:modem-dev/hunk hunk
omarchy-mise-install github:basecamp/hey-cli hey
omarchy-mise-install github:OpenRouterLabs/ori-releases ori

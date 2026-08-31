#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

ui="$ROOT/install/provisioning/setup-ui.sh"
owner="$ROOT/bin/omarchy-provision-owner"
wsl_owner="$ROOT/bin/omarchy-provision-wsl-owner"

# The library exists so both first runs draw the same screen rather than one
# resembling the other. A function that drifted back into a caller is how they
# would start to diverge again.
shared=(
  measure_terminal clear_logo step say notice
  term_cols term_size console_signature wait_console_stable
  repeat left_padding visible_len blank_line line_at center
  render_logo progress_bar set_now current_tip
  measure_setup_layout render_setup_static render_setup_dynamic greeter_screen
)

for name in "${shared[@]}"; do
  grep -q "^$name()" "$ui" || fail "setup-ui.sh defines $name"
  grep -q "^$name()" "$owner" && fail "omarchy-provision-owner takes $name from setup-ui.sh"
  grep -q "^$name()" "$wsl_owner" && fail "omarchy-provision-wsl-owner takes $name from setup-ui.sh"
done
pass "the shared screen is defined once, in setup-ui.sh"

# Both callers have to actually source it, and setup-form.sh alongside it: the
# form calls notice(), which is the library's.
for caller in "$owner" "$wsl_owner"; do
  grep -q 'install/provisioning/setup-ui.sh' "$caller" ||
    fail "$(basename "$caller") sources setup-ui.sh"
  grep -q 'install/provisioning/setup-form.sh' "$caller" ||
    fail "$(basename "$caller") sources setup-form.sh"
done
pass "both first runs source the shared screen and the shared form"

# Console font fitting reads /sys/class/graphics and calls setfont. It belongs
# to the framebuffer console, not to a terminal emulator, so the library's is a
# no-op the machine setup overrides.
grep -q '^scale_console_font() { :; }$' "$ui" ||
  fail "setup-ui.sh defaults scale_console_font to nothing"
grep -q '^scale_console_font() {$' "$owner" ||
  fail "omarchy-provision-owner overrides scale_console_font for the console"
! grep -q 'scale_console_font() {$' "$wsl_owner" ||
  fail "omarchy-provision-wsl-owner leaves the console font alone"
grep -q '^set_tokyo_night_colors() {$' "$owner" ||
  fail "the VT palette stays with the console caller"
! grep -q 'set_tokyo_night_colors' "$ui" ||
  fail "setup-ui.sh leaves the VT palette to the console caller"
pass "console-only work stays with the console caller"

# render_setup_dynamic calls setup_progress every frame. Each caller measures
# progress against its own phases, so the library only guarantees one exists.
grep -q '^setup_progress() {$' "$ui" || fail "setup-ui.sh defaults setup_progress"
for caller in "$owner" "$wsl_owner"; do
  grep -q '^setup_progress() {$' "$caller" ||
    fail "$(basename "$caller") measures progress against its own phases"
  grep -q '^phase_band() {$' "$caller" ||
    fail "$(basename "$caller") defines its own phase bands"
done
pass "each first run measures progress against its own phases"

# The bar itself, run rather than read: 34 cells, clamped at both ends, and
# filled in proportion. It is the one piece of the screen with arithmetic in it.
render_bar() {
  OMARCHY_PATH="$ROOT" bash -c '
    source "$1/install/provisioning/setup-ui.sh"
    progress_bar "$2" 34
  ' bar "$ROOT" "$1" | sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g'
}

for probe in "0 0" "250 8" "500 17" "1000 34" "-5 0" "5000 34"; do
  set -- $probe
  bar=$(render_bar "$1")
  filled=${bar//░/}
  (( ${#bar} == 34 )) || fail "the progress bar is 34 cells wide" "$1 gave ${#bar}"
  (( ${#filled} == $2 )) ||
    fail "the progress bar fills in proportion" "$1 filled ${#filled}, expected $2"
done
pass "the progress bar is 34 cells, clamped at both ends and filled in proportion"

# One tip per eight seconds, cycling. A caller may replace the list; the
# arithmetic that walks it is the library's.
tip_at() {
  OMARCHY_PATH="$ROOT" bash -c '
    source "$1/install/provisioning/setup-ui.sh"
    tips=(alpha beta gamma)
    SETUP_T0=0
    NOW=$2
    current_tip
  ' tip "$ROOT" "$1"
}

[[ $(tip_at 0) == alpha ]] || fail "the first tip shows first" "got: $(tip_at 0)"
[[ $(tip_at 7) == alpha ]] || fail "a tip holds for eight seconds" "got: $(tip_at 7)"
[[ $(tip_at 8) == beta ]] || fail "the tip changes after eight seconds" "got: $(tip_at 8)"
[[ $(tip_at 24) == alpha ]] || fail "the tips cycle" "got: $(tip_at 24)"
pass "one tip per eight seconds, cycling"

# visible_len is what centers a line carrying colour. Counting the escape bytes
# would push every coloured line off-center.
measure() {
  OMARCHY_PATH="$ROOT" bash -c '
    source "$1/install/provisioning/setup-ui.sh"
    visible_len "$2"
  ' measure "$ROOT" "$1"
}

[[ $(measure "plain") == 5 ]] || fail "visible_len counts plain text" "got: $(measure "plain")"
[[ $(measure '\033[32mplain\033[0m') == 5 ]] ||
  fail "visible_len ignores colour" "got: $(measure '\033[32mplain\033[0m')"
pass "visible_len measures what is on screen, not what was written"

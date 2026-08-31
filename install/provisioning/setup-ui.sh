# The first-boot presentation layer: the logo header, the gum chrome the setup
# form draws into, the animated greeter, and the progress screen.
#
# Sourced by bin/omarchy-provision-owner, which is where all of it started, and
# by bin/omarchy-provision-wsl-owner. install/provisioning/setup-form.sh is the
# same arrangement for the questions themselves, and the two are meant to be
# sourced together: setup-form.sh calls notice(), which is defined here.
#
# Two things are the caller's, because they differ between a machine being set
# up and an image being finished:
#
#   scale_console_font  the greeter calls it before painting. Console-only, so
#                       the default here does nothing and
#                       omarchy-provision-owner overrides it.
#   setup_progress      render_setup_dynamic calls it to move SETUP_POS. The
#                       default is a time-only asymptote; a caller that can
#                       count real work overrides it.
#
# A caller may also replace the tips array.

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

LOGO_PATH="$OMARCHY_PATH/logo.txt"
LOGO_WIDTH=$(awk '{ if (length > max) max = length } END { print max+0 }' "$LOGO_PATH" 2>/dev/null || echo 0)
LOGO_HEIGHT=$(wc -l <"$LOGO_PATH" 2>/dev/null || echo 0)
(( LOGO_WIDTH > 0 )) || LOGO_WIDTH=81
(( LOGO_HEIGHT > 0 )) || LOGO_HEIGHT=1

export GUM_CONFIRM_PROMPT_FOREGROUND="6"
export GUM_CONFIRM_SELECTED_FOREGROUND="0"
export GUM_CONFIRM_SELECTED_BACKGROUND="2"
export GUM_CONFIRM_UNSELECTED_FOREGROUND="7"
export GUM_CONFIRM_UNSELECTED_BACKGROUND="0"

measure_terminal() {
  TERM_WIDTH=$(stty size 2>/dev/null </dev/tty | awk '{print $2}')
  (( TERM_WIDTH > 0 )) || TERM_WIDTH=${COLUMNS:-80}

  PADDING_LEFT=$(((TERM_WIDTH - LOGO_WIDTH) / 2))
  (( PADDING_LEFT < 0 )) && PADDING_LEFT=0
  PADDING_LEFT_SPACES=$(printf "%*s" "$PADDING_LEFT" "")

  local padding="0 0 0 $PADDING_LEFT"
  export GUM_CHOOSE_PADDING="$padding"
  export GUM_FILTER_PADDING="$padding"
  export GUM_INPUT_PADDING="$padding"
  export GUM_SPIN_PADDING="$padding"
  export GUM_TABLE_PADDING="$padding"
  export GUM_CONFIRM_PADDING="$padding"
}

clear_logo() {
  measure_terminal
  printf "\033[H\033[2J"
  gum style --foreground 2 --padding "1 0 0 $PADDING_LEFT" "$(<"$LOGO_PATH")"
}

step() {
  clear_logo
  echo
  gum style --padding "0 0 0 $PADDING_LEFT" "$1"
  echo
}

say() {
  gum style --padding "0 0 0 $PADDING_LEFT" "$@"
}

notice() {
  clear_logo
  echo
  printf '%*s\033[32m● \033[0m%s\n' "$PADDING_LEFT" '' "$1"
  sleep "${2:-2}"
  echo
}

# ── Setup progress screen ────────────────────────────────────────────────────
#
# A port of the ISO install dashboard's renderer, so first-boot account setup
# looks like a continuation of the install: same logo header, same 34-cell
# bar, same rotating tips. Position = max(floor, work) in
# per-mille, monotonic; the floor is asymptotic per phase band and the work
# signal counts finalize-user's run_logged scripts in the log.

CSI=$'\033['
RESET="${CSI}0m"
DIM="${CSI}2m"
HIDE_CURSOR="${CSI}?25l"
SHOW_CURSOR="${CSI}?25h"
CLEAR="${CSI}2J${CSI}H"
CLEAR_LINE="${CSI}2K"
CLEAR_TO_END="${CSI}J"
GREEN="${CSI}32m"
WHITE="${CSI}37m"
DARK="${CSI}90m"

SETUP_HEIGHT=$((LOGO_HEIGHT + 6))
SETUP_TOP_ROW=1
DYNAMIC_ROW=$((LOGO_HEIGHT + 3))
LAST_SETUP_SIZE=""

tips=(
  "Super + Space opens the Omarchy menu for apps, settings, and more"
  "Super + K shows all the key bindings"
  "Super is the Windows or command key on your keyboard"
  "Use Xournal++ to sign PDFs"
  "Share files with phones and laptops using LocalSend"
  "Turn any website into an app with Install > Web App in the menu"
  "Super + Return opens a terminal, Super + Shift + Return the browser"
  "Edit images with Pinta, videos with Kdenlive, docs with LibreOffice"
  "Super + Ctrl + Print grabs text off the screen with OCR"
  "Print takes a screenshot, Alt + Print records the screen"
  "Set a reminder with Super + Ctrl + R"
  "Switch themes from Style > Theme in the Omarchy menu"
  "Double-click the menu bar to make it transparent"
  "Run a full Windows VM via Install > Windows in the menu"
  "Super + Ctrl + V opens the clipboard manager"
  "Super + 1 through 0 switches workspaces, add Shift to bring the window"
  "Super + Print picks a color from anywhere on screen"
  "Keep the system fresh with Update in the Omarchy menu"
)

term_cols() {
  local cols
  cols=$(stty size 2>/dev/null </dev/tty | awk '{print $2}')
  [[ $cols =~ ^[0-9]+$ ]] && (( cols > 0 )) || cols=${COLUMNS:-80}
  printf '%s' "$cols"
}

term_size() { stty size 2>/dev/null </dev/tty || printf '24 80\n'; }

# A fingerprint of the console geometry: the VT size plus the framebuffer's
# identity and pixel size. On a fresh first boot the VT can come up in a
# transitional ~80x25 mode and only widen to the real resolution a second or
# more later, when virtio-gpu's KMS takes over (or the SDL window's size lands).
# Watching this signature settle — rather than trusting one early reading — is
# what keeps the greeter from measuring that transient and rendering into it.
console_signature() {
  local size fb_size="" fb_name=""
  size=$(stty size 2>/dev/null </dev/tty) || return 1
  [[ $size =~ ^[0-9]+\ [0-9]+$ ]] || return 1
  [[ -r /sys/class/graphics/fb0/virtual_size ]] && fb_size=$(<"/sys/class/graphics/fb0/virtual_size")
  [[ -r /sys/class/graphics/fb0/name ]] && fb_name=$(<"/sys/class/graphics/fb0/name")
  printf '%s|%s|%s' "$size" "$fb_name" "$fb_size"
}

# Block until the console signature holds unchanged for a genuine quiet stretch
# (quiet_samples * 100ms), giving up after max_samples * 100ms. Returns 0 once
# quiet, 1 on timeout.
wait_console_stable() {
  local max_samples="${1:-100}" quiet_samples="${2:-15}"
  local previous="" current="" quiet=0 i
  for ((i = 0; i < max_samples; i++)); do
    current=$(console_signature 2>/dev/null || true)
    if [[ -n $current && $current == "$previous" ]]; then
      quiet=$((quiet + 1))
      (( quiet >= quiet_samples )) && return 0
    else
      previous=$current
      quiet=0
    fi
    sleep 0.1
  done
  return 1
}

repeat() {
  local char="$1" count="$2" out="" i
  for ((i = 0; i < count; i++)); do out+="$char"; done
  printf '%s' "$out"
}

left_padding() {
  local width="${1:-$LOGO_WIDTH}" cols pad
  cols=$(term_cols)
  pad=$(((cols - width) / 2))
  (( pad < 0 )) && pad=0
  printf '%*s' "$pad" ''
}

visible_len() {
  local text="$1"
  text="$(printf '%b' "$text" | sed -E $'s/\x1b\\[[0-9;?]*[A-Za-z]//g')"
  printf '%s' "${#text}"
}

blank_line() { printf '\r%s\n' "$CLEAR_LINE"; }

line_at() {
  local width="${1:-$LOGO_WIDTH}" indent="${2:-0}"
  shift 2
  printf '\r%s%s%*s' "$CLEAR_LINE" "$(left_padding "$width")" "$indent" ''
  printf '%b' "$*"
}

center() {
  local text="$1" width="${2:-$LOGO_WIDTH}" len inner_pad
  len="$(visible_len "$text")"
  inner_pad=$(((width - len) / 2))
  (( inner_pad < 0 )) && inner_pad=0
  printf '\r%s%s%*s%b%s\n' "$CLEAR_LINE" "$(left_padding "$width")" "$inner_pad" '' "$text" "$RESET"
}

render_logo() {
  local pad line
  pad="$(left_padding "$LOGO_WIDTH")"
  while IFS= read -r line; do
    printf '\r%s%s%b%s%b\n' "$CLEAR_LINE" "$pad" "$GREEN" "$line" "$RESET"
  done <"$LOGO_PATH"
}

progress_bar() {
  local pm="$1" width="${2:-34}" filled empty
  (( pm < 0 )) && pm=0
  (( pm > 1000 )) && pm=1000
  filled=$((pm * width / 1000))
  empty=$((width - filled))
  printf '%s%s%s%s%s' "$WHITE" "$(repeat █ "$filled")" "$DARK" "$(repeat ░ "$empty")" "$RESET"
}

# Monotonic clock so an NTP step during setup cannot jump the bar.
set_now() {
  local up rest
  if read -r up rest </proc/uptime 2>/dev/null && [[ $up == [0-9]* ]]; then
    NOW=${up%%.*}
  else
    NOW=$EPOCHSECONDS
  fi
  return 0
}

# One tip per 8 seconds, elapsed-time driven like the install dashboard.
current_tip() {
  printf '%s' "${tips[$(((NOW - SETUP_T0) / 8 % ${#tips[@]}))]}"
}

SETUP_POS=10
SETUP_T0=0
NOW=0

# Vertically center the setup block the way greeter_screen centers its splash,
# so the screen the owner watches through finalization is composed rather than
# stacked from row one — and first boot bookends the install identically.
measure_setup_layout() {
  local rows
  LAST_SETUP_SIZE=$(term_size)
  rows=${LAST_SETUP_SIZE%% *}
  [[ $rows =~ ^[0-9]+$ ]] || rows=24
  SETUP_TOP_ROW=$(((rows - SETUP_HEIGHT) / 2))
  (( SETUP_TOP_ROW < 0 )) && SETUP_TOP_ROW=0
  SETUP_TOP_ROW=$((SETUP_TOP_ROW + 1))
  DYNAMIC_ROW=$((SETUP_TOP_ROW + LOGO_HEIGHT + 1))
}

render_setup_static() {
  measure_setup_layout
  printf '%s%s%s%d;1H' "$HIDE_CURSOR" "$CLEAR" "$CSI" "$SETUP_TOP_ROW"
  render_logo
  blank_line
}

render_setup_dynamic() {
  # The VT can still resize under us — the same virtio-gpu KMS handoff the
  # greeter watches for. left_padding recomputes every frame, but the logo is
  # drawn once, so repaint it at the new center rather than leaving the centered
  # block stranded against a stale geometry.
  [[ $(term_size) == "$LAST_SETUP_SIZE" ]] || render_setup_static
  set_now
  setup_progress
  printf '%s%d;1H' "$CSI" "$DYNAMIC_ROW"
  center "Setting up your machine" "$LOGO_WIDTH"
  blank_line
  line_at "$LOGO_WIDTH" $(((LOGO_WIDTH - 34) / 2)) ""
  progress_bar "$SETUP_POS" 34
  printf '\n'
  blank_line
  center "${DIM}Tip:${RESET} ${GREEN}$(current_tip)${RESET}" "$LOGO_WIDTH"
  printf '%s' "$CLEAR_TO_END"
}

# The first thing a new owner sees, shown once before the keyboard step:
# the logo (vertically centered like the boot logo) running a looping ColorShift,
# the Omarchy tagline, and a hint. Return skips ahead into setup at any time.
greeter_screen() {
  local anim="" drawn_sig cur_sig resized=0

  # Paint the whole splash for the console's *current* geometry. Kept in a
  # nested function so the wait loop below can repaint it verbatim if the VT
  # resizes out from under us: a late resize (virtio-gpu KMS handoff, or the SDL
  # window's size arriving) scrolls the old frame into the top-left and resets
  # the DEC saved cursor ttfx paints from — exactly the tiled/garbled logo we saw
  # on a fresh first boot. Redrawing on every resize beats any fixed-length
  # startup wait, which can only ever guess when the console has stopped moving.
  _greeter_draw() {
    local rows cols top content_h logo_row tagline_row hint_row
    local tagline hint tpad hpad pad line i

    cols=$(term_cols)
    rows=$(stty size 2>/dev/null </dev/tty | awk '{print $1}')
    [[ $rows =~ ^[0-9]+$ ]] || rows=${LINES:-24}

    tagline="Beautiful, Modern & Opinionated Linux by DHH"
    hint="Press Return to Start Setup"

    printf '%s%s' "$HIDE_CURSOR" "$CLEAR"

    # Console still too narrow for the 81-column logo (a transient small mode):
    # skip the logo and animation rather than wrap them into mush — just center
    # the words. The redraw loop repaints the full splash once the VT widens.
    if (( cols <= LOGO_WIDTH )); then
      local mid=$(( rows / 2 ))
      tpad=$(( (cols - ${#tagline}) / 2 )); (( tpad < 0 )) && tpad=0
      hpad=$(( (cols - ${#hint}) / 2 )); (( hpad < 0 )) && hpad=0
      printf '%s%d;%dH%s' "$CSI" "$mid" "$((tpad + 1))" "$tagline"
      printf '%s%d;%dH%s%s%s' "$CSI" "$((mid + 2))" "$((hpad + 1))" "$DIM" "$hint" "$RESET"
      return 0
    fi

    # logo + blank + tagline + blank + hint
    content_h=$(( LOGO_HEIGHT + 4 ))
    top=$(( (rows - content_h) / 2 )); (( top < 0 )) && top=0
    logo_row=$(( top + 1 ))
    tagline_row=$(( top + LOGO_HEIGHT + 2 ))
    hint_row=$(( top + LOGO_HEIGHT + 4 ))

    # Draw each logo row at an explicit column so nothing can wrap it even if a
    # measurement is off by one; left_padding centers it for the current width.
    pad="$(left_padding "$LOGO_WIDTH")"
    i=0
    while IFS= read -r line; do
      printf '%s%d;1H%s%b%s%b' "$CSI" "$((logo_row + i))" "$pad" "$GREEN" "$line" "$RESET"
      i=$((i + 1))
    done <"$LOGO_PATH"

    tpad=$(( (cols - ${#tagline}) / 2 )); (( tpad < 0 )) && tpad=0
    printf '%s%d;%dH%s' "$CSI" "$tagline_row" "$((tpad + 1))" "$tagline"

    hpad=$(( (cols - ${#hint}) / 2 )); (( hpad < 0 )) && hpad=0
    printf '%s%d;%dH%s%s%s' "$CSI" "$hint_row" "$((hpad + 1))" "$DIM" "$hint" "$RESET"

    # ColorShift the logo: a green base (indexed color 2) with a cyan accent (6)
    # drifting through, settling on green. Indexed ANSI colors, not hex — the
    # framebuffer console can't render ttfx's truecolor faithfully (it crushes the
    # palette to a muddy lavender), but the 16 indexed colors map to the Tokyo
    # Night palette and render true. One long-running invocation (many cycles) so
    # it never restarts — a restart is what flashed. The effect reads from
    # /dev/null so it never swallows the Return the foreground read waits on;
    # --reuse-canvas paints upward from the saved cursor, anchored one row below
    # the logo to repaint exactly the rows drawn above.
    #
    # --xterm-colors is what actually keeps the palette indexed: ttfx resolves
    # even indexed stops to truecolor otherwise, and the console reduces 256-colour
    # codes well but 24-bit ones badly — that reduction is the muddy lavender.
    # It also pins the settle colour to index 2, matching the green logo drawn
    # above. --canvas-width is cols-2, not cols-1: ttfx centres its text two
    # columns right of plain centering, so cols-1 lands the animated logo a
    # column off the static one and it jumps when the effect starts.
    printf '%s%d;1H\0337' "$CSI" "$((logo_row + LOGO_HEIGHT))"
    # Run ttfx directly (not inside a `while` subshell) so $anim is ttfx's own
    # PID: killing a wrapping subshell would orphan ttfx, which then keeps
    # painting the logo over the keyboard step. --cycles is high enough that it
    # never ends on its own before Return.
    ttfx -i "$LOGO_PATH" \
      --canvas-width "$((cols > 2 ? cols - 2 : cols))" \
      --anchor-text c \
      --frame-rate 60 \
      --reuse-canvas \
      --xterm-colors \
      colorshift \
      --gradient-stops 2 10 6 10 \
      --gradient-frames 3 \
      --cycles 1000 \
      --final-gradient-stops 2 \
      </dev/null >/dev/tty 2>/dev/null &
    anim=$!
  }

  _greeter_kill_anim() {
    [[ -n ${anim:-} ]] || return 0
    # Guard both: `kill` returns non-zero if ttfx already exited (crash, or a
    # resize race), and `wait` reports ttfx's kill signal (143) — either would
    # abort provisioning under `set -e` and drop straight to the login screen.
    kill "$anim" 2>/dev/null || true
    wait "$anim" 2>/dev/null || true
    anim=""
  }

  # Let the console settle before the first paint, then size the font to it.
  wait_console_stable 100 15 || true
  scale_console_font
  wait_console_stable 30 5 || true

  trap 'resized=1' WINCH

  _greeter_draw
  drawn_sig=$(console_signature 2>/dev/null || true)

  # Wait for Return, but keep watching the geometry. On any resize (SIGWINCH or
  # a changed signature) tear the animation down, settle, re-fit the font, and
  # repaint — so a resize arriving five seconds in looks the same as one that
  # never happened.
  while true; do
    if IFS= read -r -t 0.2 _ </dev/tty; then
      break
    fi
    cur_sig=$(console_signature 2>/dev/null || true)
    if (( resized )) || [[ -n $cur_sig && $cur_sig != "$drawn_sig" ]]; then
      _greeter_kill_anim
      stty sane </dev/tty 2>/dev/null || true
      wait_console_stable 50 5 || true
      scale_console_font
      wait_console_stable 30 5 || true
      _greeter_draw
      drawn_sig=$(console_signature 2>/dev/null || true)
      # Clear last so the font-fitting's own SIGWINCHes don't re-trigger a redraw.
      resized=0
    fi
  done

  trap - WINCH
  _greeter_kill_anim
  # ttfx leaves the tty in raw/no-echo mode when killed; restore it or the gum
  # prompts in the keyboard step that follows silently die. Then clear the
  # leftover animation frame.
  stty sane </dev/tty 2>/dev/null || true
  printf '%s%s%s' "$RESET" "$CLEAR" "$SHOW_CURSOR"
}

# Fitting the console font is the framebuffer console's problem and nobody
# else's: omarchy-provision-owner overrides this, and anything drawing into a
# terminal emulator leaves it alone.
scale_console_font() { :; }

# Move the bar on elapsed time alone, asymptotically towards the end of the
# band, so it always moves and never arrives on its own. A caller with a real
# work signal to count overrides this.
OMARCHY_SETUP_CEILING=1000
OMARCHY_SETUP_TAU=45

setup_progress() {
  local t span floor

  t=$((NOW - SETUP_T0))
  span=$((OMARCHY_SETUP_CEILING - 10))
  floor=$((10 + (span - 1) * t / (t + OMARCHY_SETUP_TAU)))

  (( floor > SETUP_POS )) && SETUP_POS=$floor
  (( SETUP_POS > 1000 )) && SETUP_POS=1000
  return 0
}

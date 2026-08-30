# Omarchy launches the browser, shares files and schedules reminders through
# "systemd-run --user", which needs a systemd user manager. WSL has none
# (docs/wsl.md explains why), so those commands fail before they start
# anything -- and omarchy-launch-browser passes StandardError=null, so the
# browser simply never appears and nothing is logged.
#
# Shimmed rather than guarded at each of the five call sites, the same way
# uwsm-app is: WSL knowledge stays in install/wsl, and /usr/local/bin precedes
# /usr/bin so the real systemd-run is shadowed without being removed.

install -Dm755 /dev/stdin /usr/local/bin/systemd-run <<'SYSTEMD_RUN'
#!/bin/bash

# Convert the systemd time spans these callers actually use into seconds.
# Longest suffixes first: "2ms" ends in s, and "5min" ends in n, so the order
# is what keeps them apart.
span_to_seconds() {
  local span="$1"

  case "$span" in
    *ms) echo 0 ;;
    *min) echo $(( ${span%min} * 60 )) ;;
    *s) echo "${span%s}" ;;
    *m) echo $(( ${span%m} * 60 )) ;;
    *h) echo $(( ${span%h} * 3600 )) ;;
    *) echo "$span" ;;
  esac
}

# Only the user manager is missing. The system one works, and
# omarchy-sudo-passwordless schedules its timers against it.
user_scope=0

for arg in "$@"; do
  [[ $arg == "--" ]] && break
  if [[ $arg == "--user" ]]; then
    user_scope=1
    break
  fi
done

if (( ! user_scope )); then
  exec /usr/bin/systemd-run "$@"
fi

delay=0

while (($#)); do
  case "$1" in
    --on-active=*)
      delay=$(span_to_seconds "${1#*=}")
      shift
      ;;
    --on-active)
      delay=$(span_to_seconds "$2")
      shift 2
      ;;
    --unit|--property|-p|--timer-property|--description|--slice|--setenv|-E|--working-directory|--uid|--gid)
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      # Every other systemd-run option is about unit bookkeeping that has no
      # meaning without a manager. A command never starts with a dash, so
      # dropping these cannot swallow one.
      shift
      ;;
    *)
      break
      ;;
  esac
done

(($#)) || exit 0

# Output goes to the journal rather than nowhere: a browser that fails to start
# should be diagnosable, which is exactly what StandardError=null prevented.
if (( delay > 0 )); then
  setsid --fork bash -c 'sleep "$1"; shift; exec systemd-cat --identifier=systemd-run "$@"' \
    systemd-run-shim "$delay" "$@" >/dev/null 2>&1 </dev/null
  exit 0
fi

exec setsid --fork systemd-cat --identifier=systemd-run "$@" >/dev/null 2>&1 </dev/null
SYSTEMD_RUN

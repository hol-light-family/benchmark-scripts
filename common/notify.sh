#!/bin/bash
# notify.sh: e-mail a notification when a benchmark script exits.
#
# Source this file; do not run it.
#
#   source "$script_dir/../../common/notify.sh"
#   notify_on_exit <name> [log file]
#
# notify_on_exit installs an EXIT trap that sends one e-mail when the calling
# script ends, whether it passed (exit 0) or failed (any other exit, including
# `set -e` aborts and early `exit 1` checks). The body holds the exit status,
# host, elapsed time, the log path, and the last lines of the log.
#
# Notifications are off unless NOTIFY_TO is set, so scripts behave as before
# when it is not. Settings (environment):
#   NOTIFY_TO         recipient address (required to enable notifications)
#   NOTIFY_FROM       optional From: address
#   NOTIFY_LOG        log to tail when notify_on_exit is given no log file
#   NOTIFY_SUMMARY    optional extra text appended to the body
#   NOTIFY_TAIL_LINES number of log lines to include (default 40)
#   NOTIFY_UNSENT_DIR where an unsent message is saved if no mailer works
#                     (default: $TMPDIR or /tmp)
#
# Mailer credentials are not handled here. Configure `mail`, `msmtp` or
# `sendmail` (for example ~/.msmtprc) on the machine. They are tried in that
# order.
#
# A script that installs its own EXIT trap after calling notify_on_exit
# replaces this one. Such a script must call notify_exit from its trap:
#
#   trap 'status=$?; rm -f "$tmp"; notify_exit "$status"' EXIT

NOTIFY_NAME=
NOTIFY_LOG_FILE=
NOTIFY_START=
NOTIFY_SENT=0

notify_send() {  # notify_send <subject> <body file>
  local subject=$1 body=$2 to=${NOTIFY_TO:-}
  [ -n "$to" ] || return 0
  local headers
  headers=$(printf 'To: %s\nSubject: %s\n' "$to" "$subject")
  if [ -n "${NOTIFY_FROM:-}" ]; then
    headers=$(printf 'From: %s\n%s' "$NOTIFY_FROM" "$headers")
  fi
  if command -v mail >/dev/null 2>&1; then
    if [ -n "${NOTIFY_FROM:-}" ]; then
      mail -s "$subject" -r "$NOTIFY_FROM" "$to" < "$body" && return 0
    else
      mail -s "$subject" "$to" < "$body" && return 0
    fi
  fi
  if command -v msmtp >/dev/null 2>&1; then
    { printf '%s\n\n' "$headers"; cat "$body"; } | msmtp "$to" && return 0
  fi
  if command -v sendmail >/dev/null 2>&1; then
    { printf '%s\n\n' "$headers"; cat "$body"; } | sendmail -t && return 0
  fi
  local pending
  pending="${NOTIFY_UNSENT_DIR:-${TMPDIR:-/tmp}}/UNSENT-$(date +%Y%m%d-%H%M%S)-$$.txt"
  { printf '%s\n\n' "$headers"; cat "$body"; } > "$pending"
  echo "No working mailer; notification saved to $pending" >&2
  return 1
}

# notify_exit [status]: send the notification once. Meant to run from an EXIT
# trap; it keeps the script's exit status.
notify_exit() {
  local status=${1:-$?}
  if [ "$NOTIFY_SENT" = 1 ] || [ -z "${NOTIFY_TO:-}" ] || [ -z "$NOTIFY_NAME" ]; then
    exit "$status"
  fi
  NOTIFY_SENT=1
  set +e
  local verdict=PASS
  [ "$status" -eq 0 ] || verdict=FAILED
  local now elapsed=unknown
  now=$(date +%s)
  [ -n "$NOTIFY_START" ] && elapsed="$((now - NOTIFY_START)) sec"
  local body
  body=$(mktemp)
  {
    echo "$NOTIFY_NAME: $verdict (exit status $status)"
    echo "Host: $(hostname)"
    echo "Time: $(date -u)"
    echo "Elapsed: $elapsed"
    [ -n "$NOTIFY_LOG_FILE" ] && echo "Log: $NOTIFY_LOG_FILE"
    if [ -n "${NOTIFY_SUMMARY:-}" ]; then
      echo
      printf '%s\n' "$NOTIFY_SUMMARY"
    fi
    if [ -n "$NOTIFY_LOG_FILE" ] && [ -f "$NOTIFY_LOG_FILE" ]; then
      echo
      echo "--- last ${NOTIFY_TAIL_LINES:-40} log lines ---"
      tail -n "${NOTIFY_TAIL_LINES:-40}" "$NOTIFY_LOG_FILE"
    fi
  } > "$body"
  notify_send "[HOL benchmarks] $verdict: $NOTIFY_NAME ($(hostname))" "$body"
  rm -f "$body"
  exit "$status"
}

# notify_on_exit <name> [log file]
notify_on_exit() {
  NOTIFY_NAME=$1
  NOTIFY_LOG_FILE=${2:-${NOTIFY_LOG:-}}
  NOTIFY_START=$(date +%s)
  NOTIFY_SENT=0
  trap 'notify_exit "$?"' EXIT
  # Without these, bash runs the EXIT trap with status 0 when a signal kills
  # the script, which would report a killed run as PASS.
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

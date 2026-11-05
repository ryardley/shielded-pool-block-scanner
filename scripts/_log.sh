#!/usr/bin/env bash
# Shared timing/logging helpers for install.sh and up.sh.
#
# Sourced by the scripts; expects the sourcing script to set CACHE and LOG_NAME
# before calling init_log. Logs are written to <CACHE>/logs/<LOG_NAME>-<UTC ts>.log
# with a stable <CACHE>/logs/<LOG_NAME>-latest.log symlink for convenience.
set -u

# --- state ----------------------------------------------------------------
LOG_FILE=""
LOG_START=""
SUMMARY_PRINTED=0
declare -A _TIMES=()
_TIMES_ORDER=()

# --- helpers --------------------------------------------------------------
_log_ts() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
_now() { date +%s.%N; }
_script() { echo "${LOG_NAME:-$(basename "${BASH_SOURCE[1]:-$0}")}"; }

init_log() {
  LOG_NAME="${LOG_NAME:-$(_script)}"
  local dir="$CACHE/logs"
  mkdir -p "$dir"
  LOG_FILE="$dir/${LOG_NAME}-$(date -u '+%Y%m%dT%H%M%SZ').log"
  : > "$LOG_FILE"
  ln -sf "$(basename "$LOG_FILE")" "$dir/${LOG_NAME}-latest.log"
  LOG_START=$(_now)
  log "=== $(_script) started ==="
  log "log: $LOG_FILE"
}

# Print a timestamped line to stdout and append it to the run log.
log() {
  local line="$(_log_ts) [$(_script)] $*"
  printf '%s\n' "$line" | tee -a "${LOG_FILE:-/dev/null}"
}

# Run a command, streaming output to both the terminal and the run log, and
# log its duration + status. Returns the command's exit status. Safe under
# `set -e` / `set -o pipefail`.
run_timed() {
  local label="$1"; shift
  local start end status
  start=$(_now)
  log "START $label: $*"
  set +e
  "$@" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"
  status=${PIPESTATUS[0]}
  set -e
  end=$(_now)
  _record "$label" "$start" "$end" "$status"
  return "$status"
}

# Run a command inside a directory, logging duration + status like run_timed.
run_timed_in() {
  local dir="$1" label="$2"; shift 2
  (
    cd "$dir" || { log "FAILED $label: cannot cd $dir"; return 1; }
    run_timed "$label" "$@"
  )
}

# --- summary --------------------------------------------------------------
_record() {
  local label="$1" start="$2" end="$3" status="$4"
  local dur
  dur=$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.1f", e - s }')
  _TIMES["$label"]="$dur|$status"
  _TIMES_ORDER+=("$label")
  if [ "$status" -eq 0 ]; then
    log "DONE $label (${dur}s)"
  else
    log "FAILED $label (exit $status, ${dur}s)"
  fi
}

_duration_hms() {
  local s="$1" h m
  h=$((s / 3600)); s=$((s % 3600))
  m=$((s / 60)); s=$((s % 60))
  printf '%dh%02dm%02ds' "$h" "$m" "$s"
}

print_summary() {
  if [ "$SUMMARY_PRINTED" -eq 1 ]; then return 0; fi
  SUMMARY_PRINTED=1
  local label row dur status total width
  total=$(awk -v s="$LOG_START" -v e="$(_now)" 'BEGIN { printf "%.1f", e - s }')
  width=34
  for label in "${_TIMES_ORDER[@]}"; do
    row="${_TIMES[$label]}"
    dur="${row%%|*}"
    status="${row##*|}"
    printf '  %-*s %8ss  %s\n' "$width" "$label" "$dur" \
      "$([ "$status" -eq 0 ] && echo ok || echo "FAILED($status)")"
  done
  printf '  %-*s %8ss  %s\n' "$width" "TOTAL" "$total" ok
  log "=== summary: total ${total}s ==="
}

#!/bin/bash
# run.sh <Flyspeck dir> <hol-light dir> [log file]
#
# Loads Flyspeck's load_flyspeck.ml entry point, then loads the whole proof
# through the final command documented there:
#
#   map flyspeck_needs Build.build_sequence_full;;
#
# The command is wrapped only to emit a completion marker if the whole map
# returns successfully. No later proof stage is run.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "run.sh <Flyspeck dir> <hol-light dir> [log file]" >&2
  exit 1
fi

flyspeck_root=$(cd "$1" && pwd)
hol_light_dir=$(cd "$2" && pwd)
log_file=${3:-"$(dirname "$flyspeck_root")/flyspeck-run.log"}

if [ ! -f "$flyspeck_root/load_flyspeck.ml" ]; then
  echo "$flyspeck_root does not contain load_flyspeck.ml" >&2
  exit 1
fi
if [ ! -d "$flyspeck_root/text_formalization" ]; then
  echo "$flyspeck_root does not contain text_formalization/" >&2
  exit 1
fi
if [ ! -x "$hol_light_dir/hol.sh" ]; then
  echo "$hol_light_dir/hol.sh is missing or not executable" >&2
  exit 1
fi

export FLYSPECK_DIR="$flyspeck_root/text_formalization"
export HOLLIGHT_DIR="$hol_light_dir"

# Use the local opam switch with which this HOL Light checkout was built.
eval "$(opam env --switch "$hol_light_dir" --set-switch 2>/dev/null || opam env)"

mkdir -p "$(dirname "$log_file")"
log_file=$(cd "$(dirname "$log_file")" && pwd)/$(basename "$log_file")
command_file=$(mktemp)
trap 'rm -f "$command_file"' EXIT

cat > "$command_file" <<'EOF'
needs "load_flyspeck.ml";;
let _ = map flyspeck_needs Build.build_sequence_full in
  print_endline "FLYSPECK_BUILD_SEQUENCE_FULL_COMPLETED";;
EOF

start_unixtime=$(date +%s)
{
  echo "Flyspeck root: $flyspeck_root"
  echo "FLYSPECK_DIR: $FLYSPECK_DIR"
  echo "HOLLIGHT_DIR: $HOLLIGHT_DIR"
  echo "Start unixtime: $start_unixtime"
  echo
} > "$log_file"

set +e
(
  cd "$flyspeck_root"
  "$hol_light_dir/hol.sh" < "$command_file"
) >> "$log_file" 2>&1
hol_status=$?
set -e

end_unixtime=$(date +%s)
elapsed=$((end_unixtime - start_unixtime))
{
  echo
  echo "Running time: $elapsed sec, Start unixtime: $start_unixtime, End unixtime: $end_unixtime"
  echo "HOL Light exit status: $hol_status"
} >> "$log_file"

if [ "$hol_status" -ne 0 ]; then
  echo "HOL Light exited with status $hol_status; see $log_file" >&2
  exit "$hol_status"
fi

if ! grep -q '^FLYSPECK_BUILD_SEQUENCE_FULL_COMPLETED$' "$log_file"; then
  echo "The full Flyspeck sequence did not reach its completion marker; see $log_file" >&2
  exit 1
fi

"$script_dir/../../common/check-failures.sh" "$log_file"
echo "Flyspeck full sequence completed successfully."
echo "Log: $log_file"

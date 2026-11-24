#!/bin/bash
# run.sh <LightCake dir> <hol-light dir> [log file]
#
# Loads and checks the complete LightCake port of CakeML in one HOL Light
# session, started in the repository root as its README requires:
#
#   loadt "check.ml";;
#
# check.ml loads make.ml, then prints NOT LOADED <file> for every expected
# file that did not load, AXIOMS_COUNT <n> and the axioms, HEADLINE <bool>
# (compile_correct and compile_correct_safe_for_space), HEADLINE_AG32 <bool>
# (ag32_compile_correct), and finally CHECK_OK or CHECK_FAILED. The load is
# bracketed by LIGHTCAKE_STAGE_START/END markers carrying the Unix time,
# which collect-results.py uses for timing.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "run.sh <LightCake dir> <hol-light dir> [log file]" >&2
  exit 1
fi

lightcake_root=$(cd "$1" && pwd)
hol_light_dir=$(cd "$2" && pwd)
log_file=${3:-"$(dirname "$lightcake_root")/lightcake-run.log"}
source "$script_dir/../../common/notify.sh"
notify_on_exit "LightCake" "$log_file"

for required in make.ml check.ml src/prelude.ml; do
  if [ ! -f "$lightcake_root/$required" ]; then
    echo "$lightcake_root does not contain $required" >&2
    exit 1
  fi
done
if [ ! -x "$hol_light_dir/hol.sh" ]; then
  echo "$hol_light_dir/hol.sh is missing or not executable" >&2
  exit 1
fi

# Use the local opam switch with which this HOL Light checkout was built.
eval "$(opam env --switch "$hol_light_dir" --set-switch 2>/dev/null || opam env)"

# Run the toplevel directly; ledit would echo the piped commands into the log.
export LINE_EDITOR=env

mkdir -p "$(dirname "$log_file")"
log_file=$(cd "$(dirname "$log_file")" && pwd)/$(basename "$log_file")
command_file=$(mktemp)
trap 'status=$?; rm -f "$command_file"; notify_exit "$status"' EXIT

# Stage markers are printed by a child `date` process because Unix is not
# loaded in the HOL Light toplevel. The marker words are concatenated so the
# literal marker text never appears in the input. The leading newline keeps
# each marker on its own line after the toplevel prompt.
cat > "$command_file" <<'EOC'
let lightcake_bench_stage edge =
  print_newline (); flush stdout; flush stderr;
  ignore (Sys.command
    ("echo \"LIGHTCAKE_" ^ "STAGE_" ^ edge ^ " check.ml $(date +%s)\""));;
lightcake_bench_stage "START";;
loadt "check.ml";;
lightcake_bench_stage "END";;
EOC

start_unixtime=$(date +%s)
{
  echo "LightCake root: $lightcake_root"
  echo "HOL Light directory: $hol_light_dir"
  echo "OCaml version: $(ocamlfind ocamlc -version 2>/dev/null || echo unknown)"
  echo "Start unixtime: $start_unixtime"
  echo
} > "$log_file"

set +e
(
  cd "$lightcake_root"
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

# The toplevel continues after a failed loadt, so completion is judged from
# the lines check.ml prints after loading make.ml.
if ! grep -Eq '^(# )*CHECK_OK$' "$log_file"; then
  echo "The log does not contain CHECK_OK; see $log_file" >&2
  exit 1
fi
if grep -Eq '^(# )*NOT LOADED ' "$log_file"; then
  echo "Some files of make.ml did not load; see $log_file" >&2
  exit 1
fi
for marker in 'AXIOMS_COUNT 3' 'HEADLINE true' 'HEADLINE_AG32 true'; do
  if ! grep -Eq "^(# )*$marker\$" "$log_file"; then
    echo "The log does not contain '$marker'; see $log_file" >&2
    exit 1
  fi
done

# Same markers as common/check-failures.sh, but only at the start of a line
# (after optional "# " prompts): HOL Light echoes definitions whose string
# literals contain "### ERROR: ..." on indented lines, which are not failures.
# The "### Error: skip" benign rule never applies because "###" does not match.
if grep -aEiq '^(# )*(error:|exception:|error in included file)' "$log_file"; then
  echo "Failure markers found in $log_file:" >&2
  grep -aEi '^(# )*(error:|exception:|error in included file)' "$log_file" | head -20 >&2
  exit 1
fi
echo "LightCake port completed successfully."
echo "Log: $log_file"

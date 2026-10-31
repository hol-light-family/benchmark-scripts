#!/bin/bash
# run.sh <Navier_Stokes dir> <hol-light dir> [log file]
#
# Loads the complete Navier_Stokes development and its statement audit in one
# HOL Light session, started in the repository root as its README requires:
#
#   loadt "check.ml";;        (* make.ml + headline theorems and axioms *)
#   loadt "audit/check.ml";;  (* audit/make.ml + equivalence/sanity checks *)
#
# audit/make.ml reaches the development through `needs "make.ml"`, so the
# second stage only loads the audit files. Each stage is bracketed by
# NAVIER_STOKES_STAGE_START/END markers carrying the Unix time, which
# collect-results.py uses for per-stage timing.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "run.sh <Navier_Stokes dir> <hol-light dir> [log file]" >&2
  exit 1
fi

ns_root=$(cd "$1" && pwd)
hol_light_dir=$(cd "$2" && pwd)
log_file=${3:-"$(dirname "$ns_root")/navier-stokes-run.log"}

for required in make.ml check.ml audit/make.ml audit/check.ml; do
  if [ ! -f "$ns_root/$required" ]; then
    echo "$ns_root does not contain $required" >&2
    exit 1
  fi
done
if [ ! -x "$hol_light_dir/hol.sh" ]; then
  echo "$hol_light_dir/hol.sh is missing or not executable" >&2
  exit 1
fi

# Use the local opam switch with which this HOL Light checkout was built.
eval "$(opam env --switch "$hol_light_dir" --set-switch 2>/dev/null || opam env)"

# Run the toplevel directly, as Navier_Stokes' README documents. ledit would
# echo the piped commands into the log.
export LINE_EDITOR=env

mkdir -p "$(dirname "$log_file")"
log_file=$(cd "$(dirname "$log_file")" && pwd)/$(basename "$log_file")
command_file=$(mktemp)
trap 'rm -f "$command_file"' EXIT

# Stage markers are printed by a child `date` process because Unix is not
# loaded in the HOL Light toplevel. The marker words are concatenated so the
# literal marker text never appears in the input. The leading newline keeps
# each marker on its own line after the toplevel prompt.
cat > "$command_file" <<'EOF'
let ns_bench_stage edge name =
  print_newline (); flush stdout; flush stderr;
  ignore (Sys.command
    ("echo \"NAVIER_STOKES_" ^ "STAGE_" ^ edge ^ " " ^ name ^ " $(date +%s)\""));;
ns_bench_stage "START" "check.ml";;
loadt "check.ml";;
ns_bench_stage "END" "check.ml";;
ns_bench_stage "START" "audit/check.ml";;
loadt "audit/check.ml";;
ns_bench_stage "END" "audit/check.ml";;
EOF

start_unixtime=$(date +%s)
{
  echo "Navier_Stokes root: $ns_root"
  echo "HOL Light directory: $hol_light_dir"
  echo "OCaml version: $(ocamlfind ocamlc -version 2>/dev/null || echo unknown)"
  echo "Start unixtime: $start_unixtime"
  echo
} > "$log_file"

set +e
(
  cd "$ns_root"
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
# the markers that check.ml and audit/check.ml print at their very end.
for marker in NAVIER_STOKES_CHECK_DONE NAVIER_STOKES_AUDIT_CHECK_DONE; do
  if ! grep -Eq "^(# )*$marker\$" "$log_file"; then
    echo "The log does not contain $marker; see $log_file" >&2
    exit 1
  fi
done

# Every headline/audit theorem must have no hypotheses and the expected
# conclusion, using only HOL Light's three standard axioms.
if grep -Eq 'hypotheses [1-9]|: false$' "$log_file"; then
  echo "A checked theorem has hypotheses or an unexpected conclusion; see $log_file" >&2
  exit 1
fi
if [ "$(grep -Ec '^(# )*AXIOMS_COUNT 3$' "$log_file")" -ne 2 ]; then
  echo "Expected AXIOMS_COUNT 3 after both stages; see $log_file" >&2
  exit 1
fi

"$script_dir/../../common/check-failures.sh" "$log_file"
echo "Navier_Stokes development and audit completed successfully."
echo "Log: $log_file"

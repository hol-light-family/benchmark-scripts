#!/bin/bash
# run.sh <catalan-is-irrational dir> <hol-light dir> [log file]
#
# Loads the complete catalan-is-irrational development in one HOL Light
# session, started in the repository root as its README requires:
#
#   loadt "make.ml";;
#
# The load is bracketed by CATALAN_STAGE_START/END markers carrying the Unix
# time, which collect-results.py uses for timing. Afterwards the session
# reports, for each headline theorem, its number of hypotheses and whether its
# conclusion is exactly the expected statement, and the number of axioms.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "run.sh <catalan-is-irrational dir> <hol-light dir> [log file]" >&2
  exit 1
fi

catalan_root=$(cd "$1" && pwd)
hol_light_dir=$(cd "$2" && pwd)
log_file=${3:-"$(dirname "$catalan_root")/catalan-is-irrational-run.log"}

for required in make.ml src/catalan_main.ml src/catalan_statement.ml; do
  if [ ! -f "$catalan_root/$required" ]; then
    echo "$catalan_root does not contain $required" >&2
    exit 1
  fi
done
if [ ! -x "$hol_light_dir/hol.sh" ]; then
  echo "$hol_light_dir/hol.sh is missing or not executable" >&2
  exit 1
fi

# Use the local opam switch with which this HOL Light checkout was built.
eval "$(opam env --switch "$hol_light_dir" --set-switch 2>/dev/null || opam env)"

# Run the toplevel directly, as the catalan-is-irrational README documents.
# ledit would echo the piped commands into the log.
export LINE_EDITOR=env

mkdir -p "$(dirname "$log_file")"
log_file=$(cd "$(dirname "$log_file")" && pwd)/$(basename "$log_file")
command_file=$(mktemp)
trap 'rm -f "$command_file"' EXIT

# Stage markers are printed by a child `date` process because Unix is not
# loaded in the HOL Light toplevel. Marker words are concatenated so the
# literal marker text never appears in the input.
#
# The expected statements are written here, independently of the
# development: CATALAN_CONSTANT_IRRATIONAL_HEADLINE uses only HOL Light's own
# notions (real_sums, from, integer), so checking its conclusion checks the
# result without trusting the development's definitions. make.ml ends with
# prioritize_real(), the same number priority used to parse it there; set it
# again so these terms parse the same way. Each report is its own phrase, so
# a missing theorem only drops that report (and prints an Error: line).
cat > "$command_file" <<'EOF'
let cat_bench_stage edge =
  print_newline (); flush stdout; flush stderr;
  ignore (Sys.command
    ("echo \"CATALAN_" ^ "STAGE_" ^ edge ^ " make.ml $(date +%s)\""));;
cat_bench_stage "START";;
loadt "make.ml";;
cat_bench_stage "END";;
prioritize_real();;
let cat_bench_report name th expected =
  Printf.printf ("\nCATALAN_" ^^ "THEOREM %s hypotheses %d conclusion %b\n%!")
    name (List.length (hyp th)) (aconv (concl th) expected);;
cat_bench_report "CATALAN_CONSTANT_IRRATIONAL_HEADLINE"
  CATALAN_CONSTANT_IRRATIONAL_HEADLINE
  `(exists G. ((\j. --(&1) pow j / &(2 * j + 1) pow 2) real_sums G) (from 0)) /\
   (forall G. ((\j. --(&1) pow j / &(2 * j + 1) pow 2) real_sums G) (from 0)
        ==> ~(exists m n. integer m /\ integer n /\ ~(n = &0) /\ G = m / n))`;;
cat_bench_report "CATALAN_CONSTANT_IRRATIONAL"
  CATALAN_CONSTANT_IRRATIONAL `~(rational catalan_constant)`;;
cat_bench_report "CATALAN_IRRATIONAL"
  CATALAN_IRRATIONAL `CATALAN_IRRATIONAL_STATEMENT`;;
Printf.printf ("\nCATALAN_" ^^ "AXIOMS_COUNT %d\n%!") (List.length (axioms ()));;
EOF

start_unixtime=$(date +%s)
{
  echo "catalan-is-irrational root: $catalan_root"
  echo "HOL Light directory: $hol_light_dir"
  echo "OCaml version: $(ocamlfind ocamlc -version 2>/dev/null || echo unknown)"
  echo "Start unixtime: $start_unixtime"
  echo
} > "$log_file"

set +e
(
  cd "$catalan_root"
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
# the reports printed after the load, not from the exit status.
for name in CATALAN_CONSTANT_IRRATIONAL_HEADLINE CATALAN_CONSTANT_IRRATIONAL \
            CATALAN_IRRATIONAL; do
  if ! grep -Eq "^(# )*CATALAN_THEOREM $name hypotheses 0 conclusion true\$" "$log_file"; then
    echo "$name was not proved with no hypotheses and the expected conclusion; see $log_file" >&2
    exit 1
  fi
done
if ! grep -Eq '^(# )*CATALAN_AXIOMS_COUNT 3$' "$log_file"; then
  echo "Expected CATALAN_AXIOMS_COUNT 3; see $log_file" >&2
  exit 1
fi

"$script_dir/../../common/check-failures.sh" "$log_file"
echo "catalan-is-irrational development completed successfully."
echo "Log: $log_file"

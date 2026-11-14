#!/bin/bash
# run.sh <Poincare dir> <hol-light dir> [log file]
#
# Loads the complete Poincare development and its statement audit in one HOL
# Light session, started in the repository root as its README requires:
#
#   loadt "check.ml";;        (* make.ml + headline theorems and axioms *)
#   loadt "audit/check.ml";;  (* audit/make.ml + equivalence/sanity checks *)
#
# audit/make.ml starts with loadt "make.ml", but make.ml loads every file with
# needs, so the second stage only loads the audit files. Each stage is
# bracketed by POINCARE_STAGE_START/END markers carrying the Unix time, which
# collect-results.py uses for per-stage timing.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "run.sh <Poincare dir> <hol-light dir> [log file]" >&2
  exit 1
fi

poincare_root=$(cd "$1" && pwd)
hol_light_dir=$(cd "$2" && pwd)
log_file=${3:-"$(dirname "$poincare_root")/poincare-run.log"}

for required in make.ml check.ml audit/make.ml audit/check.ml; do
  if [ ! -f "$poincare_root/$required" ]; then
    echo "$poincare_root does not contain $required" >&2
    exit 1
  fi
done
if [ ! -x "$hol_light_dir/hol.sh" ]; then
  echo "$hol_light_dir/hol.sh is missing or not executable" >&2
  exit 1
fi

# Use the local opam switch with which this HOL Light checkout was built.
eval "$(opam env --switch "$hol_light_dir" --set-switch 2>/dev/null || opam env)"

# Run the toplevel directly, as Poincare's README documents. ledit would echo
# the piped commands into the log.
export LINE_EDITOR=env

mkdir -p "$(dirname "$log_file")"
log_file=$(cd "$(dirname "$log_file")" && pwd)/$(basename "$log_file")
command_file=$(mktemp)
trap 'rm -f "$command_file"' EXIT

# Stage markers are printed by a child `date` process because Unix is not
# loaded in the HOL Light toplevel. The marker words are concatenated so the
# literal marker text never appears in the input. The leading newline keeps
# each marker on its own line after the toplevel prompt.
cat > "$command_file" <<'EOC'
let poincare_bench_stage edge name =
  print_newline (); flush stdout; flush stderr;
  ignore (Sys.command
    ("echo \"POINCARE_" ^ "STAGE_" ^ edge ^ " " ^ name ^ " $(date +%s)\""));;
poincare_bench_stage "START" "check.ml";;
loadt "check.ml";;
poincare_bench_stage "END" "check.ml";;
poincare_bench_stage "START" "audit/check.ml";;
loadt "audit/check.ml";;
poincare_bench_stage "END" "audit/check.ml";;
EOC

start_unixtime=$(date +%s)
{
  echo "Poincare root: $poincare_root"
  echo "HOL Light directory: $hol_light_dir"
  echo "OCaml version: $(ocamlfind ocamlc -version 2>/dev/null || echo unknown)"
  echo "Start unixtime: $start_unixtime"
  echo
} > "$log_file"

set +e
(
  cd "$poincare_root"
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
for marker in POINCARE_CHECK_DONE POINCARE_AUDIT_CHECK_DONE; do
  if ! grep -Eq "^(# )*$marker\$" "$log_file"; then
    echo "The log does not contain $marker; see $log_file" >&2
    exit 1
  fi
done

# Every headline and audit theorem must have no hypotheses and the expected
# conclusion, every sanity theorem no hypotheses, using only HOL Light's three
# standard axioms.
for name in POINCARE_TOP POINCARE_SMOOTH POINCARE_EMBEDDED MOI_SST_HEADLINE \
            POINCARE_TOP_BLIND_EQUIV POINCARE_SMOOTH_BLIND_EQUIV \
            BLIND_POINCARE_TOP_PROVED BLIND_POINCARE_SMOOTH_PROVED; do
  if ! grep -Eq "^(# )*$name +hypotheses 0  conclusion.*: true\$" "$log_file"; then
    echo "$name was not proved with no hypotheses and the expected conclusion; see $log_file" >&2
    exit 1
  fi
done
if grep -Eq 'hypotheses [1-9]|: false$' "$log_file"; then
  echo "A checked theorem has hypotheses or an unexpected conclusion; see $log_file" >&2
  exit 1
fi
if [ "$(grep -Ec '^(# )*AXIOMS_COUNT 3$' "$log_file")" -ne 2 ]; then
  echo "Expected AXIOMS_COUNT 3 after both stages; see $log_file" >&2
  exit 1
fi

"$script_dir/../../common/check-failures.sh" "$log_file"
echo "Poincare development and audit completed successfully."
echo "Log: $log_file"

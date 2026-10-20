#!/bin/bash
# run.sh <hol-light dir> [log file]
#
# Runs HOL Light's complete Four Colour Theorem development through its OCaml
# 5 parallel bytecode target. FOURCOLOR_DOMAINS defaults to min(online CPUs,
# 128), matching 4CT/parallel.ml's documented runtime limit.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "run.sh <hol-light dir> [log file]" >&2
  exit 1
fi

hol_light_dir=$(cd "$1" && pwd)
log_file=${2:-"$(dirname "$hol_light_dir")/4ct-run.log"}
fourct_dir="$hol_light_dir/4CT"

if [ ! -x "$hol_light_dir/hol.sh" ]; then
  echo "$hol_light_dir/hol.sh is missing or not executable" >&2
  exit 1
fi
if [ ! -f "$fourct_dir/Makefile" ]; then
  echo "$fourct_dir/Makefile does not exist" >&2
  exit 1
fi

# Use the local opam switch with which this HOL Light checkout was built.
eval "$(opam env --switch "$hol_light_dir" --set-switch 2>/dev/null || opam env)"

ocaml_major=$(ocamlfind ocamlopt -version | cut -d. -f1)
if [ "$ocaml_major" -lt 5 ]; then
  echo "The parallel 4CT runner requires OCaml 5 or later; found $(ocamlfind ocamlopt -version)." >&2
  exit 1
fi

if [ -z "${FOURCOLOR_DOMAINS:-}" ]; then
  online_cores=$(getconf _NPROCESSORS_ONLN)
  if [ "$online_cores" -lt 128 ]; then
    FOURCOLOR_DOMAINS=$online_cores
  else
    FOURCOLOR_DOMAINS=128
  fi
fi
export FOURCOLOR_DOMAINS

if ! [[ "$FOURCOLOR_DOMAINS" =~ ^[1-9][0-9]*$ ]]; then
  echo "FOURCOLOR_DOMAINS must be a positive integer, got '$FOURCOLOR_DOMAINS'" >&2
  exit 1
fi

mkdir -p "$(dirname "$log_file")"
log_file=$(cd "$(dirname "$log_file")" && pwd)/$(basename "$log_file")

start_unixtime=$(date +%s)
{
  echo "HOL Light directory: $hol_light_dir"
  echo "4CT directory: $fourct_dir"
  echo "OCaml version: $(ocamlfind ocamlopt -version)"
  echo "FOURCOLOR_DOMAINS: $FOURCOLOR_DOMAINS"
  echo "Target: run-bytecode-parallel"
  echo "Start unixtime: $start_unixtime"
  echo
} > "$log_file"

set +e
make -C "$fourct_dir" \
  HOL="$hol_light_dir/hol.sh" \
  PARALLEL=yes \
  run-bytecode-parallel >> "$log_file" 2>&1
make_status=$?
set -e

end_unixtime=$(date +%s)
elapsed=$((end_unixtime - start_unixtime))
{
  echo
  echo "Running time: $elapsed sec, Start unixtime: $start_unixtime, End unixtime: $end_unixtime"
  echo "make exit status: $make_status"
} >> "$log_file"

if [ "$make_status" -ne 0 ]; then
  echo "The 4CT make target exited with status $make_status; see $log_file" >&2
  exit "$make_status"
fi

"$script_dir/../../common/check-failures.sh" "$log_file"

required_theorems=(FOUR_COLOR FOUR_COLOR_PLANAR_GRAPH FOUR_COLOR_MAP)
for theorem in "${required_theorems[@]}"; do
  if ! grep -q "^val $theorem : thm" "$log_file"; then
    echo "The log does not contain the final theorem $theorem; see $log_file" >&2
    exit 1
  fi
done

echo "FOUR_COLOR_THEOREMS_COMPLETED" >> "$log_file"
echo "Parallel 4CT proof completed successfully with $FOURCOLOR_DOMAINS domains."
echo "Log: $log_file"

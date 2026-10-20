#!/bin/bash
# run.sh <s2n-bignum dir> <arm|x86> <hol-light dir>
#
# Builds and checks the s2n-bignum HOL Light proofs for one architecture
# subdirectory (arm/ or x86/), then collects timing and the list of proven
# specifications.
#
# HOLDIR is pointed at an already-built hol-light checkout (the same one used
# by the hol-light benchmark, e.g.
#   holbench-workspace/holbench-.../hol-light
# ); we do not build HOL Light here.
#
# Parallelism (-j): both phases are memory-intensive -- the proof (run) phase
# because checking s2n-bignum proofs is memory-hungry, and the build phase
# because ocamlopt itself uses a lot of memory per concurrent process. So
# both are capped at the same heuristic: min(online cores, (total RAM in GB)
# / 6), reserving at least ~6 GB per concurrent job. NUMCORES /
# BUILD_NUMCORES override the run / build job counts respectively.
#
# Tutorials are intentionally not built or run here -- only the library
# proofs.
set -euo pipefail

# Resolve the directory of this script up front, before any cd below, so the
# path to the shared common/ helpers stays correct.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ "$#" -ne 3 ]; then
  echo "run.sh <s2n-bignum dir> <arm|x86> <hol-light dir>" >&2
  exit 1
fi

s2n_dir=$(cd "$1" && pwd)
arch=$2
hol_light_dir=$(cd "$3" && pwd)

case "$arch" in
  arm|x86) ;;
  *) echo "arch must be 'arm' or 'x86', got '$arch'" >&2; exit 1 ;;
esac

if [ ! -d "$s2n_dir/$arch" ]; then
  echo "$s2n_dir/$arch does not exist -- is '$s2n_dir' an s2n-bignum checkout?" >&2
  exit 1
fi
if [ ! -x "$hol_light_dir/hol.sh" ]; then
  echo "$hol_light_dir/hol.sh not found -- '$hol_light_dir' must be a built HOL Light checkout." >&2
  exit 1
fi

export HOLDIR="$hol_light_dir"

# Pick up the HOL Light opam switch so camlp5 / ocaml used by build-proof.sh
# match the ones HOL Light was built with.
eval "$(opam env --root "$hol_light_dir/_opam" --set-root 2>/dev/null || opam env)"

physical_cores=$(getconf _NPROCESSORS_ONLN)

mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
# (kB / 1024 / 1024) / 6 == kB / 6291456, rounded down.
mem_core_cap=$(( mem_total_kb / 6291456 ))
[ "$mem_core_cap" -lt 1 ] && mem_core_cap=1
if [ "$physical_cores" -lt "$mem_core_cap" ]; then
  default_cores=$physical_cores
else
  default_cores=$mem_core_cap
fi

# Run phase: cap at (total memory GB) / 6 -> at least ~6 GB per proof.
run_cores=${NUMCORES:-$default_cores}

# Build phase: compiling the .native binaries also runs ocamlopt per job,
# which can use substantial memory, so apply the same cap (still
# overridable).
build_cores=${BUILD_NUMCORES:-$default_cores}

echo "arch=$arch  HOLDIR=$HOLDIR"
echo "build -j$build_cores, run -j$run_cores (physical cores=$physical_cores)"

cd "$s2n_dir/$arch"

# Build the proof binaries first (lighter), then run the proofs
# (heavy, memory-capped). Tutorials are excluded.
make -j"$build_cores" HOLDIR="$HOLDIR" build_proofs
make -j"$run_cores"   HOLDIR="$HOLDIR" proofs

cd "$s2n_dir"

echo
echo "===== Running times (tools/collect-times.sh $arch) ====="
./tools/collect-times.sh "$arch"

echo
echo "===== Proven specifications (tools/collect-specs.sh $arch) ====="
./tools/collect-specs.sh "$arch"

echo
echo "===== Failure check (common/check-failures.sh) ====="
# Shared, benchmark-agnostic failure scan. Point it at the proof OUTPUT files
# only (the '*.correct' logs), NOT the whole arch tree -- the source .ml files
# legitimately contain the words 'Error:'/'Exception:' in string literals.
mapfile -t correct_files < <(find "$s2n_dir/$arch" -name '*.correct' -type f)
if [ "${#correct_files[@]}" -eq 0 ]; then
  echo "No *.correct files found under $s2n_dir/$arch (did 'make proofs' run?)." >&2
else
  "$script_dir/../../common/check-failures.sh" "${correct_files[@]}"
fi

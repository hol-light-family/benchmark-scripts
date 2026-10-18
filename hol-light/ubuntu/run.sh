#!/bin/bash
# run.sh <hol-light dir> [log dir]
#
# Runs holtest.mk against an already-initialized HOL Light checkout (see
# install-dependencies.sh). Prepends <hol-light dir>/external-bin, built by
# install-dependencies.sh, to PATH so cadical/lrat-trim/prover9 are picked up
# without a system-wide install.
#
# holtest.mk defaults its log directory to /tmp/hol-light-test, but every
# rule references the $(LOGDIR) make variable (there are no hardcoded
# /tmp/hol-light-test paths in its rules), so passing LOGDIR on the make
# command line fully redirects all output. Pass a second argument here to
# use a different log dir -- give each concurrent run its own, since runs
# share nothing else only when they also use separate checkouts.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "run.sh <hol-light dir> [log dir]" >&2
  exit 1
fi

hol_light_dir=$(cd "$1" && pwd)
log_dir=${2:-/tmp/hol-light-test}

bin_dir="$hol_light_dir/external-bin"
if [ -d "$bin_dir" ]; then
  export PATH="$bin_dir:$PATH"
fi

# Activate the local opam switch that lives in the HOL Light checkout
# ($hol_light_dir/_opam). Use --switch/--set-switch (NOT --root/--set-root):
# the latter only puts the switch bin on PATH loosely and leaves ocamlfind
# resolving to the system one, so `ocamlfind -package camlp5` fails -- which
# the Mizarlight rule needs to compile its camlp5 syntax extension.
eval "$(opam env --switch "$hol_light_dir" --set-switch 2>/dev/null || opam env)"

# Start from a clean log dir. Refuse to blow away a non-empty directory
# unless it already looks like one of our own log dirs (contains holtest.log
# or *.ready files), so a mistyped/shared path -- e.g. from a parallel run --
# can't silently wipe unrelated data.
if [ -e "$log_dir" ]; then
  if [ -n "$(ls -A "$log_dir" 2>/dev/null)" ] \
     && [ ! -e "$log_dir/holtest.log" ] \
     && ! ls "$log_dir"/*.ready >/dev/null 2>&1 \
     && ! ls "$log_dir"/*/*.ready >/dev/null 2>&1; then
    echo "Refusing to clear '$log_dir': it is non-empty and does not look" >&2
    echo "like a holtest log dir. Remove it yourself or pass a fresh path." >&2
    exit 1
  fi
  rm -rf "$log_dir"
fi
mkdir -p "$log_dir"

cd "$hol_light_dir"

# Choose the parallelism for holtest.mk. Each HOL Light test process can use
# a lot of RAM, so in addition to the physical core count we cap the job
# count at (total memory in GB) / 2 -- e.g. a 96 GB machine is limited to 48
# jobs even if it has more cores -- to avoid OOM from too many concurrent
# heavyweight proof checks. NUMCORES, if set, overrides both and is used
# verbatim.
if [ -n "${NUMCORES:-}" ]; then
  num_cores=$NUMCORES
else
  physical_cores=$(getconf _NPROCESSORS_ONLN)
  # MemTotal is in kB; (kB / 1024 / 1024) / 2 == kB / 2097152, rounded down.
  mem_total_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  mem_core_cap=$(( mem_total_kb / 2097152 ))
  [ "$mem_core_cap" -lt 1 ] && mem_core_cap=1
  if [ "$physical_cores" -lt "$mem_core_cap" ]; then
    num_cores=$physical_cores
  else
    num_cores=$mem_core_cap
  fi
fi

make -j"$num_cores" SHELL=bash -f holtest.mk all LOGDIR="$log_dir"

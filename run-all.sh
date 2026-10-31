#!/bin/bash
# run-all.sh <HOL Light repo URL> <commit-ish> [benchmark-results dir]
#            [runs parent]
#
# Creates a fresh HOL Light workspace, runs holtest, s2n-bignum ARM and x86,
# Flyspeck, Navier_Stokes, and parallel 4CT, writes all result JSON files to a
# dated directory under benchmark-results, and prepends the run to runs.json.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
  echo "run-all.sh <HOL Light repo URL> <commit-ish> [benchmark-results dir]" >&2
  echo "           [runs parent]" >&2
  exit 1
fi

hol_repo_url=$1
hol_commit_ish=$2
results_root=${3:-"$HOME/benchmark-results"}
runs_parent=${4:-"$HOME/holbench-runs"}

s2n_repo_url=${S2N_BIGNUM_REPO_URL:-https://github.com/awslabs/s2n-bignum.git}
s2n_commit=${S2N_BIGNUM_COMMIT:-6ea503b84f41688bd479d305dd2e4a3ef8ae1e7c}
flyspeck_repo_url=${FLYSPECK_REPO_URL:-https://github.com/hol-light-family/Flyspeck.git}
flyspeck_commit=${FLYSPECK_COMMIT:-51447cb63acd3af4190b7113438f6b5af4fc6951}
navier_stokes_repo_url=${NAVIER_STOKES_REPO_URL:-https://github.com/hol-light-family/Navier_Stokes.git}
navier_stokes_commit=${NAVIER_STOKES_COMMIT:-2b506b4288b5a94dc8394da7dfcd119ce88d2ac0}

mkdir -p "$results_root" "$runs_parent"
results_root=$(cd "$results_root" && pwd)
runs_parent=$(cd "$runs_parent" && pwd)

for command in git python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required but was not found on PATH" >&2
    exit 1
  fi
done

scripts_commit=$(git -C "$script_dir" rev-parse HEAD)
if git -C "$script_dir" diff --quiet --ignore-submodules -- \
   && git -C "$script_dir" diff --cached --quiet --ignore-submodules -- \
   && [ -z "$(git -C "$script_dir" ls-files --others --exclude-standard)" ]; then
  scripts_dirty=false
else
  scripts_dirty=true
fi

start_date=$(date -u +%Y-%m-%d)
create_log=$(mktemp)
trap 'rm -f "$create_log"' EXIT

echo "===== Create HOL Light workspace ====="
echo "Repository: $hol_repo_url"
echo "Revision:   $hol_commit_ish"
if ! "$script_dir/init/ubuntu/create-workspace.sh" \
    "$runs_parent" "$hol_repo_url" "$hol_commit_ish" switch-5 \
    > "$create_log" 2>&1; then
  cat "$create_log" >&2
  exit 1
fi

workspace=$(sed -n 's/^Workspace ready: //p' "$create_log" | tail -1)
if [ -z "$workspace" ] || [ ! -d "$workspace/hol-light" ]; then
  echo "Could not determine the workspace created by create-workspace.sh" >&2
  cat "$create_log" >&2
  exit 1
fi

hol_dir="$workspace/hol-light"
hol_commit=$(cat "$hol_dir/HOL_LIGHT_COMMIT")
if [ ! -x "$hol_dir/_opam/bin/ocamlc" ]; then
  echo "The workspace OCaml compiler is missing: $hol_dir/_opam/bin/ocamlc" >&2
  exit 1
fi
ocaml_version=$("$hol_dir/_opam/bin/ocamlc" -version)
if ! [[ "$ocaml_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+~._-][A-Za-z0-9.+~-]+)?$ ]]; then
  echo "The workspace returned an invalid OCaml version: $ocaml_version" >&2
  exit 1
fi
run_id="$start_date-$hol_commit"
result_dir="$results_root/$run_id"

if [ -e "$result_dir" ]; then
  echo "Result directory already exists: $result_dir" >&2
  echo "The fresh workspace was left at: $workspace" >&2
  exit 1
fi
mkdir -p "$workspace/logs" "$result_dir"
mv "$create_log" "$workspace/logs/create-workspace.log"
create_log="$workspace/logs/create-workspace.log"
trap - EXIT

echo "Workspace: $workspace"
echo "Results:   $result_dir"
echo "HOL Light: $hol_commit"
echo "OCaml:     $ocaml_version"
echo "Scripts:   $scripts_commit (dirty=$scripts_dirty)"

overall_status=0
record_failure() {
  echo "FAILED: $1" >&2
  overall_status=1
}

run_and_record() {
  local label=$1
  local log_file=$2
  shift 2
  echo
  echo "===== $label ====="
  echo "Log: $log_file"
  if "$@" > "$log_file" 2>&1; then
    echo "Completed: $label"
  else
    local status=$?
    record_failure "$label (exit $status)"
  fi
}

collect_and_record() {
  local label=$1
  local stdout_file=$2
  shift 2
  if "$@" > "$stdout_file"; then
    echo "Collected: $label"
  else
    local status=$?
    record_failure "$label collection (exit $status)"
  fi
}

# HOL Light holtest.
echo
echo "===== Prepare holtest dependencies ====="
"$script_dir/hol-light/ubuntu/install-dependencies.sh" "$hol_dir" \
  > "$workspace/logs/holtest-dependencies.log" 2>&1
run_and_record \
  "HOL Light holtest" \
  "$workspace/logs/holtest-run.log" \
  "$script_dir/hol-light/ubuntu/run.sh" "$hol_dir" "$workspace/holtest-logs"
collect_and_record \
  "HOL Light holtest" \
  "$workspace/logs/holtest-collect.stdout.json" \
  "$script_dir/hol-light/collect-results.py" \
  "$hol_dir" "$workspace/holtest-logs" \
  -o "$result_dir/hol-light-results.json"

# s2n-bignum, pinned by default for comparison across HOL Light runs.
echo
echo "===== Clone s2n-bignum ====="
"$script_dir/s2n-bignum/ubuntu/clone-repo.sh" \
  "$workspace" "$s2n_repo_url" "$s2n_commit" \
  > "$workspace/logs/s2n-clone.log" 2>&1
"$script_dir/s2n-bignum/ubuntu/install-dependencies.sh" \
  > "$workspace/logs/s2n-dependencies.log" 2>&1

for arch in arm x86; do
  run_and_record \
    "s2n-bignum $arch" \
    "$workspace/logs/s2n-$arch-run.log" \
    "$script_dir/s2n-bignum/ubuntu/run.sh" \
    "$workspace/s2n-bignum" "$arch" "$hol_dir"
  collect_and_record \
    "s2n-bignum $arch" \
    "$workspace/logs/s2n-$arch-collect.stdout.json" \
    "$script_dir/s2n-bignum/collect-results.py" \
    "$workspace/s2n-bignum" "$arch" --hol-light-dir "$hol_dir" \
    -o "$result_dir/s2n-bignum-$arch-results.json"
done

# Flyspeck, Navier_Stokes, and 4CT can safely overlap: Flyspeck's full
# sequence and the Navier_Stokes session are single-core (Navier_Stokes peaks
# at about 8 GB), while 4CT uses OCaml domains and the run script enforces its
# own limit.
echo
echo "===== Clone Flyspeck ====="
"$script_dir/Flyspeck/ubuntu/clone-repo.sh" \
  "$workspace" "$flyspeck_repo_url" "$flyspeck_commit" \
  > "$workspace/logs/flyspeck-clone.log" 2>&1

echo
echo "===== Clone Navier_Stokes ====="
"$script_dir/navier-stokes/ubuntu/clone-repo.sh" \
  "$workspace" "$navier_stokes_repo_url" "$navier_stokes_commit" \
  > "$workspace/logs/navier-stokes-clone.log" 2>&1

echo
echo "===== Start Flyspeck, Navier_Stokes, and parallel 4CT ====="
"$script_dir/Flyspeck/ubuntu/run.sh" \
  "$workspace/Flyspeck" "$hol_dir" "$workspace/logs/flyspeck-run.log" \
  > "$workspace/logs/flyspeck-run-wrapper.log" 2>&1 &
flyspeck_pid=$!

"$script_dir/navier-stokes/ubuntu/run.sh" \
  "$workspace/Navier_Stokes" "$hol_dir" "$workspace/logs/navier-stokes-run.log" \
  > "$workspace/logs/navier-stokes-run-wrapper.log" 2>&1 &
navier_stokes_pid=$!

"$script_dir/4CT/ubuntu/run.sh" \
  "$hol_dir" "$workspace/logs/4ct-run.log" \
  > "$workspace/logs/4ct-run-wrapper.log" 2>&1 &
fourct_pid=$!

if wait "$flyspeck_pid"; then
  echo "Completed: Flyspeck"
else
  status=$?
  record_failure "Flyspeck (exit $status)"
fi
if wait "$navier_stokes_pid"; then
  echo "Completed: Navier_Stokes"
else
  status=$?
  record_failure "Navier_Stokes (exit $status)"
fi
if wait "$fourct_pid"; then
  echo "Completed: 4CT"
else
  status=$?
  record_failure "4CT (exit $status)"
fi

collect_and_record \
  "Flyspeck" \
  "$workspace/logs/flyspeck-collect.stdout.json" \
  "$script_dir/Flyspeck/collect-results.py" \
  "$workspace/Flyspeck" "$workspace/logs/flyspeck-run.log" \
  --hol-light-dir "$hol_dir" -o "$result_dir/flyspeck-results.json"
collect_and_record \
  "Navier_Stokes" \
  "$workspace/logs/navier-stokes-collect.stdout.json" \
  "$script_dir/navier-stokes/collect-results.py" \
  "$workspace/Navier_Stokes" "$workspace/logs/navier-stokes-run.log" \
  --hol-light-dir "$hol_dir" -o "$result_dir/navier-stokes-results.json"
collect_and_record \
  "4CT" \
  "$workspace/logs/4ct-collect.stdout.json" \
  "$script_dir/4CT/collect-results.py" \
  "$hol_dir" "$workspace/logs/4ct-run.log" \
  -o "$result_dir/4ct-results.json"

# Publish the run to the results index only if all six report files exist.
export RUN_ALL_RESULT_DIR="$result_dir"
export RUN_ALL_RESULTS_ROOT="$results_root"
export RUN_ALL_RUN_ID="$run_id"
export RUN_ALL_DATE="$start_date"
export RUN_ALL_HOL_COMMIT="$hol_commit"
export RUN_ALL_OCAML_VERSION="$ocaml_version"
export RUN_ALL_HOL_REPO="$hol_repo_url"
export RUN_ALL_SCRIPTS_COMMIT="$scripts_commit"
export RUN_ALL_SCRIPTS_DIRTY="$scripts_dirty"

python3 <<'PY'
import json
import os
import re
from pathlib import Path

result_dir = Path(os.environ["RUN_ALL_RESULT_DIR"])
results_root = Path(os.environ["RUN_ALL_RESULTS_ROOT"])
run_id = os.environ["RUN_ALL_RUN_ID"]
report_entries = [
    ("HOL Light", "hol-light-results.json"),
    ("s2n-bignum ARM", "s2n-bignum-arm-results.json"),
    ("s2n-bignum x86", "s2n-bignum-x86-results.json"),
    ("Flyspeck", "flyspeck-results.json"),
    ("Navier-Stokes", "navier-stokes-results.json"),
    ("Four Colour Theorem", "4ct-results.json"),
]
missing = [name for _, name in report_entries if not (result_dir / name).is_file()]
if missing:
    raise SystemExit(f"Cannot index the run; missing reports: {', '.join(missing)}")

def github_web_url(url: str) -> str:
    url = re.sub(r"^git@github\.com:", "https://github.com/", url)
    return url.removesuffix(".git").rstrip("/")

hol_repository = github_web_url(os.environ["RUN_ALL_HOL_REPO"])
match = re.search(r"github\.com/([^/]+)/", hol_repository)
owner = match.group(1) if match else "custom"
hol_label = "HOL Light" if owner == "jrh13" else f"HOL Light ({owner})"

manifest = {
    "id": run_id,
    "date": os.environ["RUN_ALL_DATE"],
    "hol_light_label": hol_label,
    "hol_light_commit": os.environ["RUN_ALL_HOL_COMMIT"],
    "ocaml_version": os.environ["RUN_ALL_OCAML_VERSION"],
    "benchmark_scripts_commit": os.environ["RUN_ALL_SCRIPTS_COMMIT"],
    "benchmark_scripts_dirty": os.environ["RUN_ALL_SCRIPTS_DIRTY"] == "true",
    "repositories": {
        "HOL Light": hol_repository,
        "s2n-bignum": "https://github.com/awslabs/s2n-bignum",
        "Flyspeck": "https://github.com/hol-light-family/Flyspeck",
        "Navier-Stokes": "https://github.com/hol-light-family/Navier_Stokes",
        "benchmark-scripts": "https://github.com/hol-light-family/benchmark-scripts",
    },
    "reports": [{"label": label, "file": name} for label, name in report_entries],
}
(result_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

index_path = results_root / "runs.json"
index = json.loads(index_path.read_text()) if index_path.is_file() else {"runs": []}
entry = {
    "id": run_id,
    "date": manifest["date"],
    "hol_light_label": hol_label,
    "hol_light_commit": manifest["hol_light_commit"],
    "ocaml_version": manifest["ocaml_version"],
    "benchmark_scripts_commit": manifest["benchmark_scripts_commit"],
    "manifest": f"{run_id}/manifest.json",
}
index["runs"] = [entry] + [run for run in index.get("runs", []) if run.get("id") != run_id]
index_path.write_text(json.dumps(index, indent=2) + "\n")
PY

echo
echo "===== Result summary ====="
python3 - "$result_dir" <<'PY'
import json
import sys
from pathlib import Path

result_dir = Path(sys.argv[1])
for path in sorted(result_dir.glob("*-results.json")):
    data = json.loads(path.read_text())
    print(f"{path.name}: {data['counts']}")
PY

echo
echo "Workspace: $workspace"
echo "Results:   $result_dir"
if [ "$overall_status" -ne 0 ]; then
  echo "One or more benchmarks or collectors failed." >&2
fi
exit "$overall_status"

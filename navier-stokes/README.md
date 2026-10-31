# Navier-Stokes benchmark scripts

Scripts for loading and checking the complete
[Navier_Stokes](https://github.com/hol-light-family/Navier_Stokes) HOL Light
formalization of finite-time blowup for the Navier-Stokes equations, together
with its statement audit.

In command descriptions, `<argument>` is required and `[argument]` is
optional. Replace the argument name with a value; do not type the brackets.

## Scripts

| Script | Purpose |
| --- | --- |
| `ubuntu/clone-repo.sh <workspace dir> [repo URL] [commit-ish]` | Clones Navier_Stokes into `<workspace dir>/Navier_Stokes`. Defaults to `https://github.com/hol-light-family/Navier_Stokes.git` at its latest default-branch commit (`HEAD`) and records the resolved commit in `NAVIER_STOKES_COMMIT`. |
| `ubuntu/run.sh <Navier_Stokes dir> <hol-light dir> [log file]` | Loads `check.ml` and then `audit/check.ml` in one HOL Light session started in the repository root. The default log is `<workspace dir>/navier-stokes-run.log`. |
| `collect-results.py <Navier_Stokes dir> [log file] [--hol-light-dir DIR] [-o out.json] [--no-write]` | Emits a two-test JSON report (development and audit) with per-stage timing, the checked theorem names, the Navier_Stokes/HOL Light commits, and shared machine metadata. Defaults to `<workspace dir>/navier-stokes-results.json`. |

## Typical flow

```bash
WS=~/holbench-runs/holbench-...

# Clone the latest default-branch commit. Pass URL and commit-ish to pin it.
navier-stokes/ubuntu/clone-repo.sh "$WS"

# Load the development and the audit.
navier-stokes/ubuntu/run.sh "$WS/Navier_Stokes" "$WS/hol-light" \
  "$WS/logs/navier-stokes-run.log"
navier-stokes/collect-results.py "$WS/Navier_Stokes" \
  "$WS/logs/navier-stokes-run.log"
```

`run.sh` pipes the following into `hol.sh` with `LINE_EDITOR=env`, as the
Navier_Stokes README documents (ledit would echo the input into the log):

```ocaml
loadt "check.ml";;
loadt "audit/check.ml";;
```

Each `loadt` is bracketed by `NAVIER_STOKES_STAGE_START <stage> <unix time>`
and `NAVIER_STOKES_STAGE_END ...` lines. These are printed by a child `date`
process because `Unix` is not loaded in the HOL Light toplevel.
`audit/make.ml` reaches the development through `needs "make.ml"`, so the
audit stage loads only the audit files.

## Stages and success criteria

| Test | What it loads | Pass requires |
| --- | --- | --- |
| `Navier_Stokes/check.ml` | HOL Light `Multivariate/cauchy.ml`, `Multivariate/lpspaces.ml`, `100/green.ml`, then all of `src/` via `make.ml` | `NAVIER_STOKES_CHECK_DONE`; `NS_BREAKDOWN_PERIODIC`, `NS_BREAKDOWN_R3`, `NS_THEOREM_1_1_FULL`, `NS_THEOREM_1_1`, `NS_THEOREM_3_1_HEAT`, `NS_THEOREM_3_1` with no hypotheses and exactly their statement constant as conclusion; `NS_HEAT_SWIRL_PDE` with no hypotheses; `AXIOMS_COUNT 3` |
| `Navier_Stokes/audit/check.ml` | `audit/make.ml`: the independent Clay formalization, its equivalence proof, and the sanity theorems | `NAVIER_STOKES_AUDIT_CHECK_DONE`; `CLAY_BLIND_{C,D}_PROVED` and `NS_CLAY_{C,D}_EQUIV_BLIND` with no hypotheses and the expected conclusions; every `NS_SANITY_*` theorem with no hypotheses and a count matching `SANITY_THEOREMS`; `AXIOMS_COUNT 3` |

A stage also fails if its part of the log contains a failure marker (the same
rule as `../common/check-failures.sh`) or if the session ends before the
stage's END marker. A stage with no START marker is `missing`. The OCaml
toplevel keeps going after a failed `loadt`, so these checks, not the HOL Light
exit status, decide the result. `run.sh` applies the same checks in a coarser
form and exits nonzero if any fails.

## Resources

Upstream reports about 91 minutes of CPU time for one core in a fresh
bytecode session, with peak memory near 7.6 GB. Most of that time is HOL
Light's Multivariate library (about 26 minutes) and the development itself
(about 65 minutes). The audit adds a few minutes. On a 192-core arm64
machine with OCaml 5.5, the full run took 58 minutes of wall time: 57 for
`check.ml` and 15 seconds for the audit. `run-all.sh` runs this benchmark next
to Flyspeck and parallel 4CT because it is single-core.

## HOL Light version

The Navier_Stokes README names the HOL Light commit and OCaml version it was
tested with (`924faf0c`, OCaml 4.14.1). Other HOL Light checkouts and OCaml 5
switches may also work; the full run is the compatibility check.

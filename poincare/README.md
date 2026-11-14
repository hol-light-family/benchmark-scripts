# Poincare benchmark scripts

Scripts for loading and checking the complete
[Poincare](https://github.com/hol-light-family/Poincare) HOL Light
formalization of the Poincare conjecture, following Perelman's proof as
presented by Morgan and Tian, together with Moise's theorem that every
topological 3-manifold has a smooth structure, together with its statement
audit.

In command descriptions, `<argument>` is required and `[argument]` is
optional. Replace the argument name with a value; do not type the brackets.

## Scripts

| Script | Purpose |
| --- | --- |
| `ubuntu/clone-repo.sh <workspace dir> [repo URL] [commit-ish]` | Clones Poincare into `<workspace dir>/Poincare`. Defaults to `https://github.com/hol-light-family/Poincare.git` at its latest default-branch commit (`HEAD`) and records the resolved commit in `POINCARE_COMMIT`. |
| `ubuntu/run.sh <Poincare dir> <hol-light dir> [log file]` | Loads `check.ml` and then `audit/check.ml` in one HOL Light session started in the repository root. The default log is `<workspace dir>/poincare-run.log`. |
| `collect-results.py <Poincare dir> [log file] [--hol-light-dir DIR] [-o out.json] [--no-write]` | Emits a two-test JSON report (development and audit) with per-stage timing, the checked theorem names, the axiom counts, the Poincare/HOL Light commits, and shared machine metadata. Defaults to `<workspace dir>/poincare-results.json`. |

## Typical flow

```bash
WS=~/holbench-runs/holbench-...

# Clone the latest default-branch commit. Pass URL and commit-ish to pin it.
poincare/ubuntu/clone-repo.sh "$WS"

# Load the development and the audit.
poincare/ubuntu/run.sh "$WS/Poincare" "$WS/hol-light" \
  "$WS/logs/poincare-run.log"
poincare/collect-results.py "$WS/Poincare" \
  "$WS/logs/poincare-run.log"
```

`run.sh` pipes the following into `hol.sh` with `LINE_EDITOR=env`, as the
Poincare README documents (ledit would echo the input into the log):

```ocaml
loadt "check.ml";;
loadt "audit/check.ml";;
```

`check.ml` loads `make.ml`, which sets the garbage collector's
`space_overhead` to 40, loads HOL Light's `Multivariate/cauchy.ml`,
`Multivariate/lpspaces.ml` and `100/green.ml`, then all of `src/`. It then
prints one line per headline theorem and the axioms. `audit/make.ml` starts
with `loadt "make.ml"`, but `make.ml` loads everything with `needs`, so the
audit stage loads only the audit files.

Each `loadt` is bracketed by `POINCARE_STAGE_START <stage> <unix time>` and
`POINCARE_STAGE_END ...` lines. These are printed by a child `date` process
because `Unix` is not loaded in the HOL Light toplevel.

## Stages and success criteria

| Test | What it loads | Pass requires |
| --- | --- | --- |
| `Poincare/check.ml` | HOL Light `Multivariate/cauchy.ml`, `Multivariate/lpspaces.ml`, `100/green.ml`, then all of `src/` via `make.ml` | `POINCARE_CHECK_DONE`; `POINCARE_TOP`, `POINCARE_SMOOTH`, and `POINCARE_EMBEDDED` with no hypotheses and exactly their statement constant applied to `(:A)` for a type variable `A`; `MOI_SST_HEADLINE` with no hypotheses and conclusion `!u:A->bool. MOISE_SMOOTHING_STATEMENT u`; `AXIOMS_COUNT 3` |
| `Poincare/audit/check.ml` | `audit/make.ml`: an independent formalization of both forms of the conjecture, its equivalence proof, and the sanity theorems | `POINCARE_AUDIT_CHECK_DONE`; `POINCARE_TOP_BLIND_EQUIV`, `POINCARE_SMOOTH_BLIND_EQUIV`, `BLIND_POINCARE_TOP_PROVED`, and `BLIND_POINCARE_SMOOTH_PROVED` with no hypotheses and the expected conclusions; every sanity theorem with no hypotheses and a count matching `SANITY_THEOREMS`; `AXIOMS_COUNT 3` |

`check.ml` and `audit/check.ml` themselves decide whether each conclusion is
the expected one and print `true` or `false`; the scripts read those verdicts.
A stage also fails if its part of the log contains a failure marker (the same
rule as `../common/check-failures.sh`) or if the session ends before the
stage's END marker. A stage with no START marker is `missing`. The OCaml
toplevel keeps going after a failed `loadt`, so these checks, not the HOL
Light exit status, decide the result. `run.sh` applies the same checks in a
coarser form and exits nonzero if any fails.

## Resources

Upstream reports 418 minutes (7.0 hours) of CPU time on one core in a fresh
bytecode session with HOL Light `e5236a58`, with peak memory about 17.5 GiB:
27 minutes for HOL Light's Multivariate prerequisites and 390 minutes for the
development itself. The audit adds less than a minute. `run-all.sh` runs this benchmark next to the other
single-core benchmarks.

## HOL Light version

The Poincare README recommends HOL Light `e5236a58` (OCaml 4.14.1) and says it
also loads with `2828953e` and `924faf0c`. Other HOL Light checkouts and OCaml
5 switches may also work; the full run is the compatibility check.

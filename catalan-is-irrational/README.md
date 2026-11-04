# catalan-is-irrational benchmark scripts

Scripts for loading and checking the complete
[catalan-is-irrational](https://github.com/hol-light-family/catalan-is-irrational)
HOL Light formalization of the irrationality of Catalan's constant.

In command descriptions, `<argument>` is required and `[argument]` is
optional. Replace the argument name with a value; do not type the brackets.

## Scripts

| Script | Purpose |
| --- | --- |
| `ubuntu/clone-repo.sh <workspace dir> [repo URL] [commit-ish]` | Clones catalan-is-irrational into `<workspace dir>/catalan-is-irrational`. Defaults to `https://github.com/hol-light-family/catalan-is-irrational.git` at its latest default-branch commit (`HEAD`) and records the resolved commit in `CATALAN_IS_IRRATIONAL_COMMIT`. |
| `ubuntu/run.sh <catalan-is-irrational dir> <hol-light dir> [log file]` | Loads `make.ml` in one HOL Light session started in the repository root, then checks the headline theorems and the axiom count. The default log is `<workspace dir>/catalan-is-irrational-run.log`. |
| `collect-results.py <catalan-is-irrational dir> [log file] [--hol-light-dir DIR] [-o out.json] [--no-write]` | Emits a one-test JSON report with timing, the checked theorem names, the axiom count, the catalan-is-irrational/HOL Light commits, and shared machine metadata. Defaults to `<workspace dir>/catalan-is-irrational-results.json`. |

## Typical flow

```bash
WS=~/holbench-runs/holbench-...

# Clone the latest default-branch commit. Pass URL and commit-ish to pin it.
catalan-is-irrational/ubuntu/clone-repo.sh "$WS"

# Load the development and check its headline theorems.
catalan-is-irrational/ubuntu/run.sh "$WS/catalan-is-irrational" "$WS/hol-light" \
  "$WS/logs/catalan-is-irrational-run.log"
catalan-is-irrational/collect-results.py "$WS/catalan-is-irrational" \
  "$WS/logs/catalan-is-irrational-run.log"
```

`run.sh` pipes `loadt "make.ml";;` into `hol.sh` with `LINE_EDITOR=env`, as the
catalan-is-irrational README documents (ledit would echo the input into the
log). `make.ml` loads HOL Light's `100/pnt.ml` (and with it
`Multivariate/cauchy.ml`) and `Library/ring_det.ml`, then the development,
and ends with `check_axioms ()`.

The load is bracketed by `CATALAN_STAGE_START make.ml <unix time>` and
`CATALAN_STAGE_END ...` lines. These are printed by a child `date` process
because `Unix` is not loaded in the HOL Light toplevel. After the load, the
session prints one `CATALAN_THEOREM <name> hypotheses <n> conclusion <bool>`
line per headline theorem and a `CATALAN_AXIOMS_COUNT <n>` line.

## Success criteria

| Test | What it loads | Pass requires |
| --- | --- | --- |
| `catalan-is-irrational/make.ml` | HOL Light `100/pnt.ml`, `Library/ring_det.ml`, then all of `src/` via `src/catalan_main.ml` | `CATALAN_CONSTANT_IRRATIONAL_HEADLINE`, `CATALAN_CONSTANT_IRRATIONAL`, and `CATALAN_IRRATIONAL` with no hypotheses and exactly the expected conclusion; `CATALAN_AXIOMS_COUNT 3` |

The expected conclusions are written in `run.sh`, independently of the
development, and compared with `aconv`:

- `CATALAN_CONSTANT_IRRATIONAL_HEADLINE`: the series
  `sum_j (-1)^j / (2j+1)^2` converges (`real_sums ... (from 0)`), and its sum
  is not `m / n` for integers `m`, `n` with `n` nonzero. This uses only HOL
  Light's own notions, so it checks the result without trusting the
  development's definitions.
- `CATALAN_CONSTANT_IRRATIONAL`: `~(rational catalan_constant)`.
- `CATALAN_IRRATIONAL`: `CATALAN_IRRATIONAL_STATEMENT`.

The test also fails if the log after the START marker contains a failure
marker (the same rule as `../common/check-failures.sh`) or if the session ends
before the END marker. A test with no START marker is `missing`. The OCaml
toplevel keeps going after a failed `loadt`, so these checks, not the HOL Light
exit status, decide the result. `run.sh` applies the same checks and exits
nonzero if any fails.

## Resources

Upstream reports about an hour on one core (62 minutes in its test),
including HOL Light's prerequisites. Most of the development's own time goes
to the exact arithmetic of the real-place certificate (about 22 minutes) and
to `Library/ring_det.ml`. On a 192-core arm64 machine with OCaml 5.5 and HOL
Light `31fe213`, loading `make.ml` took 51 minutes of wall time.
`run-all.sh` runs this benchmark next to Flyspeck, Navier_Stokes, and parallel
4CT because it is single-core.

## HOL Light version

The catalan-is-irrational README names the HOL Light commit it was tested
with (`31fe213`). Other HOL Light checkouts may also work; the full run is the
compatibility check.

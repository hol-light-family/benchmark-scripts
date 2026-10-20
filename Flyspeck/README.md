# Flyspeck benchmark scripts

Scripts for loading the complete [Flyspeck](https://github.com/hol-light-family/Flyspeck)
HOL Light proof through the final command documented in `load_flyspeck.ml`.

In command descriptions, `<argument>` is required and `[argument]` is
optional. Replace the argument name with a value; do not type the brackets.

## Scripts

| Script | Purpose |
| --- | --- |
| `ubuntu/clone-repo.sh <workspace dir> [repo URL] [commit-ish]` | Clones Flyspeck into `<workspace dir>/Flyspeck`. Defaults to `https://github.com/hol-light-family/Flyspeck.git` at its latest default-branch commit (`HEAD`) and records the resolved commit in `FLYSPECK_COMMIT`. |
| `ubuntu/run.sh <Flyspeck dir> <hol-light dir> [log file]` | Loads `load_flyspeck.ml`, then runs the complete `Build.build_sequence_full`. The default log is `<workspace dir>/flyspeck-run.log`. |
| `collect-results.py <Flyspeck dir> [log file] [--hol-light-dir DIR] [-o out.json] [--no-write]` | Emits a one-test JSON report with timing, Flyspeck/HOL Light commits, and shared machine metadata. Defaults to `<workspace dir>/flyspeck-results.json`. |

## Typical flow

```bash
WS=~/holbench-runs/holbench-...

# Clone the latest default-branch commit. Pass URL and commit-ish to pin it.
Flyspeck/ubuntu/clone-repo.sh "$WS"

# Load the full proof.
Flyspeck/ubuntu/run.sh "$WS/Flyspeck" "$WS/hol-light" \
  "$WS/logs/flyspeck-run.log"
Flyspeck/collect-results.py "$WS/Flyspeck" "$WS/logs/flyspeck-run.log"
```

`run.sh` sets the two environment variables required by `load_flyspeck.ml`:

- `FLYSPECK_DIR=<Flyspeck dir>/text_formalization`
- `HOLLIGHT_DIR=<hol-light dir>`

It then executes:

```ocaml
needs "load_flyspeck.ml";;
let _ = map flyspeck_needs Build.build_sequence_full in
  print_endline "FLYSPECK_BUILD_SEQUENCE_FULL_COMPLETED";;
```

The wrapper emits the marker only after the complete sequence returns. It
also records start/end Unix times, checks the log with
`../common/check-failures.sh`, and exits nonzero if HOL Light exits nonzero,
the marker is absent, or the failure scan finds an error.

## Scope of the full sequence

As described in Flyspeck's `load_flyspeck.ml`, `Build.build_sequence_full`:

- verifies the archived linear-program bounds,
- loads the theorem that imports the nonlinear inequalities against their
  recorded digests, and
- reaches the Kepler-conjecture result whose remaining tame-classification
  assumption is verified separately in Isabelle.

The nonlinear inequalities themselves are not recomputed; doing so was an
optional Azure computation requiring thousands of processor-hours. The full
sequence uses their checked digests as documented by Flyspeck.

## HOL Light version

Flyspeck's `INSTALL.md` states the HOL Light commit against which it was tested.
A different HOL Light checkout may work, but the full run is the compatibility
check.

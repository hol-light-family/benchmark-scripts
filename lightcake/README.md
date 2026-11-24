# LightCake benchmark scripts

Scripts for loading and checking
[LightCake](https://github.com/hol-light-family/LightCake), the HOL Light
port of the CakeML compiler correctness proof (HOL4's
`compilerProofTheory.compile_correct` and its ag32 instance
`ag32_configProofTheory.ag32_compile_correct`).

In command descriptions, `<argument>` is required and `[argument]` is
optional. Replace the argument name with a value; do not type the brackets.

## Scripts

| Script | Purpose |
| --- | --- |
| `ubuntu/clone-repo.sh <workspace dir> [repo URL] [commit-ish]` | Clones LightCake into `<workspace dir>/LightCake`. Defaults to `https://github.com/hol-light-family/LightCake.git` at its latest default-branch commit (`HEAD`) and records the resolved commit in `LIGHTCAKE_COMMIT`. |
| `ubuntu/run.sh <LightCake dir> <hol-light dir> [log file]` | Loads `check.ml` in one HOL Light session started in the repository root. The default log is `<workspace dir>/lightcake-run.log`. |
| `collect-results.py <LightCake dir> [log file] [--hol-light-dir DIR] [-o out.json] [--no-write]` | Emits a one-test JSON report with timing, the checked theorem names, the axiom count, any files that did not load, the LightCake/HOL Light commits, and shared machine metadata. Defaults to `<workspace dir>/lightcake-results.json`. |

## Typical flow

```bash
WS=~/holbench-runs/holbench-...

# Clone the latest default-branch commit. Pass URL and commit-ish to pin it.
lightcake/ubuntu/clone-repo.sh "$WS"

# Load the port and check its headline theorems.
lightcake/ubuntu/run.sh "$WS/LightCake" "$WS/hol-light" \
  "$WS/logs/lightcake-run.log"
lightcake/collect-results.py "$WS/LightCake" \
  "$WS/logs/lightcake-run.log"
```

`run.sh` pipes `loadt "check.ml";;` into `hol.sh` with `LINE_EDITOR=env`
(ledit would echo the input into the log). `check.ml` loads `make.ml`, which
sets `use_file_raise_failure := true`, loads `src/prelude.ml` (HOL Light's
`Library/words.ml`, `Library/rstc.ml`, `Library/iter.ml` and the proof kit)
and then every file of the port with `needs`. After the load, `check.ml`
prints:

- `NOT LOADED <file>` for every expected file missing from `loaded_files`,
- `AXIOMS_COUNT <n>` and one `AXIOM <term>` line per axiom,
- `HEADLINE <bool>`: `compilerProof_compile_correct` and
  `compile_correct_safe_for_space` have no hypotheses and their conclusions
  are alpha-equivalent to the statements of
  `src/compiler/proofs/compile_correct_statement.ml`,
- `HEADLINE_AG32 <bool>`: the same for `ag32_compile_correct` and
  `src/compiler/backend/ag32/proofs/ag32_compile_correct_statement.ml`,
- `CHECK_OK` if all of the above hold, otherwise `CHECK_FAILED`.

The load is bracketed by `LIGHTCAKE_STAGE_START check.ml <unix time>` and
`LIGHTCAKE_STAGE_END ...` lines. These are printed by a child `date` process
because `Unix` is not loaded in the HOL Light toplevel.

## Success criteria

| Test | What it loads | Pass requires |
| --- | --- | --- |
| `LightCake/check.ml` | HOL Light `Library/words.ml`, `Library/rstc.ml`, `Library/iter.ml`, then all of `src/` via `make.ml` | `CHECK_OK`; no `NOT LOADED` lines; `AXIOMS_COUNT 3`; `HEADLINE true`; `HEADLINE_AG32 true` |

The statements the headline theorems are compared with are files of the port,
written in terms of its own definitions, so this benchmark trusts those
statement files (unlike catalan-is-irrational, whose `run.sh` writes the
expected statement independently).

The test also fails if the log between the START and END markers contains a
failure marker (the markers of `../common/check-failures.sh`, but only at the
start of a line, because HOL Light echoes definitions containing strings such as
`### ERROR: parse error` on indented lines) or if the
session ends before the END marker. A test with no START marker is `missing`.
The OCaml toplevel keeps going after a failed `loadt`, so these checks, not
the HOL Light exit status, decide the result. `run.sh` applies the same checks
and exits nonzero if any fails.

## Resources

Upstream reports 1.6 hours for `check.ml` with HOL Light `1a0c0e6` plus
jrh13/hol-light pull request #215, 1.6 hours with jargh/hol-light-dev
`55cac39` (jrh13/hol-light pull request #218), and 3.3 hours with HOL Light
`6dbb775`. The session is single-core, so `run-all.sh` runs this benchmark
next to the other single-core benchmarks.

## HOL Light version

The LightCake README requires HOL Light commit `2828953` (10 November 2026)
or later. Older checkouts fail while loading, not just more slowly.

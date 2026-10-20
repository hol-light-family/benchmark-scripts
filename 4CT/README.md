# HOL Light 4CT benchmark scripts

Scripts for running HOL Light's complete Four Colour Theorem development from
the `4CT/` directory in a HOL Light checkout.

In command descriptions, `<argument>` is required and `[argument]` is
optional. Replace the argument name with a value; do not type the brackets.

## Scripts

| Script | Purpose |
| --- | --- |
| `ubuntu/run.sh <hol-light dir> [log file]` | Runs `4CT`'s OCaml 5 parallel bytecode target and checks that `FOUR_COLOR`, `FOUR_COLOR_PLANAR_GRAPH`, and `FOUR_COLOR_MAP` were produced. Defaults to `<workspace dir>/4ct-run.log`. |
| `collect-results.py <hol-light dir> [log file] [-o out.json] [--no-write]` | Emits a one-test JSON report with timing, domain count, theorem names, HOL Light commit, and shared machine metadata. Defaults to `<workspace dir>/4ct-results.json`. |

## Typical flow

```bash
WS=~/holbench-runs/holbench-...

4CT/ubuntu/run.sh "$WS/hol-light" "$WS/logs/4ct-run.log"
4CT/collect-results.py "$WS/hol-light" "$WS/logs/4ct-run.log"
```

## Parallelism

The runner invokes:

```bash
make -C <hol-light dir>/4CT PARALLEL=yes run-bytecode-parallel
```

This loads `4CT/make_parallel.ml`. Its proof-producing computations use
`FOURCOLOR_DOMAINS` OCaml domains in one process. The runner defaults that
variable to the smaller of the number of online CPUs and 128, matching the
limit documented by `4CT/parallel.ml`. Set `FOURCOLOR_DOMAINS` to a positive
integer to override it.

The HOL Light `4CT/README.md` estimates about 1.5 hours and 60 GB for this
parallel bytecode route. The native route runs faster after compilation but
requires a separate native build estimated at about 2.5 hours and 50 GB, so
this benchmark uses bytecode for lower total turnaround time.

## Success criteria

The run passes only when:

- the make target exits successfully,
- the shared failure scanner finds no error marker,
- all three final theorem bindings appear in the log, and
- the runner appends `FOUR_COLOR_THEOREMS_COMPLETED`.

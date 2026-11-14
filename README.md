# HOL benchmark scripts

Scripts for creating a fresh HOL Light workspace and running benchmark families.

Published reports and the browser dashboard live in the companion
[benchmark-results repository](https://github.com/hol-light-family/benchmark-results/).

In command descriptions, `<argument>` is required and `[argument]` is
optional. Replace the argument name with a value; do not type the brackets.

## Run the complete suite

`run-all.sh` creates a workspace, runs every benchmark, writes the eight JSON
reports and a manifest under the requested results directory, and prepends the
run to `runs.json`:

```bash
./run-all.sh \
  <HOL Light repo URL> \
  <commit-ish> \
  [benchmark-results dir] \
  [runs parent output dir]
```

The last two arguments default to `~/benchmark-results` and
`~/holbench-runs`. For example:

```bash
./run-all.sh \
  https://github.com/jrh13/hol-light.git \
  <HOL Light commit>
```

s2n-bignum, Flyspeck, Navier_Stokes, catalan-is-irrational, and Poincare
default to the latest commit (`HEAD`) of their default branches. The resolved commits are printed and recorded in
the result files. To pin specific revisions instead:

```bash
S2N_BIGNUM_COMMIT=<commit-ish> \
FLYSPECK_COMMIT=<commit-ish> \
NAVIER_STOKES_COMMIT=<commit-ish> \
CATALAN_IS_IRRATIONAL_COMMIT=<commit-ish> \
POINCARE_COMMIT=<commit-ish> \
  ./run-all.sh <HOL Light repo URL> <commit-ish>
```

The script runs the major stages sequentially, except Flyspeck, Navier-Stokes,
catalan-is-irrational, Poincare, and parallel 4CT. Those five overlap because
Flyspeck, Navier-Stokes, catalan-is-irrational, and Poincare are single-core. If a benchmark fails,
the script still attempts to collect its report and continue, then exits nonzero.
It refuses to overwrite an existing result directory.

## Create a workspace

Start by creating and building a fresh HOL Light workspace:

```bash
mkdir -p ~/holbench-runs
./init/ubuntu/create-workspace.sh ~/holbench-runs
```

The command creates a timestamped directory such as:

```text
~/holbench-runs/holbench-YYYY-MM-DD-HH.MM.<unix-time>/
└── hol-light/
```

Its full syntax is:

```text
init/ubuntu/create-workspace.sh <parent dir> [repo URL] [commit-ish] [switch|switch-5]
```

Defaults:

- repository: `https://github.com/jrh13/hol-light`
- revision: `HEAD`, resolved to the latest default-branch commit
- opam target: `switch-5`

For a reproducible run, pass a commit explicitly:

```bash
./init/ubuntu/create-workspace.sh \
  ~/holbench-runs \
  https://github.com/jrh13/hol-light \
  <HOL Light commit> \
  switch-5
```

Set `WS` to the directory created by that command, then create a place for
command logs:

```bash
WS=~/holbench-runs/holbench-...
mkdir -p "$WS/logs"
```

The setup script checks required Ubuntu packages and reports an `apt-get`
command if any are missing. It expects `opam` to have already been initialized.

## Run individual benchmarks

Each benchmark directory has a README that explains how to run that benchmark
in the workspace and collect its JSON report:

| Benchmark | Instructions |
| --- | --- |
| HOL Light holtest | [`hol-light/README.md`](hol-light/README.md) |
| s2n-bignum (ARM and x86) | [`s2n-bignum/README.md`](s2n-bignum/README.md) |
| Flyspeck | [`Flyspeck/README.md`](Flyspeck/README.md) |
| Four Colour Theorem | [`4CT/README.md`](4CT/README.md) |
| Navier-Stokes | [`navier-stokes/README.md`](navier-stokes/README.md) |
| Catalan's constant is irrational | [`catalan-is-irrational/README.md`](catalan-is-irrational/README.md) |
| Poincare conjecture | [`poincare/README.md`](poincare/README.md) |

## Result format

Collectors print JSON to standard output and also write their default report
file at the workspace root. Use `-o <path>` to choose another destination or
`--no-write` for standard output only.

Every report includes:

- pass/fail/skip/missing counts,
- per-test timing and log paths,
- the applicable HOL Light and project commit hashes, and
- shared machine metadata: architecture, CPU model, online cores, and memory.

The run manifest also records the OCaml compiler version used by the workspace.

The collectors exit nonzero for failed or missing work. Keep raw logs until the
JSON has been collected and checked.

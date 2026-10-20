# HOL benchmark scripts

Scripts for creating a fresh HOL Light workspace and running benchmark families.

Published reports and the browser dashboard live in the companion
[benchmark-results repository](https://github.com/hol-light-family/benchmark-results/).

In command descriptions, `<argument>` is required and `[argument]` is
optional. Replace the argument name with a value; do not type the brackets.

## 1. Create a workspace

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

## 2. Run HOL Light holtest

Prepare the external tools, run `holtest.mk`, and collect its JSON report:

```bash
./hol-light/ubuntu/install-dependencies.sh "$WS/hol-light"
./hol-light/ubuntu/run.sh "$WS/hol-light" "$WS/holtest-logs" \
  > "$WS/logs/holtest-run.log" 2>&1
./hol-light/collect-results.py "$WS/hol-light" "$WS/holtest-logs"
```

This writes:

```text
$WS/hol-light-results.json
```

See [`hol-light/README.md`](hol-light/README.md) for dependency, skip, timing,
and parallelism details.

## 3. Run s2n-bignum

Clone s2n-bignum next to HOL Light, check the native/cross toolchains, run the
architectures sequentially, and collect both reports:

```bash
./s2n-bignum/ubuntu/clone-repo.sh "$WS"
./s2n-bignum/ubuntu/install-dependencies.sh

./s2n-bignum/ubuntu/run.sh \
  "$WS/s2n-bignum" arm "$WS/hol-light" \
  > "$WS/logs/s2n-arm-run.log" 2>&1
./s2n-bignum/collect-results.py "$WS/s2n-bignum" arm

./s2n-bignum/ubuntu/run.sh \
  "$WS/s2n-bignum" x86 "$WS/hol-light" \
  > "$WS/logs/s2n-x86-run.log" 2>&1
./s2n-bignum/collect-results.py "$WS/s2n-bignum" x86
```

`clone-repo.sh` defaults to
`https://github.com/awslabs/s2n-bignum.git` at `HEAD`. Pass the optional URL
and commit-ish to pin it. The resulting files are:

```text
$WS/s2n-bignum-arm-results.json
$WS/s2n-bignum-x86-results.json
```

See [`s2n-bignum/README.md`](s2n-bignum/README.md), especially its HOL Light
version and memory guidance.

## 4. Run Flyspeck

Clone Flyspeck and load the complete sequence documented by its
`load_flyspeck.ml`:

```bash
./Flyspeck/ubuntu/clone-repo.sh "$WS"
./Flyspeck/ubuntu/run.sh \
  "$WS/Flyspeck" "$WS/hol-light" "$WS/logs/flyspeck-run.log"
./Flyspeck/collect-results.py \
  "$WS/Flyspeck" "$WS/logs/flyspeck-run.log"
```

The clone defaults to
`https://github.com/hol-light-family/Flyspeck.git` at `HEAD`. The runner ends
at `map flyspeck_needs Build.build_sequence_full;;`; it does not recompute the
Azure nonlinear-inequality work. Flyspeck's linear-program verification can
take many hours.

This writes:

```text
$WS/flyspeck-results.json
```

See [`Flyspeck/README.md`](Flyspeck/README.md) for scope and success criteria.

## 5. Run the Four Colour Theorem

The 4CT source is already inside the HOL Light checkout. Run its OCaml 5
parallel bytecode target and collect the result:

```bash
./4CT/ubuntu/run.sh "$WS/hol-light" "$WS/logs/4ct-run.log"
./4CT/collect-results.py "$WS/hol-light" "$WS/logs/4ct-run.log"
```

The runner defaults to the smaller of the online CPU count and 128 OCaml
domains. Override it with `FOURCOLOR_DOMAINS`:

```bash
FOURCOLOR_DOMAINS=64 \
  ./4CT/ubuntu/run.sh "$WS/hol-light" "$WS/logs/4ct-run.log"
```

This writes:

```text
$WS/4ct-results.json
```

See [`4CT/README.md`](4CT/README.md) for the final theorems and parallel route.

## Result format

Collectors print JSON to standard output and also write their default report
file at the workspace root. Use `-o <path>` to choose another destination or
`--no-write` for standard output only.

Every report includes:

- pass/fail/skip/missing counts,
- per-test timing and log paths,
- the applicable HOL Light and project commit hashes, and
- shared machine metadata: architecture, CPU model, online cores, and memory.

The collectors exit nonzero for failed or missing work. Keep raw logs until the
JSON has been collected and checked.

# s2n-bignum benchmark scripts

Scripts for building and checking the [s2n-bignum](https://github.com/awslabs/s2n-bignum)
HOL Light proofs on Ubuntu, and collecting their running times and the list of
proven specifications.

Target platform: **Ubuntu on arm64 (aarch64)** (also works on x86_64; see
"Cross toolchains" below).

These scripts reuse an already-built HOL Light checkout (the same one the
`hol-light/` benchmark uses) via `HOLDIR`; they do not build HOL Light.

## Scripts

In command descriptions, `<argument>` is required and `[argument]` is
optional. Replace the argument name with a value; do not type the brackets.

| Script | Purpose |
| --- | --- |
| `ubuntu/clone-repo.sh <workspace dir> [repo URL] [commit-ish]` | Full `git clone` of s2n-bignum into `<workspace dir>/s2n-bignum`, i.e. right next to the hol-light checkout in the same workspace. Defaults to `https://github.com/awslabs/s2n-bignum.git` at the latest default-branch commit (`HEAD`), then checks out the resolved commit detached. Writes it to `s2n-bignum/S2N_BIGNUM_COMMIT`. |
| `ubuntu/install-dependencies.sh` | Checks (does not install) the apt packages and the **foreign-architecture** cross toolchain needed to build and check both `arm/` and `x86/` proofs on this host. Prints an `apt-get install` line if anything is missing. |
| `ubuntu/run.sh <s2n-bignum dir> <arm\|x86> <hol-light dir>` | Builds the proof binaries, runs the proofs for one architecture, then prints running times, proven specifications, and a failure scan. Tutorials are not built or run. |
| `collect-results.py <s2n-bignum dir> <arm\|x86> [-o out.json] [--no-write]` | Parses the architecture's `*.correct` proof logs and emits JSON with per-proof pass/fail/missing status plus timing. Prints to stdout, and by default also writes `<workspace dir>/s2n-bignum-<arch>-results.json` (the workspace being `<s2n-bignum dir>`'s parent). Platform-independent (pure Python + `make`), so it lives at the top level rather than under `ubuntu/`. |

Shared helper (one level up, used by both benchmark flows):

| Script | Purpose |
| --- | --- |
| `../common/check-failures.sh <s2n-bignum\|holtest> <file-or-dir>...` | Scans benchmark logs for failure markers. Exits non-zero if any file contains one. |

## Typical flow

Assuming hol-light already lives in a workspace, e.g.
`~/holbench-workspace/holbench-.../hol-light`, built and ready:

```bash
WS=~/holbench-workspace/holbench-2026-10-18-15.29.1792337369
HOL=$WS/hol-light

# 1. Clone s2n-bignum next to hol-light. The repository URL and HEAD are defaults.
s2n-bignum/ubuntu/clone-repo.sh "$WS"

# 2. Check apt deps + cross toolchain (install whatever it lists, then re-run)
s2n-bignum/ubuntu/install-dependencies.sh

# 3. Build + check the proofs for one architecture
s2n-bignum/ubuntu/run.sh "$WS/s2n-bignum" arm "$HOL"
# ...and/or the other architecture:
s2n-bignum/ubuntu/run.sh "$WS/s2n-bignum" x86 "$HOL"

# 4. Collect results as JSON (also written to
#    "$WS/s2n-bignum-arm-results.json" by default)
s2n-bignum/collect-results.py "$WS/s2n-bignum" arm
```

`run.sh` ends by printing:
- running times (via `tools/collect-times.sh`),
- the proven `*_SUBROUTINE_CORRECT` / `*_SUBROUTINE_SAFE` specs (via
  `tools/collect-specs.sh`), and
- a pass/fail summary from `../common/check-failures.sh`.

## Result JSON (`collect-results.py`)

For each proof log in the architecture Makefile's `PROOF_LOGS` list (derived
from its `$(OBJ)` list, i.e. every `.correct` file `make proofs` is expected
to produce), status is derived from the `<arch>/<proof>.correct` log:

- **missing** — the `.correct` file does not exist (the proof never ran).
- **fail** — the log contains `error:`, `exception:`, or `error in included
  file` (case-insensitive) -- the same rule `../common/check-failures.sh`
  uses.
- **pass** — none of the above.

s2n-bignum has no equivalent of holtest.mk's "skip" (no test is conditionally
skipped for a missing external tool), so `skip` is always `0`; the key is
kept so the JSON shape matches `hol-light/collect-results.py`.

Each record also carries:
- timing parsed from the proof binary's own `Running time: <secs> sec, ...`
  line (the same line `tools/collect-times.sh` greps for): `elapsed_seconds`,
  `start_unixtime`, `end_unixtime` (all `null` if the line is absent, e.g.
  missing proofs).
- `specs`: the `*_SUBROUTINE_CORRECT` / `*_SUBROUTINE_SAFE` theorem names
  that log proved (the same theorems `tools/collect-specs.sh` collects
  suite-wide, attributed back to the proof file that produced them).

The top-level output includes `counts`, `total_elapsed_seconds`, and a
`machine` object containing the CPU architecture and brand, online core count,
and total memory in bytes and GiB. Both benchmark collectors populate this
object through the shared `../common/machine_info.py` helper.

Example (abridged):

```json
{
  "arch": "arm",
  "total": 338,
  "counts": { "pass": 338, "fail": 0, "skip": 0, "missing": 0 },
  "total_elapsed_seconds": 50571.0,
  "tests": [
    { "name": "p256/bignum_add_p256", "status": "pass",
      "elapsed_seconds": 31.0, "start_unixtime": 1792446647.0,
      "end_unixtime": 1792446678.0,
      "specs": ["BIGNUM_ADD_P256_SUBROUTINE_CORRECT"],
      "log_path": ".../arm/p256/bignum_add_p256.correct" }
  ]
}
```

The script exits non-zero if there are any `fail` or `missing` proofs.

By default the JSON is also written to a file in the workspace directory
(the parent of `<s2n-bignum dir>`), e.g.
`~/holbench-runs/holbench-.../s2n-bignum-arm-results.json`, so results land
next to the checkout they report on without extra plumbing. Pass `-o <path>`
to write somewhere else, or `--no-write` to only print to stdout.

## HOL Light version

s2n-bignum pins a specific HOL Light commit in its CI (`HOLLIGHT_COMMIT`).
The `hol-light` checkout you point `HOLDIR` at should be built from that same
commit. Check `s2n-bignum/.github/workflows/ci.yml` for the pinned value, and
compare against the `HOL_LIGHT_COMMIT` file written by the hol-light
`create-workspace.sh`.

## Cross toolchains

s2n-bignum assembles each architecture's `.S` sources into object files that
the proofs are checked against. The native architecture uses the stock
`as`/`objdump`; the **other** architecture uses a cross-assembler:

- `arm/Makefile` uses `aarch64-linux-gnu-as` when not on aarch64.
- `x86/Makefile` uses `x86_64-linux-gnu-as` when not on x86_64.

So to check **both** architectures on one machine you need the foreign-arch
cross toolchain:

| Host | Foreign toolchain needed (apt) |
| --- | --- |
| aarch64 | `binutils-x86-64-linux-gnu`, `gcc-x86-64-linux-gnu` |
| x86_64 | `binutils-aarch64-linux-gnu`, `gcc-aarch64-linux-gnu` |

`install-dependencies.sh` detects the host arch and asks for the right one.

Building/checking the proofs does **not execute** the foreign code, so no
emulator (qemu) is needed here. qemu is only required for the
`sematest`/cosimulation targets, which these scripts do not run.

## Parallelism and memory

The proofs and the build phase are both memory-intensive (the build phase
runs `ocamlopt`, which itself uses substantial memory per concurrent job).
`run.sh` runs both with `make -j N`, where `N` is the smaller of:

- the number of online CPUs, and
- `(total RAM in GB) / 6` — reserving at least ~6 GB per concurrent job.

Overrides:

- `NUMCORES` — job count for the proof (run) phase.
- `BUILD_NUMCORES` — job count for the build phase.

## Notes / scope

- Tutorials are intentionally excluded. `run.sh` calls `build_proofs` and
  `proofs` only, not `build_tutorial`/`tutorial`.
- A full `make proofs` for one architecture checks hundreds of proofs and can
  take hours; run `arm` and `x86` separately.
- Failure detection: a proof's `*.correct` log is considered failed if it
  contains `error:`, `exception:`, or `error in included file`
  (case-insensitive), excluding a couple of known-benign lines. This is done
  by `../common/check-failures.sh`, a single benchmark-agnostic scanner shared
  with the hol-light `holtest` flow (same pattern for both). It is pointed at
  the `*.correct` output logs only — not the source tree, whose `.ml` files
  legitimately contain those words in string literals. See that script's
  header for the exact pattern and exclusions.

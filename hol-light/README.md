# HOL Light benchmark scripts

Scripts for running the HOL Light regression/benchmark suite (`holtest.mk`)
on Ubuntu, collecting pass/fail/skip status and timing.

Target platform for this setup: **Ubuntu on arm64 (aarch64)**.

## Scripts

In command descriptions, `<argument>` is required and `[argument]` is
optional. Replace the argument name with a value; do not type the brackets.

`init/ubuntu/create-workspace.sh` defaults to
`https://github.com/jrh13/hol-light` at its latest default-branch commit
(`HEAD`) and uses the `switch-5` target. Pass the optional arguments to pin a
repository, commit, or switch target.

| Script | Purpose |
| --- | --- |
| `ubuntu/install-dependencies.sh <hol-light dir>` | Checks apt build/test dependencies and builds the external SAT/theorem-prover tools from source into `<hol-light dir>/external-bin`. Nothing is installed system-wide and no sudo is used for the source builds. |
| `ubuntu/run.sh <hol-light dir> [log dir]` | Runs `holtest.mk` against an initialized checkout, prepending `<hol-light dir>/external-bin` to `PATH`. Picks a `make -j` job count (see "Parallelism" below). Default log dir is `/tmp/hol-light-test` (holtest.mk's hardcoded default). |
| `collect-results.py <hol-light dir> [log dir] [-o out.json] [--no-write]` | Parses the log dir and emits JSON with per-test pass/fail/skip/missing status plus timing. Prints to stdout, and by default also writes `<workspace dir>/hol-light-results.json` (the workspace being `<hol-light dir>`'s parent). Platform-independent (pure Python + `make`), so it lives at the top level rather than under `ubuntu/`. |

Typical flow:

```bash
# 1. Provision a workspace + checkout. The upstream repository, HEAD, and
#    `switch-5` target are defaults; pass optional values to pin a run.
init/ubuntu/create-workspace.sh <parent dir> [repo URL] [commit-ish] [switch|switch-5]

# 2. Build external tools into that checkout
hol-light/ubuntu/install-dependencies.sh <parent dir>/holbench-.../hol-light

# 3. Run the suite
hol-light/ubuntu/run.sh <parent dir>/holbench-.../hol-light

# 4. Collect results as JSON (also written to
#    <parent dir>/holbench-.../hol-light-results.json by default)
hol-light/collect-results.py <parent dir>/holbench-.../hol-light
```

## Parallelism

`run.sh` runs `make -j N`. By default `N` is the smaller of:

- the number of online CPUs (`getconf _NPROCESSORS_ONLN`), and
- `(total RAM in GB) / 2` — e.g. a 96 GB machine is capped at 48 jobs.

The memory cap guards against OOM, since each HOL Light test process can be
memory-heavy. Set the `NUMCORES` environment variable to override both and
use an exact job count.

## External tool dependencies

`holtest.mk` drives several tests through external tools. Some come from apt;
the rest are built from source by `install-dependencies.sh`.

### From apt (checked, not auto-installed)

`install-dependencies.sh` verifies these are present and prints an
`apt-get install` line if any are missing, rather than installing them:

| Package | Needed by |
| --- | --- |
| `build-essential`, `cmake`, `git`, `curl` | building the source tools below |
| `coinor-csdp` (provides `csdp`) | `Examples/sos` |
| `maxima` | `WZ`/`make` (Wilf–Zeilberger) |
| `pari-gp` (provides `gp`) | `Library/prime-pratt`, `Library/prime-pocklington` |
| `libocamlgraph-ocaml-dev` | `QBF/make` |

### Built from source into `<hol-light dir>/external-bin`

We build these from source rather than shipping prebuilt binaries, so the
binaries match the runtime's own libraries and arch and we avoid shared
library mismatches. (For that reason there are no vendored binaries in this
repo.)

| Tool | Version built | License | Needed by | Build notes |
| --- | --- | --- | --- | --- |
| cadical | 3.0.1 (github.com/arminbiere/cadical) | MIT | `Cadical/make-test` (guarded by `which cadical`) | `./configure && make` |
| lrat-trim | github.com/arminbiere/lrat-trim | MIT | LRAT checking used by the Cadical flow | `./configure && make` |
| prover9 | LADR-2009-11A (cs.unm.edu) | GPLv2 | `Examples/prover9` (no `which` guard — a missing prover9 makes this test **fail**, not skip) | See below |

**prover9 / LADR build note (arm64 + modern GCC).** The 2009 LADR sources
predate C99's stricter rules; GCC 14+ turns implicit-int, implicit function
declarations, and K&R-style definitions into hard errors. LADR's Makefiles
expose an `XFLAGS` hook prepended to `CFLAGS`, so the build passes
`XFLAGS="-Wno-implicit-int -Wno-implicit-function-declaration -fcommon"` to
downgrade those back to warnings. The build is also run **serially** (no
`-j`): LADR's top-level Makefile runs each subdir's `all` target, which
includes an `install` step that `mv`s the binary into `./bin`, and that is
not parallel-safe.

## Not installed: zChaff / MiniSat-p (the `Minisat/make-test` test)

The `Minisat/make-test` target is **not** supported by this setup and will be
recorded as a **skip**.

`holtest.mk` guards that target on `which zchaff`; if `zchaff` is not on
`PATH` it writes a `### Error: skip ...` marker and moves on. The underlying
test (see `Minisat/README` and `Minisat/zc2mso/README` in the HOL Light
checkout) relies on:

- **MiniSat-p** — the proof-logging MiniSat `v1.14 (2006-Sep-07)`
  (MIT-licensed, but a legacy source drop that needs patching to build on
  modern C++ compilers), and
- **zChaff** — Princeton's `zchaff.64bit.2007.3.12`, used via the `zc2mso`
  proof-format translator.

**Why zChaff is excluded:** zChaff is distributed under Princeton's
research-only license, which does not permit redistribution or commercial
use. We therefore do not vendor it, download it, or build it here, and we
leave `Minisat/make-test` as a documented skip. If you have independently
obtained zChaff (and MiniSat-p) under terms you are comfortable with, placing
a `zchaff` binary on `PATH` (e.g. in `external-bin`) will let that test run.

## Result JSON (`collect-results.py`)

For each test name in `holtest.mk`'s `TESTS` list, status is derived from its
log:

- **missing** — neither `<log dir>/<t>` nor `<log dir>/<t>.ready` exists (the
  test never ran).
- **skip** — the log contains a line starting with `### Error: skip`
  (holtest.mk's own marker for a deliberately skipped test, e.g. when
  `cadical`/`zchaff` is absent).
- **fail** — `<t>.ready` is missing, or the log contains
  `Error in included file` (HOL Light's `loadt`/`needs` error convention).
- **pass** — none of the above.

Each record also carries timing parsed from the `time` summary line that
`holtest.mk` emits via `(time $(HOLLIGHT))`
(`<u>user <s>system <e>elapsed ...`): `elapsed_seconds`, `user_seconds`,
`system_seconds` (all `null` for skipped/missing tests with no timing line).
The top-level output includes `counts`, `total_elapsed_seconds`, and a
`machine` object containing the CPU architecture and brand, online core count,
and total memory in bytes and GiB. Both benchmark collectors populate this
object through the shared `../common/machine_info.py` helper.

Example (abridged):

```json
{
  "total": 191,
  "counts": { "pass": 180, "fail": 9, "skip": 2, "missing": 0 },
  "total_elapsed_seconds": 67949.07,
  "tests": [
    { "name": "Library/agm", "status": "pass",
      "elapsed_seconds": 29.4, "user_seconds": 0.01, "system_seconds": 0.0,
      "log_path": "/tmp/hol-light-test/Library/agm" }
  ]
}
```

The script exits non-zero if there are any `fail` or `missing` tests.

By default the JSON is also written to a file in the workspace directory
(the parent of `<hol-light dir>`), e.g.
`~/holbench-runs/holbench-.../hol-light-results.json`, so results land next
to the checkout they report on without extra plumbing. Pass `-o <path>` to
write somewhere else, or `--no-write` to only print to stdout.

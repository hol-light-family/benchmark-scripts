#!/usr/bin/env python3
"""collect-results.py <hol-light dir> [log dir] [-o output.json]

Parses the output of a holtest.mk run (see run.sh) and reports, as JSON, the
pass/fail/skip status of every test defined in holtest.mk.

The JSON is printed to stdout, and -- by default -- also written to a file
in the workspace directory (the parent of <hol-light dir>, e.g.
~/holbench-runs/holbench-.../hol-light-results.json), so a run's results
land next to the checkout it tested without extra plumbing. Use -o/--output
to write somewhere else instead, or --no-write to skip writing a file and
only print to stdout.

Status is derived like this for each test name <t> in holtest.mk's TESTS
list:
  - missing : neither <log dir>/<t> nor <log dir>/<t>.ready exists, i.e. the
              test never ran (interrupted run, or `make` stopped early).
  - skip    : the log contains a line starting with "### Error: skip" --
              holtest.mk's own convention for a test it deliberately skipped
              because an external tool (e.g. zchaff, cadical) isn't on PATH.
  - fail    : <log dir>/<t>.ready is missing (the make rule didn't finish),
              or the log contains a line starting with "Error in included
              file" -- HOL Light's own loadt/needs error-reporting
              convention, printed for both runtime exceptions and
              compile-time errors while loading a file.
  - pass    : none of the above.

Each test's record also includes the path to its log file so a report
viewer can link to the raw output, and the elapsed wall-clock time of the
run (parsed from the `time` summary that holtest.mk emits as
`(time $(HOLLIGHT))`). Two formats are supported: the bash builtin `time`
(what run.sh produces via SHELL=bash), e.g.

    real	23m38.873s
    user	0m0.012s
    sys	0m0.006s

and GNU /usr/bin/time, e.g.

    0.01user 0.00system 0:34.20elapsed 0%CPU (0avgtext+0avgdata ...)

reported as:
  - elapsed_seconds : wall-clock seconds (float) for the test, or null if no
                      timing line was found (e.g. missing/skipped test).
  - user_seconds    : CPU time in user mode, or null.
  - system_seconds  : CPU time in system mode, or null.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

SKIP_MARKER = re.compile(r"^### Error: skip", re.MULTILINE)
FAIL_MARKER = re.compile(r"^Error in included file", re.MULTILINE)

# Two `time` output formats can appear in a holtest log, depending on which
# `time` ran the HOL Light invocation:
#
# 1. The bash builtin `time` (used when holtest.mk is run with SHELL=bash,
#    as run.sh does). Three separate lines, each "<label>\t<[Hh][Mm]S.SSSs>":
#       real	23m38.873s
#       user	0m0.012s
#       sys	0m0.006s
#
# 2. GNU /usr/bin/time, one line:
#       0.01user 0.00system 0:34.20elapsed 0%CPU (0avgtext+0avgdata ...)
#
# We support both; (1) is what the current run.sh produces.

# GNU /usr/bin/time, single line.
GNU_TIME_LINE = re.compile(
    r"(?P<user>\d+(?:\.\d+)?)user\s+"
    r"(?P<system>\d+(?:\.\d+)?)system\s+"
    r"(?P<elapsed>(?:\d+:)?\d+:\d+(?:\.\d+)?)elapsed",
    re.MULTILINE,
)

# bash builtin `time`, per-label line: "real\t1m2.500s", "user\t0m0.010s", ...
# Hours are possible in principle ("1h2m3.000s"); accept an optional Hh field.
BASH_TIME_LINE = re.compile(
    r"^(?P<label>real|user|sys)\s+"
    r"(?:(?P<h>\d+)h)?(?:(?P<m>\d+)m)?(?P<s>\d+(?:\.\d+)?)s\s*$",
    re.MULTILINE,
)


def _elapsed_to_seconds(elapsed: str) -> float:
    """Convert a GNU time elapsed field (M:SS.ss or H:MM:SS.ss) to seconds."""
    parts = elapsed.split(":")
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + float(part)
    return seconds


def _bash_dur_to_seconds(h, m, s) -> float:
    return (int(h) if h else 0) * 3600 + (int(m) if m else 0) * 60 + float(s)


def parse_timing(log_text: str) -> dict:
    """Return the timing of the last `time` summary in a log, or nulls.

    holtest.mk may run several HOL Light invocations for one test (e.g.
    analysis-transc loads six files via one `time`, but Minisat-style tests
    wrap a single invocation); we take the last timing block so the reported
    elapsed time reflects the whole test's final/aggregate measurement.

    'elapsed' is wall-clock: GNU time's elapsed field, or bash time's 'real'.
    """
    null = {"elapsed_seconds": None, "user_seconds": None, "system_seconds": None}

    # Prefer the bash builtin format (what run.sh with SHELL=bash produces):
    # collect the last real/user/sys triple seen.
    last = {}
    for m in BASH_TIME_LINE.finditer(log_text):
        last[m.group("label")] = _bash_dur_to_seconds(
            m.group("h"), m.group("m"), m.group("s")
        )
    if "real" in last:
        return {
            "elapsed_seconds": last.get("real"),
            "user_seconds": last.get("user"),
            "system_seconds": last.get("sys"),
        }

    # Fall back to GNU /usr/bin/time's single-line format.
    gnu = None
    for m in GNU_TIME_LINE.finditer(log_text):
        gnu = m
    if gnu is None:
        return null
    return {
        "elapsed_seconds": _elapsed_to_seconds(gnu.group("elapsed")),
        "user_seconds": float(gnu.group("user")),
        "system_seconds": float(gnu.group("system")),
    }


def get_test_names(hol_light_dir: Path) -> list[str]:
    """Ask holtest.mk itself for its TESTS list, so this stays in sync with
    whatever version of holtest.mk is checked out.

    We add a throwaway phony goal via --eval that just echoes $(TESTS), and
    ask make to build only that goal. This expands the TESTS variable without
    evaluating holtest.mk's real target graph. (Using `make -p` instead is
    pathologically slow once a run has completed: it walks the whole
    dependency graph against the large tree of per-test log/.ready files and
    can take many minutes.)"""
    result = subprocess.run(
        [
            "make",
            "-f", "holtest.mk",
            "--eval=__print_tests__:\n\t@echo $(TESTS)",
            "__print_tests__",
        ],
        cwd=hol_light_dir,
        capture_output=True,
        text=True,
        check=True,
    )
    names = [tok for tok in result.stdout.split() if "/" in tok]
    if not names:
        raise RuntimeError("Could not obtain a TESTS list from holtest.mk")
    return names


def classify(log_dir: Path, test_name: str) -> dict:
    log_path = log_dir / test_name
    ready_path = log_dir / f"{test_name}.ready"

    record = {
        "name": test_name,
        "log_path": str(log_path),
    }

    if not log_path.exists() and not ready_path.exists():
        record["status"] = "missing"
        record.update(parse_timing(""))
        return record

    log_text = log_path.read_text(errors="replace") if log_path.exists() else ""

    record.update(parse_timing(log_text))

    if SKIP_MARKER.search(log_text):
        record["status"] = "skip"
        return record

    if not ready_path.exists() or FAIL_MARKER.search(log_text):
        record["status"] = "fail"
        return record

    record["status"] = "pass"
    return record


def default_output_path(hol_light_dir: Path) -> Path:
    """Default JSON output path: <workspace dir>/hol-light-results.json,
    where <workspace dir> is hol-light_dir's parent (e.g.
    ~/holbench-runs/holbench-.../hol-light-results.json next to the
    hol-light checkout it reports on)."""
    return hol_light_dir.parent / "hol-light-results.json"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect holtest.mk pass/fail/skip status and timing as JSON.",
    )
    parser.add_argument("hol_light_dir", help="path to the hol-light checkout")
    parser.add_argument(
        "log_dir",
        nargs="?",
        default="/tmp/hol-light-test",
        help="holtest.mk log directory (default: /tmp/hol-light-test)",
    )
    parser.add_argument(
        "-o", "--output",
        help="path to write the JSON report to "
             "(default: <workspace dir>/hol-light-results.json, i.e. next "
             "to the hol-light checkout)",
    )
    parser.add_argument(
        "--no-write",
        action="store_true",
        help="do not write a JSON file, only print to stdout",
    )
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args(sys.argv[1:])

    hol_light_dir = Path(args.hol_light_dir).resolve()
    log_dir = Path(args.log_dir).resolve()

    if not (hol_light_dir / "holtest.mk").is_file():
        print(f"{hol_light_dir} does not contain holtest.mk", file=sys.stderr)
        return 1

    test_names = get_test_names(hol_light_dir)
    results = [classify(log_dir, name) for name in test_names]

    counts = {"pass": 0, "fail": 0, "skip": 0, "missing": 0}
    for r in results:
        counts[r["status"]] += 1

    total_elapsed = sum(
        r["elapsed_seconds"] for r in results if r["elapsed_seconds"] is not None
    )

    output = {
        "hol_light_dir": str(hol_light_dir),
        "log_dir": str(log_dir),
        "total": len(results),
        "counts": counts,
        "total_elapsed_seconds": round(total_elapsed, 2),
        "tests": results,
    }

    text = json.dumps(output, indent=2) + "\n"
    sys.stdout.write(text)

    if not args.no_write:
        output_path = Path(args.output).resolve() if args.output else default_output_path(hol_light_dir)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text)
        print(f"Wrote {output_path}", file=sys.stderr)

    return 0 if counts["fail"] == 0 and counts["missing"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

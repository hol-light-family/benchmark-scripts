#!/usr/bin/env python3
"""collect-results.py <s2n-bignum dir> <arm|x86>
                      [--hol-light-dir DIR] [-o output.json]

Parses the output of an s2n-bignum `make proofs` run (see ubuntu/run.sh) and
reports, as JSON, the pass/fail/missing status of every proof defined in the
architecture's Makefile. The JSON shape mirrors hol-light/collect-results.py
(same top-level/per-test keys), so a single report viewer can consume either.

The JSON is printed to stdout, and -- by default -- also written to a file
in the workspace directory (the parent of <s2n-bignum dir>, e.g.
~/holbench-runs/holbench-.../s2n-bignum-arm-results.json), so a run's
results land next to the checkout it tested without extra plumbing. Use
-o/--output to write somewhere else instead, or --no-write to skip writing a
file and only print to stdout.

The canonical list of proofs is read from the Makefile itself (its
PROOF_LOGS variable, i.e. the architecture's $(OBJ) list with .o -> .correct),
the same way hol-light/collect-results.py asks holtest.mk for its TESTS
variable -- rather than hardcoding the list here, which would drift from
whatever version of s2n-bignum is checked out.

Status is derived like this for each proof log name <p> (e.g.
"p256/bignum_add_p256.correct"):
  - missing : <arch dir>/<p> does not exist, i.e. the proof never ran
              (interrupted run, or `make` stopped early).
  - fail    : the log contains a line matching the suspicious-marker pattern
              shared with common/check-failures.sh ("error:", "exception:",
              or "error in included file", case-insensitive).
  - pass    : none of the above.

s2n-bignum has no equivalent of holtest.mk's "skip" (it has no tests that are
conditionally skipped for a missing external tool), so "skip" never appears
here, but the key is kept in `counts` for shape-compatibility with the
hol-light report.

Each proof's record also includes the path to its log file, the elapsed
wall-clock time (parsed from the "Running time: <secs> sec, ..." line that
../tools/run-proof.sh's underlying .native binary prints -- the same line
../tools/collect-times.sh greps for), and the list of
*_SUBROUTINE_CORRECT / *_SUBROUTINE_SAFE theorem names proven by that log
(the same theorems ../tools/collect-specs.sh collects, but attributed back to
the proof file that produced them).
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

# Both benchmark collectors are standalone scripts in sibling directories.
# Add the repository's common/ directory so they share one machine schema.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))
from commit_info import resolve_commit  # noqa: E402
from machine_info import collect_machine_info  # noqa: E402

SUSPICIOUS_MARKER = re.compile(r"error:|exception:|error in included file", re.IGNORECASE)
BENIGN_MARKER = re.compile(r"^### Error: skip", re.IGNORECASE)

TIME_LINE = re.compile(
    r"^Running time:\s*(?P<elapsed>\d+(?:\.\d+)?)\s*sec,\s*"
    r"Start unixtime:\s*(?P<start>\d+(?:\.\d+)?)\s*,\s*"
    r"End unixtime:\s*(?P<end>\d+(?:\.\d+)?)\s*\.?\s*$",
    re.MULTILINE,
)

SPEC_LINE = re.compile(r"^val\s+([A-Z_0-9]*_SUBROUTINE_(?:CORRECT|SAFE))\s*:\s*thm\s*=", re.MULTILINE)


def is_failed(log_text: str) -> bool:
    """Same rule as common/check-failures.sh: a suspicious line that isn't
    also a benign ('### Error: skip ...') line counts as a failure."""
    for line in log_text.splitlines():
        if SUSPICIOUS_MARKER.search(line) and not BENIGN_MARKER.search(line):
            return True
    return False


def parse_timing(log_text: str) -> dict:
    """Return the timing of the last 'Running time: ...' line in a log, or
    nulls. A proof log normally has exactly one such line (written once the
    .native binary finishes); take the last if more than one ever appears."""
    null = {"elapsed_seconds": None, "start_unixtime": None, "end_unixtime": None}

    last = None
    for m in TIME_LINE.finditer(log_text):
        last = m
    if last is None:
        return null

    return {
        "elapsed_seconds": float(last.group("elapsed")),
        "start_unixtime": float(last.group("start")),
        "end_unixtime": float(last.group("end")),
    }


def parse_specs(log_text: str) -> list[str]:
    """Return the *_SUBROUTINE_CORRECT / *_SUBROUTINE_SAFE theorem names
    this log proved, in the order HOL Light printed them."""
    return SPEC_LINE.findall(log_text)


def get_proof_logs(arch_dir: Path) -> list[str]:
    """Ask the architecture Makefile itself for its PROOF_LOGS list, so this
    stays in sync with whatever version of s2n-bignum is checked out.

    Mirrors hol-light/collect-results.py's get_test_names: add a throwaway
    phony goal via --eval that just echoes $(PROOF_LOGS), and ask make to
    build only that goal, which expands the variable without evaluating the
    real target graph (HOLDIR is irrelevant to this variable, so it is left
    unset)."""
    result = subprocess.run(
        [
            "make",
            "--eval=__print_proof_logs__:\n\t@echo $(PROOF_LOGS)",
            "__print_proof_logs__",
        ],
        cwd=arch_dir,
        capture_output=True,
        text=True,
        check=True,
    )
    names = result.stdout.split()
    if not names:
        raise RuntimeError(f"Could not obtain a PROOF_LOGS list from {arch_dir}/Makefile")
    return names


def classify(arch_dir: Path, proof_log: str) -> dict:
    log_path = arch_dir / proof_log

    record = {
        "name": proof_log[: -len(".correct")] if proof_log.endswith(".correct") else proof_log,
        "log_path": str(log_path),
    }

    if not log_path.exists():
        record["status"] = "missing"
        record.update(parse_timing(""))
        record["specs"] = []
        return record

    log_text = log_path.read_text(errors="replace")

    record.update(parse_timing(log_text))
    record["specs"] = parse_specs(log_text)
    record["status"] = "fail" if is_failed(log_text) else "pass"
    return record


def default_output_path(s2n_dir: Path, arch: str) -> Path:
    """Default JSON output path: <workspace dir>/s2n-bignum-<arch>-results.json,
    where <workspace dir> is s2n_dir's parent (e.g.
    ~/holbench-runs/holbench-.../s2n-bignum-arm-results.json next to the
    s2n-bignum checkout it reports on)."""
    return s2n_dir.parent / f"s2n-bignum-{arch}-results.json"


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect s2n-bignum proof pass/fail/missing status and timing as JSON.",
    )
    parser.add_argument("s2n_bignum_dir", help="path to the s2n-bignum checkout")
    parser.add_argument("arch", choices=["arm", "x86"], help="architecture to report on")
    parser.add_argument(
        "--hol-light-dir",
        help="HOL Light checkout used for the proofs "
             "(default: sibling <workspace dir>/hol-light)",
    )
    parser.add_argument(
        "-o", "--output",
        help="path to write the JSON report to "
             "(default: <workspace dir>/s2n-bignum-<arch>-results.json, "
             "i.e. next to the s2n-bignum checkout)",
    )
    parser.add_argument(
        "--no-write",
        action="store_true",
        help="do not write a JSON file, only print to stdout",
    )
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args(sys.argv[1:])

    s2n_dir = Path(args.s2n_bignum_dir).resolve()
    arch = args.arch
    hol_light_dir = (
        Path(args.hol_light_dir).resolve()
        if args.hol_light_dir
        else s2n_dir.parent / "hol-light"
    )

    arch_dir = s2n_dir / arch
    if not (arch_dir / "Makefile").is_file():
        print(f"{arch_dir} does not contain a Makefile", file=sys.stderr)
        return 1
    if not hol_light_dir.is_dir():
        print(f"HOL Light directory does not exist: {hol_light_dir}", file=sys.stderr)
        return 1

    proof_logs = get_proof_logs(arch_dir)
    results = [classify(arch_dir, name) for name in proof_logs]

    counts = {"pass": 0, "fail": 0, "skip": 0, "missing": 0}
    for r in results:
        counts[r["status"]] += 1

    total_elapsed = sum(
        r["elapsed_seconds"] for r in results if r["elapsed_seconds"] is not None
    )

    try:
        s2n_bignum_commit = resolve_commit(s2n_dir, "S2N_BIGNUM_COMMIT")
        hol_light_commit = resolve_commit(hol_light_dir, "HOL_LIGHT_COMMIT")
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1

    output = {
        "s2n_bignum_dir": str(s2n_dir),
        "s2n_bignum_commit": s2n_bignum_commit,
        "hol_light_dir": str(hol_light_dir),
        "hol_light_commit": hol_light_commit,
        "arch": arch,
        "arch_dir": str(arch_dir),
        "machine": collect_machine_info(),
        "total": len(results),
        "counts": counts,
        "total_elapsed_seconds": round(total_elapsed, 2),
        "tests": results,
    }

    text = json.dumps(output, indent=2) + "\n"
    sys.stdout.write(text)

    if not args.no_write:
        output_path = Path(args.output).resolve() if args.output else default_output_path(s2n_dir, arch)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text)
        print(f"Wrote {output_path}", file=sys.stderr)

    return 0 if counts["fail"] == 0 and counts["missing"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

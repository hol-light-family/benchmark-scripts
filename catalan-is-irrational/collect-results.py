#!/usr/bin/env python3
"""Collect the catalan-is-irrational HOL Light development result as JSON."""

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))
from commit_info import resolve_commit  # noqa: E402
from machine_info import collect_machine_info  # noqa: E402

SUSPICIOUS_MARKER = re.compile(
    r"error:|exception:|error in included file", re.IGNORECASE
)
BENIGN_MARKER = re.compile(r"^### Error: skip", re.IGNORECASE)
TIME_LINE = re.compile(
    r"^Running time:\s*(?P<elapsed>\d+(?:\.\d+)?)\s*sec,\s*"
    r"Start unixtime:\s*(?P<start>\d+(?:\.\d+)?)\s*,\s*"
    r"End unixtime:\s*(?P<end>\d+(?:\.\d+)?)\s*$",
    re.MULTILINE,
)
# The OCaml toplevel prompt may precede output that starts a phrase.
PROMPT = r"^(?:# )*"
STAGE_LINE = re.compile(
    PROMPT + r"CATALAN_STAGE_(?P<edge>START|END) make\.ml (?P<time>\d+)\s*$",
    re.MULTILINE,
)
THEOREM_LINE = re.compile(
    PROMPT + r"CATALAN_THEOREM (?P<name>\w+) hypotheses (?P<hyps>\d+) "
    r"conclusion (?P<ok>true|false)\s*$",
    re.MULTILINE,
)
AXIOMS_LINE = re.compile(PROMPT + r"CATALAN_AXIOMS_COUNT (\d+)\s*$", re.MULTILINE)
STANDARD_AXIOM_COUNT = 3

# Theorems that run.sh checks after loading make.ml.
THEOREMS = [
    "CATALAN_CONSTANT_IRRATIONAL_HEADLINE",
    "CATALAN_CONSTANT_IRRATIONAL",
    "CATALAN_IRRATIONAL",
]
TEST_NAME = "catalan-is-irrational/make.ml"


def is_failed(text: str) -> bool:
    for line in text.splitlines():
        if SUSPICIOUS_MARKER.search(line) and not BENIGN_MARKER.search(line):
            return True
    return False


def parse_overall_timing(log_text: str) -> dict:
    match = None
    for candidate in TIME_LINE.finditer(log_text):
        match = candidate
    if match is None:
        return {"elapsed_seconds": None, "start_unixtime": None, "end_unixtime": None}
    return {
        "elapsed_seconds": float(match.group("elapsed")),
        "start_unixtime": float(match.group("start")),
        "end_unixtime": float(match.group("end")),
    }


def evaluate(log_text: str, log_file: Path) -> dict:
    result = {
        "name": TEST_NAME,
        "log_path": str(log_file),
        "status": "missing",
        "elapsed_seconds": None,
        "start_unixtime": None,
        "end_unixtime": None,
        "theorems": [],
        "axioms_count": None,
        "problems": [],
    }
    start = end = None
    for match in STAGE_LINE.finditer(log_text):
        if match.group("edge") == "START" and start is None:
            start = match
        elif match.group("edge") == "END" and start is not None and end is None:
            end = match
    if start is None:
        return result

    result["start_unixtime"] = float(start.group("time"))
    problems = result["problems"]
    if end is None:
        problems.append("session ended before make.ml finished")
    else:
        result["end_unixtime"] = float(end.group("time"))
        result["elapsed_seconds"] = result["end_unixtime"] - result["start_unixtime"]

    # Everything after START: the load itself and the checks that follow it.
    segment = log_text[start.end():]
    if is_failed(segment):
        problems.append("failure marker in log")

    reports = {m.group("name"): m for m in THEOREM_LINE.finditer(segment)}
    checked = []
    for name in THEOREMS:
        report = reports.get(name)
        if report is None:
            problems.append(f"{name} not reported")
        elif report.group("hyps") != "0":
            problems.append(f"{name} has {report.group('hyps')} hypotheses")
        elif report.group("ok") != "true":
            problems.append(f"{name} has an unexpected conclusion")
        else:
            checked.append(name)
    result["theorems"] = checked

    axioms = AXIOMS_LINE.search(segment)
    if axioms is None:
        problems.append("CATALAN_AXIOMS_COUNT not reported")
    else:
        result["axioms_count"] = int(axioms.group(1))
        if result["axioms_count"] != STANDARD_AXIOM_COUNT:
            problems.append(
                f"expected {STANDARD_AXIOM_COUNT} axioms, found {result['axioms_count']}"
            )

    result["status"] = "fail" if problems else "pass"
    return result


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect the catalan-is-irrational development result as JSON."
    )
    parser.add_argument("catalan_is_irrational_dir", help="path to the catalan-is-irrational checkout")
    parser.add_argument(
        "log_file",
        nargs="?",
        help="run log (default: <workspace dir>/catalan-is-irrational-run.log)",
    )
    parser.add_argument(
        "--hol-light-dir",
        help="HOL Light checkout used for the run "
             "(default: sibling <workspace dir>/hol-light)",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="JSON output path (default: <workspace dir>/catalan-is-irrational-results.json)",
    )
    parser.add_argument(
        "--no-write",
        action="store_true",
        help="do not write a JSON file, only print to stdout",
    )
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args(sys.argv[1:])
    catalan_is_irrational_dir = Path(args.catalan_is_irrational_dir).resolve()
    workspace_dir = catalan_is_irrational_dir.parent
    hol_light_dir = (
        Path(args.hol_light_dir).resolve()
        if args.hol_light_dir
        else workspace_dir / "hol-light"
    )
    log_file = (
        Path(args.log_file).resolve()
        if args.log_file
        else workspace_dir / "catalan-is-irrational-run.log"
    )

    if not (catalan_is_irrational_dir / "make.ml").is_file():
        print(f"{catalan_is_irrational_dir} does not contain make.ml", file=sys.stderr)
        return 1
    if not hol_light_dir.is_dir():
        print(f"HOL Light directory does not exist: {hol_light_dir}", file=sys.stderr)
        return 1

    try:
        catalan_is_irrational_commit = resolve_commit(catalan_is_irrational_dir, "CATALAN_IS_IRRATIONAL_COMMIT")
        hol_light_commit = resolve_commit(hol_light_dir, "HOL_LIGHT_COMMIT")
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1

    log_text = log_file.read_text(errors="replace") if log_file.is_file() else ""
    timing = parse_overall_timing(log_text)
    tests = [evaluate(log_text, log_file)]

    counts = {"pass": 0, "fail": 0, "skip": 0, "missing": 0}
    for test in tests:
        counts[test["status"]] += 1

    output = {
        "catalan_is_irrational_dir": str(catalan_is_irrational_dir),
        "catalan_is_irrational_commit": catalan_is_irrational_commit,
        "hol_light_dir": str(hol_light_dir),
        "hol_light_commit": hol_light_commit,
        "log_file": str(log_file),
        "machine": collect_machine_info(),
        "total": len(tests),
        "counts": counts,
        "total_elapsed_seconds": timing["elapsed_seconds"] or 0,
        "start_unixtime": timing["start_unixtime"],
        "end_unixtime": timing["end_unixtime"],
        "tests": tests,
    }

    text = json.dumps(output, indent=2) + "\n"
    sys.stdout.write(text)
    if not args.no_write:
        output_path = (
            Path(args.output).resolve()
            if args.output
            else workspace_dir / "catalan-is-irrational-results.json"
        )
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text)
        print(f"Wrote {output_path}", file=sys.stderr)

    return 0 if counts["fail"] == 0 and counts["missing"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

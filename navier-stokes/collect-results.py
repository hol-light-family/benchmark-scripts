#!/usr/bin/env python3
"""Collect the Navier_Stokes HOL Light development and audit results as JSON."""

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
    PROMPT + r"NAVIER_STOKES_STAGE_(?P<edge>START|END) (?P<name>\S+) (?P<time>\d+)\s*$",
    re.MULTILINE,
)
STANDARD_AXIOM_COUNT = 3

# Theorems that check.ml reports with "hypotheses N  conclusion is S: B".
HEADLINE_THEOREMS = [
    "NS_BREAKDOWN_PERIODIC",
    "NS_BREAKDOWN_R3",
    "NS_THEOREM_1_1_FULL",
    "NS_THEOREM_1_1",
    "NS_THEOREM_3_1_HEAT",
    "NS_THEOREM_3_1",
]
# Theorems that audit/check.ml reports with "hypotheses N  conclusion...: B".
AUDIT_THEOREMS = [
    "CLAY_BLIND_C_PROVED",
    "CLAY_BLIND_D_PROVED",
    "NS_CLAY_C_EQUIV_BLIND",
    "NS_CLAY_D_EQUIV_BLIND",
]

STAGES = [
    {
        "name": "check.ml",
        "done_marker": "NAVIER_STOKES_CHECK_DONE",
        "theorems": HEADLINE_THEOREMS,
        "hypothesis_only": ["NS_HEAT_SWIRL_PDE"],
        "sanity": False,
    },
    {
        "name": "audit/check.ml",
        "done_marker": "NAVIER_STOKES_AUDIT_CHECK_DONE",
        "theorems": AUDIT_THEOREMS,
        "hypothesis_only": [],
        "sanity": True,
    },
]


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


def stage_segment(log_text: str, name: str):
    """Return (segment text, start time, end time) for one stage.

    The segment runs from the stage's START marker to its END marker, or to the
    end of the log if the session died before printing END. Returns None if
    the stage never started.
    """
    start = end = None
    for match in STAGE_LINE.finditer(log_text):
        if match.group("name") != name:
            continue
        if match.group("edge") == "START" and start is None:
            start = match
        elif match.group("edge") == "END" and start is not None and end is None:
            end = match
    if start is None:
        return None
    segment = log_text[start.end():end.start() if end else len(log_text)]
    return (
        segment,
        float(start.group("time")),
        float(end.group("time")) if end else None,
    )


def theorem_report(segment: str, name: str):
    """Return (hypotheses, conclusion_ok) for a reported theorem, or None."""
    match = re.search(
        PROMPT + re.escape(name)
        + r"\s+hypotheses (\d+)(?:\s+conclusion[^:\n]*: (true|false))?\s*$",
        segment,
        re.MULTILINE,
    )
    if match is None:
        return None
    return int(match.group(1)), match.group(2) in (None, "true")


def evaluate_stage(log_text: str, stage: dict, log_file: Path) -> dict:
    result = {
        "name": f"Navier_Stokes/{stage['name']}",
        "log_path": str(log_file),
        "status": "missing",
        "elapsed_seconds": None,
        "start_unixtime": None,
        "end_unixtime": None,
        "theorems": [],
        "axioms_count": None,
        "problems": [],
    }
    found = stage_segment(log_text, stage["name"])
    if found is None:
        return result
    segment, start_time, end_time = found
    result["start_unixtime"] = start_time
    result["end_unixtime"] = end_time
    if end_time is not None:
        result["elapsed_seconds"] = end_time - start_time

    problems = result["problems"]
    if end_time is None:
        problems.append("session ended before the stage finished")
    if not re.search(PROMPT + re.escape(stage["done_marker"]) + r"\s*$",
                     segment, re.MULTILINE):
        problems.append(f"missing {stage['done_marker']}")
    if is_failed(segment):
        problems.append("failure marker in log")

    checked = []
    for name in stage["theorems"] + stage["hypothesis_only"]:
        report = theorem_report(segment, name)
        if report is None:
            problems.append(f"{name} not reported")
        elif report[0] != 0:
            problems.append(f"{name} has {report[0]} hypotheses")
        elif not report[1]:
            problems.append(f"{name} has an unexpected conclusion")
        else:
            checked.append(name)

    if stage["sanity"]:
        sanity = re.findall(
            PROMPT + r"(NS_SANITY_\w+)\s+hypotheses (\d+)\s*$", segment, re.MULTILINE
        )
        expected = re.search(PROMPT + r"SANITY_THEOREMS (\d+)\s*$", segment, re.MULTILINE)
        bad = [name for name, hyps in sanity if hyps != "0"]
        if bad:
            problems.append(f"sanity theorems with hypotheses: {', '.join(bad)}")
        if expected is None or int(expected.group(1)) != len(sanity) or not sanity:
            problems.append("sanity theorem count mismatch")
        checked.extend(name for name, hyps in sanity if hyps == "0")

    axioms = re.search(PROMPT + r"AXIOMS_COUNT (\d+)\s*$", segment, re.MULTILINE)
    if axioms is None:
        problems.append("AXIOMS_COUNT not reported")
    else:
        result["axioms_count"] = int(axioms.group(1))
        if result["axioms_count"] != STANDARD_AXIOM_COUNT:
            problems.append(
                f"expected {STANDARD_AXIOM_COUNT} axioms, found {result['axioms_count']}"
            )

    result["theorems"] = checked
    result["status"] = "fail" if problems else "pass"
    return result


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect the Navier_Stokes development and audit results as JSON."
    )
    parser.add_argument("navier_stokes_dir", help="path to the Navier_Stokes checkout")
    parser.add_argument(
        "log_file",
        nargs="?",
        help="run log (default: <workspace dir>/navier-stokes-run.log)",
    )
    parser.add_argument(
        "--hol-light-dir",
        help="HOL Light checkout used for the run "
             "(default: sibling <workspace dir>/hol-light)",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="JSON output path (default: <workspace dir>/navier-stokes-results.json)",
    )
    parser.add_argument(
        "--no-write",
        action="store_true",
        help="do not write a JSON file, only print to stdout",
    )
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args(sys.argv[1:])
    ns_dir = Path(args.navier_stokes_dir).resolve()
    workspace_dir = ns_dir.parent
    hol_light_dir = (
        Path(args.hol_light_dir).resolve()
        if args.hol_light_dir
        else workspace_dir / "hol-light"
    )
    log_file = (
        Path(args.log_file).resolve()
        if args.log_file
        else workspace_dir / "navier-stokes-run.log"
    )

    if not (ns_dir / "check.ml").is_file():
        print(f"{ns_dir} does not contain check.ml", file=sys.stderr)
        return 1
    if not hol_light_dir.is_dir():
        print(f"HOL Light directory does not exist: {hol_light_dir}", file=sys.stderr)
        return 1

    try:
        ns_commit = resolve_commit(ns_dir, "NAVIER_STOKES_COMMIT")
        hol_light_commit = resolve_commit(hol_light_dir, "HOL_LIGHT_COMMIT")
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1

    log_text = log_file.read_text(errors="replace") if log_file.is_file() else ""
    timing = parse_overall_timing(log_text)
    tests = [evaluate_stage(log_text, stage, log_file) for stage in STAGES]

    counts = {"pass": 0, "fail": 0, "skip": 0, "missing": 0}
    for test in tests:
        counts[test["status"]] += 1

    output = {
        "navier_stokes_dir": str(ns_dir),
        "navier_stokes_commit": ns_commit,
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
            else workspace_dir / "navier-stokes-results.json"
        )
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text)
        print(f"Wrote {output_path}", file=sys.stderr)

    return 0 if counts["fail"] == 0 and counts["missing"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

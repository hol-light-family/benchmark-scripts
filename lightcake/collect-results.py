#!/usr/bin/env python3
"""Collect the LightCake (CakeML in HOL Light) result as JSON."""

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "common"))
from commit_info import resolve_commit  # noqa: E402
from machine_info import collect_machine_info  # noqa: E402

# Same markers as common/check-failures.sh, but only at the start of a line
# (after optional "# " toplevel prompts). HOL Light echoes the definitions it
# proves, and the CakeML compiler's definitions contain string literals such as
# "### ERROR: parse error" on indented lines; those are not failures.
SUSPICIOUS_MARKER = re.compile(
    r"^(# )*(error:|exception:|error in included file)", re.IGNORECASE
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
    PROMPT + r"LIGHTCAKE_STAGE_(?P<edge>START|END) check\.ml (?P<time>\d+)\s*$",
    re.MULTILINE,
)
# Lines printed by LightCake's check.ml after it loads make.ml.
NOT_LOADED_LINE = re.compile(PROMPT + r"NOT LOADED (\S+)\s*$", re.MULTILINE)
AXIOMS_LINE = re.compile(PROMPT + r"AXIOMS_COUNT (\d+)\s*$", re.MULTILINE)
HEADLINE_LINE = re.compile(
    PROMPT + r"(?P<name>HEADLINE|HEADLINE_AG32) (?P<ok>true|false)\s*$",
    re.MULTILINE,
)
VERDICT_LINE = re.compile(PROMPT + r"(CHECK_OK|CHECK_FAILED)\s*$", re.MULTILINE)
STANDARD_AXIOM_COUNT = 3

# HEADLINE covers compilerProof_compile_correct and
# compile_correct_safe_for_space; HEADLINE_AG32 covers ag32_compile_correct.
HEADLINES = {
    "HEADLINE": ["compilerProof_compile_correct", "compile_correct_safe_for_space"],
    "HEADLINE_AG32": ["ag32_compile_correct"],
}
TEST_NAME = "LightCake/check.ml"


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
        "not_loaded": [],
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
        problems.append("session ended before check.ml finished")
    else:
        result["end_unixtime"] = float(end.group("time"))
        result["elapsed_seconds"] = result["end_unixtime"] - result["start_unixtime"]

    segment = log_text[start.end():end.start() if end else len(log_text)]
    if is_failed(segment):
        problems.append("failure marker in log")

    not_loaded = NOT_LOADED_LINE.findall(segment)
    result["not_loaded"] = not_loaded
    if not_loaded:
        problems.append(f"{len(not_loaded)} file(s) of make.ml not loaded")

    axioms = AXIOMS_LINE.search(segment)
    if axioms is None:
        problems.append("AXIOMS_COUNT not reported")
    else:
        result["axioms_count"] = int(axioms.group(1))
        if result["axioms_count"] != STANDARD_AXIOM_COUNT:
            problems.append(
                f"expected {STANDARD_AXIOM_COUNT} axioms, found {result['axioms_count']}"
            )

    reports = {m.group("name"): m.group("ok") for m in HEADLINE_LINE.finditer(segment)}
    checked = []
    for marker, theorems in HEADLINES.items():
        verdict = reports.get(marker)
        if verdict is None:
            problems.append(f"{marker} not reported")
        elif verdict != "true":
            problems.append(
                f"{marker} false: {', '.join(theorems)} has hypotheses "
                "or an unexpected conclusion"
            )
        else:
            checked.extend(theorems)
    result["theorems"] = checked

    verdict = VERDICT_LINE.search(segment)
    if verdict is None:
        problems.append("CHECK_OK not reported")
    elif verdict.group(1) != "CHECK_OK":
        problems.append("check.ml reported CHECK_FAILED")

    result["status"] = "fail" if problems else "pass"
    return result


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect the LightCake result as JSON."
    )
    parser.add_argument("lightcake_dir", help="path to the LightCake checkout")
    parser.add_argument(
        "log_file",
        nargs="?",
        help="run log (default: <workspace dir>/lightcake-run.log)",
    )
    parser.add_argument(
        "--hol-light-dir",
        help="HOL Light checkout used for the run "
             "(default: sibling <workspace dir>/hol-light)",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="JSON output path (default: <workspace dir>/lightcake-results.json)",
    )
    parser.add_argument(
        "--no-write",
        action="store_true",
        help="do not write a JSON file, only print to stdout",
    )
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args(sys.argv[1:])
    lightcake_dir = Path(args.lightcake_dir).resolve()
    workspace_dir = lightcake_dir.parent
    hol_light_dir = (
        Path(args.hol_light_dir).resolve()
        if args.hol_light_dir
        else workspace_dir / "hol-light"
    )
    log_file = (
        Path(args.log_file).resolve()
        if args.log_file
        else workspace_dir / "lightcake-run.log"
    )

    if not (lightcake_dir / "check.ml").is_file():
        print(f"{lightcake_dir} does not contain check.ml", file=sys.stderr)
        return 1
    if not hol_light_dir.is_dir():
        print(f"HOL Light directory does not exist: {hol_light_dir}", file=sys.stderr)
        return 1

    try:
        lightcake_commit = resolve_commit(lightcake_dir, "LIGHTCAKE_COMMIT")
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
        "lightcake_dir": str(lightcake_dir),
        "lightcake_commit": lightcake_commit,
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
            else workspace_dir / "lightcake-results.json"
        )
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text)
        print(f"Wrote {output_path}", file=sys.stderr)

    return 0 if counts["fail"] == 0 and counts["missing"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

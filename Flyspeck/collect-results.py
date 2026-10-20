#!/usr/bin/env python3
"""Collect the full Flyspeck HOL Light sequence result as JSON."""

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
COMPLETION_MARKER = "FLYSPECK_BUILD_SEQUENCE_FULL_COMPLETED"


def is_failed(log_text: str) -> bool:
    for line in log_text.splitlines():
        if SUSPICIOUS_MARKER.search(line) and not BENIGN_MARKER.search(line):
            return True
    return False


def parse_timing(log_text: str) -> dict:
    match = None
    for candidate in TIME_LINE.finditer(log_text):
        match = candidate
    if match is None:
        return {
            "elapsed_seconds": None,
            "start_unixtime": None,
            "end_unixtime": None,
        }
    return {
        "elapsed_seconds": float(match.group("elapsed")),
        "start_unixtime": float(match.group("start")),
        "end_unixtime": float(match.group("end")),
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect the full Flyspeck sequence result as JSON."
    )
    parser.add_argument("flyspeck_dir", help="path to the Flyspeck checkout")
    parser.add_argument(
        "log_file",
        nargs="?",
        help="Flyspeck run log (default: <workspace dir>/flyspeck-run.log)",
    )
    parser.add_argument(
        "--hol-light-dir",
        help="HOL Light checkout used for the run "
             "(default: sibling <workspace dir>/hol-light)",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="JSON output path (default: <workspace dir>/flyspeck-results.json)",
    )
    parser.add_argument(
        "--no-write",
        action="store_true",
        help="do not write a JSON file, only print to stdout",
    )
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args(sys.argv[1:])
    flyspeck_dir = Path(args.flyspeck_dir).resolve()
    workspace_dir = flyspeck_dir.parent
    hol_light_dir = (
        Path(args.hol_light_dir).resolve()
        if args.hol_light_dir
        else workspace_dir / "hol-light"
    )
    log_file = (
        Path(args.log_file).resolve()
        if args.log_file
        else workspace_dir / "flyspeck-run.log"
    )

    if not (flyspeck_dir / "load_flyspeck.ml").is_file():
        print(f"{flyspeck_dir} does not contain load_flyspeck.ml", file=sys.stderr)
        return 1
    if not hol_light_dir.is_dir():
        print(f"HOL Light directory does not exist: {hol_light_dir}", file=sys.stderr)
        return 1

    try:
        flyspeck_commit = resolve_commit(flyspeck_dir, "FLYSPECK_COMMIT")
        hol_light_commit = resolve_commit(hol_light_dir, "HOL_LIGHT_COMMIT")
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1

    if log_file.is_file():
        log_text = log_file.read_text(errors="replace")
        timing = parse_timing(log_text)
        status = (
            "pass"
            if COMPLETION_MARKER in log_text and not is_failed(log_text)
            else "fail"
        )
    else:
        timing = parse_timing("")
        status = "missing"

    test = {
        "name": "Flyspeck/Build.build_sequence_full",
        "log_path": str(log_file),
        "status": status,
        **timing,
    }
    counts = {"pass": 0, "fail": 0, "skip": 0, "missing": 0}
    counts[status] = 1

    output = {
        "flyspeck_dir": str(flyspeck_dir),
        "flyspeck_commit": flyspeck_commit,
        "hol_light_dir": str(hol_light_dir),
        "hol_light_commit": hol_light_commit,
        "log_file": str(log_file),
        "machine": collect_machine_info(),
        "total": 1,
        "counts": counts,
        "total_elapsed_seconds": timing["elapsed_seconds"] or 0,
        "tests": [test],
    }

    text = json.dumps(output, indent=2) + "\n"
    sys.stdout.write(text)
    if not args.no_write:
        output_path = (
            Path(args.output).resolve()
            if args.output
            else workspace_dir / "flyspeck-results.json"
        )
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(text)
        print(f"Wrote {output_path}", file=sys.stderr)

    return 0 if status == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())

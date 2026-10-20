"""Shared commit-hash resolution for benchmark result reports."""

import re
import subprocess
from pathlib import Path

COMMIT_HASH = re.compile(r"^[0-9a-fA-F]{40}$")


def resolve_commit(checkout_dir: Path, marker_name: str) -> str:
    """Return a checkout's full commit hash from its marker file or Git.

    Benchmark tarball checkouts record the hash in a marker file, while normal
    clones can fall back to `git rev-parse HEAD`. Raise an error rather than
    emitting a report without reproducible source provenance.
    """
    marker_path = checkout_dir / marker_name
    if marker_path.is_file():
        commit = marker_path.read_text().strip()
        if COMMIT_HASH.fullmatch(commit):
            return commit.lower()
        raise RuntimeError(
            f"{marker_path} does not contain a full 40-character commit hash"
        )

    try:
        result = subprocess.run(
            ["git", "-C", str(checkout_dir), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise RuntimeError(
            f"Could not determine the commit for {checkout_dir}: "
            f"missing {marker_name} and git rev-parse failed"
        ) from error

    commit = result.stdout.strip()
    if not COMMIT_HASH.fullmatch(commit):
        raise RuntimeError(f"Git returned an invalid commit hash for {checkout_dir}")
    return commit.lower()

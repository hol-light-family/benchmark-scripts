"""Shared machine metadata collection for benchmark result reports."""

import os
import platform
import subprocess
from pathlib import Path


def collect_machine_info() -> dict:
    """Collect stable host metadata useful when comparing benchmark runs."""
    memory_total_bytes = None
    try:
        for line in Path("/proc/meminfo").read_text().splitlines():
            if line.startswith("MemTotal:"):
                memory_total_bytes = int(line.split()[1]) * 1024
                break
    except (OSError, ValueError, IndexError):
        pass

    if memory_total_bytes is None:
        try:
            memory_total_bytes = (
                os.sysconf("SC_PHYS_PAGES") * os.sysconf("SC_PAGE_SIZE")
            )
        except (AttributeError, OSError, ValueError):
            pass

    cpu_brand = None
    try:
        result = subprocess.run(
            ["lscpu"],
            capture_output=True,
            text=True,
            check=True,
            env={**os.environ, "LC_ALL": "C"},
        )
        for line in result.stdout.splitlines():
            key, separator, value = line.partition(":")
            if separator and key.strip() == "Model name" and value.strip():
                cpu_brand = value.strip()
                break
    except (OSError, subprocess.CalledProcessError):
        pass

    if cpu_brand is None:
        try:
            fields = {}
            for line in Path("/proc/cpuinfo").read_text(errors="replace").splitlines():
                key, separator, value = line.partition(":")
                if separator and value.strip():
                    fields.setdefault(key.strip().lower(), value.strip())
            cpu_brand = fields.get("model name") or fields.get("hardware")
            if (
                cpu_brand is None
                and fields.get("cpu implementer")
                and fields.get("cpu part")
            ):
                cpu_brand = (
                    f"implementer {fields['cpu implementer']}, "
                    f"part {fields['cpu part']}"
                )
        except OSError:
            pass

    if cpu_brand is None:
        cpu_brand = platform.processor() or "unknown"

    try:
        num_cores = int(os.sysconf("SC_NPROCESSORS_ONLN"))
    except (AttributeError, OSError, ValueError):
        num_cores = os.cpu_count()

    return {
        "architecture": platform.machine() or "unknown",
        "cpu_brand": cpu_brand,
        "num_cores": num_cores,
        "memory_total_bytes": memory_total_bytes,
        "memory_total_gib": (
            round(memory_total_bytes / (1024**3), 2)
            if memory_total_bytes is not None
            else None
        ),
    }

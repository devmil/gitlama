#!/usr/bin/env python3
"""Measure isolated packaged macOS startup through durable bootstrap readiness."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)]


def launch(executable: Path, repository: Path, *, timeout: float) -> float:
    with tempfile.TemporaryDirectory(prefix="ns-startup-", dir="/tmp") as name:
        root = Path(name)
        profile_root = root / "profile"
        runtime = root / "runtime"
        profile_root.mkdir()
        runtime.mkdir(mode=0o700)
        environment = dict(os.environ)
        environment["GITLAMA_PROFILE_ROOT"] = str(profile_root)
        environment["GITLAMA_RUNTIME_DIR"] = str(runtime)
        environment.pop("GITLAMA_NATIVE_LIBRARY", None)
        settings = profile_root / "settings.json"
        started = time.perf_counter()
        process = subprocess.Popen(
            [str(executable), str(repository)],
            cwd=root,
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            deadline = started + timeout
            while process.poll() is None and not settings.is_file():
                if time.perf_counter() >= deadline:
                    raise RuntimeError("startup readiness timed out")
                time.sleep(0.005)
            if process.poll() is not None:
                raise RuntimeError("application exited before startup readiness")
            elapsed_ms = (time.perf_counter() - started) * 1000
            time.sleep(0.05)
            if process.poll() is not None:
                raise RuntimeError("application exited immediately after readiness")
            return elapsed_ms
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=3)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("repository", type=Path)
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--timeout-seconds", type=float, default=10)
    parser.add_argument("--report", type=Path, required=True)
    arguments = parser.parse_args()
    executable = arguments.executable.resolve()
    repository = arguments.repository.resolve()
    if not executable.is_file() or not (repository / ".git").exists():
        raise SystemExit("provide a packaged executable and Git repository")
    if arguments.warmups < 0 or arguments.samples < 5:
        raise SystemExit("provide at least five measured samples")

    for _ in range(arguments.warmups):
        launch(executable, repository, timeout=arguments.timeout_seconds)
    samples = [
        launch(executable, repository, timeout=arguments.timeout_seconds)
        for _ in range(arguments.samples)
    ]
    report = {
        "schema": 1,
        "readiness": "isolated settings transaction complete and process remains alive",
        "warmups": arguments.warmups,
        "samples": arguments.samples,
        "milliseconds": {
            "median": round(statistics.median(samples), 3),
            "p95": round(percentile(samples, 0.95), 3),
            "max": round(max(samples), 3),
            "min": round(min(samples), 3),
        },
        "rawMilliseconds": [round(value, 3) for value in samples],
    }
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(arguments.report)


if __name__ == "__main__":
    main()

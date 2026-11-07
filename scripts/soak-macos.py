#!/usr/bin/env python3
"""Exercise packaged macOS tab/watcher/refresh churn and record bounded resources."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

SOAK_POLICY = {
    "maximumSteadyRssSlopeKiBPerSecond": 48.0,
    "maximumQuiescentThreadGrowth": 4,
    "maximumQuiescentOpenFileGrowth": 4,
    "requiredQuiescentChildren": 0,
    "minimumQuiescentSamples": 5,
}


def run(*arguments: object, environment: dict[str, str] | None = None) -> None:
    subprocess.run(
        [str(argument) for argument in arguments],
        check=True,
        env=environment,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
    )


# The app answers a forwarded command within two seconds. A slow runner can
# miss that window, which the client reports as busy. Retry only those
# transient rejections and count them in the report; other forwarding
# failures stay fatal.
FORWARD_BUSY_DEADLINE_SECONDS = 45.0
FORWARD_BUSY_RETRY_SECONDS = 0.25
BUSY_FAILURE = "gitlama_forwarding_failure=busy"


def forward(
    executable: Path,
    *arguments: object,
    environment: dict[str, str],
    retries: dict[str, int],
    invoke=subprocess.run,
    sleep=time.sleep,
    clock=time.monotonic,
) -> None:
    command = [str(executable), *(str(argument) for argument in arguments)]
    deadline = clock() + FORWARD_BUSY_DEADLINE_SECONDS
    while True:
        result = invoke(
            command,
            env={**environment, "GITLAMA_FORWARDING_DIAGNOSTICS": "1"},
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
            check=False,
        )
        if result.returncode == 0:
            return
        busy = result.returncode == 2 and BUSY_FAILURE in result.stderr.splitlines()
        if not busy:
            raise subprocess.CalledProcessError(result.returncode, command)
        retries["busy"] += 1
        if clock() >= deadline:
            raise RuntimeError("forwarded invocation stayed busy")
        sleep(FORWARD_BUSY_RETRY_SECONDS)


def process_metric(pid: int, column: str) -> int:
    value = subprocess.check_output(
        ["ps", "-o", f"{column}=", "-p", str(pid)], text=True
    ).strip()
    if not value:
        raise RuntimeError("soak application exited")
    return int(value)


def count_lines(*arguments: str) -> int:
    result = subprocess.run(arguments, capture_output=True, text=True, check=False)
    return len(result.stdout.splitlines()) if result.returncode == 0 else 0


def percentile(values: list[int], fraction: float) -> int:
    ordered = sorted(values)
    return ordered[round((len(ordered) - 1) * fraction)]


def slope(samples: list[tuple[float, int]]) -> float:
    xs = [sample[0] for sample in samples]
    ys = [sample[1] for sample in samples]
    x_mean = statistics.fmean(xs)
    y_mean = statistics.fmean(ys)
    denominator = sum((value - x_mean) ** 2 for value in xs)
    if denominator == 0:
        return 0.0
    return sum((x - x_mean) * (y - y_mean) for x, y in samples) / denominator


def resource_sample(pid: int, started: float) -> dict[str, float | int]:
    return {
        "elapsedSeconds": round(time.monotonic() - started, 3),
        "rssKiB": process_metric(pid, "rss"),
        "threads": count_lines("ps", "-M", str(pid)),
        "openFiles": count_lines("lsof", "-p", str(pid)),
        "children": count_lines("pgrep", "-P", str(pid)),
    }


def quiescent_median(samples: list[dict[str, float | int]], metric: str) -> float:
    return statistics.median(float(sample[metric]) for sample in samples)


def evaluate_samples(
    samples: list[dict[str, float | int]],
    baseline_samples: list[dict[str, float | int]],
    final_samples: list[dict[str, float | int]],
) -> tuple[dict[str, object], list[dict[str, float | int]], float]:
    if len(samples) < 5:
        raise ValueError("soak acceptance requires at least five workload samples")
    minimum_quiescent_samples = int(SOAK_POLICY["minimumQuiescentSamples"])
    if (
        len(baseline_samples) < minimum_quiescent_samples
        or len(final_samples) < minimum_quiescent_samples
    ):
        raise ValueError(
            "soak acceptance requires at least five samples in each quiescent window"
        )
    steady_samples = samples[max(1, len(samples) // 5) :]
    steady_rss_slope = slope(
        [
            (float(sample["elapsedSeconds"]), int(sample["rssKiB"]))
            for sample in steady_samples
        ]
    )
    failures = []
    if steady_rss_slope > SOAK_POLICY["maximumSteadyRssSlopeKiBPerSecond"]:
        failures.append("steady-rss-slope")
    thread_growth = quiescent_median(final_samples, "threads") - quiescent_median(
        baseline_samples, "threads"
    )
    open_file_growth = quiescent_median(
        final_samples, "openFiles"
    ) - quiescent_median(baseline_samples, "openFiles")
    if thread_growth > SOAK_POLICY["maximumQuiescentThreadGrowth"]:
        failures.append("thread-growth")
    if open_file_growth > SOAK_POLICY["maximumQuiescentOpenFileGrowth"]:
        failures.append("open-file-growth")
    if any(
        int(sample["children"]) != SOAK_POLICY["requiredQuiescentChildren"]
        for sample in final_samples
    ):
        failures.append("remaining-child-process")
    return (
        {
            "passed": not failures,
            "failures": failures,
            "policy": SOAK_POLICY,
            "quiescentGrowth": {
                "threads": thread_growth,
                "openFiles": open_file_growth,
            },
        },
        steady_samples,
        steady_rss_slope,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    parser.add_argument("--duration-seconds", type=int, default=600)
    parser.add_argument("--report", type=Path, required=True)
    arguments = parser.parse_args()
    executable = arguments.executable.resolve()
    if not executable.is_file() or arguments.duration_seconds < 60:
        raise SystemExit("provide a packaged executable and at least 60 seconds")

    with tempfile.TemporaryDirectory(prefix="ns-soak-", dir="/tmp") as name:
        root = Path(name)
        profile_root = root / "profile"
        runtime = root / "runtime"
        profile_root.mkdir()
        runtime.mkdir(mode=0o700)
        environment = dict(os.environ)
        environment["GITLAMA_PROFILE_ROOT"] = str(profile_root)
        environment["GITLAMA_RUNTIME_DIR"] = str(runtime)
        environment.pop("GITLAMA_NATIVE_LIBRARY", None)
        retries = {"busy": 0}
        repositories = []
        for index in range(3):
            repository = root / f"repository-{index}"
            repository.mkdir()
            run("git", "init", "--quiet", repository)
            run("git", "-C", repository, "config", "user.name", "GitLama Soak")
            run("git", "-C", repository, "config", "user.email", "soak@example.invalid")
            (repository / "tracked.txt").write_text("initial\n")
            run("git", "-C", repository, "add", "tracked.txt")
            run("git", "-C", repository, "commit", "--quiet", "-m", "initial")
            repositories.append(repository)

        process = subprocess.Popen(
            [str(executable), str(repositories[0])],
            env=environment,
            cwd=root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        started = time.monotonic()
        settings = profile_root / "settings.json"
        try:
            deadline = started + 20
            while process.poll() is None and not settings.is_file() and time.monotonic() < deadline:
                time.sleep(0.1)
            if process.poll() is not None or not settings.is_file():
                raise RuntimeError("packaged application did not become ready")
            for repository in repositories[1:]:
                forward(
                    executable,
                    repository,
                    environment=environment,
                    retries=retries,
                )
            for repository in repositories:
                forward(
                    executable,
                    "--command",
                    "repository.refresh",
                    environment=environment,
                    retries=retries,
                )
            time.sleep(5)
            baseline_samples = []
            for _ in range(int(SOAK_POLICY["minimumQuiescentSamples"])):
                baseline_samples.append(resource_sample(process.pid, started))
                time.sleep(1)
            samples = []
            cycles = 0
            workload_deadline = time.monotonic() + arguments.duration_seconds
            while time.monotonic() < workload_deadline:
                repository = repositories[cycles % len(repositories)]
                with (repository / "tracked.txt").open("a") as stream:
                    stream.write(f"cycle {cycles}\n")
                run("git", "-C", repository, "add", "tracked.txt")
                run("git", "-C", repository, "commit", "--quiet", "-m", f"cycle {cycles}")
                forward(
                    executable,
                    repository,
                    environment=environment,
                    retries=retries,
                )
                forward(
                    executable,
                    "--command",
                    "repository.refresh",
                    environment=environment,
                    retries=retries,
                )
                samples.append(resource_sample(process.pid, started))
                cycles += 1
                time.sleep(1)
            if process.poll() is not None:
                raise RuntimeError("packaged application exited during soak")
            time.sleep(2)
            final_samples = []
            for _ in range(int(SOAK_POLICY["minimumQuiescentSamples"])):
                final_samples.append(resource_sample(process.pid, started))
                time.sleep(1)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)

    rss = [sample["rssKiB"] for sample in samples]
    acceptance, steady_samples, steady_rss_slope = evaluate_samples(
        samples, baseline_samples, final_samples
    )
    thread_baseline = quiescent_median(baseline_samples, "threads")
    thread_final = quiescent_median(final_samples, "threads")
    open_file_baseline = quiescent_median(baseline_samples, "openFiles")
    open_file_final = quiescent_median(final_samples, "openFiles")
    report = {
        "schema": 2,
        "durationSeconds": round(final_samples[-1]["elapsedSeconds"], 3),
        "cycles": cycles,
        "sampleCount": len(samples),
        "workload": "three repository tab switches, external commits, watcher events and explicit refresh per cycle",
        "rssKiB": {
            "first": rss[0],
            "median": round(statistics.median(rss)),
            "p95": percentile(rss, 0.95),
            "max": max(rss),
            "last": rss[-1],
            "linearSlopeKiBPerSecond": round(
                slope([(sample["elapsedSeconds"], sample["rssKiB"]) for sample in samples]),
                3,
            ),
            "steadyStateLinearSlopeKiBPerSecond": round(steady_rss_slope, 3),
            "steadyStateStartsAtSeconds": steady_samples[0]["elapsedSeconds"],
        },
        "threads": {
            "quiescentBaselineMedian": thread_baseline,
            "workloadMax": max(s["threads"] for s in samples),
            "quiescentFinalMedian": thread_final,
            "quiescentGrowth": thread_final - thread_baseline,
        },
        "openFiles": {
            "quiescentBaselineMedian": open_file_baseline,
            "workloadMax": max(s["openFiles"] for s in samples),
            "quiescentFinalMedian": open_file_final,
            "quiescentGrowth": open_file_final - open_file_baseline,
        },
        "children": {
            "workloadMax": max(s["children"] for s in samples),
            "quiescentFinalMax": max(s["children"] for s in final_samples),
        },
        "busyForwardRetries": retries["busy"],
        "acceptance": acceptance,
        "quiescentBaselineSamples": baseline_samples,
        "samples": samples,
        "quiescentFinalSamples": final_samples,
    }
    arguments.report.parent.mkdir(parents=True, exist_ok=True)
    arguments.report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(arguments.report)
    if acceptance["failures"]:
        raise SystemExit(
            f"soak acceptance failed: {', '.join(acceptance['failures'])}"
        )


if __name__ == "__main__":
    main()

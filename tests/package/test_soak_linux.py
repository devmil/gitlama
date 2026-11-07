import importlib.util
from pathlib import Path
import subprocess
import unittest


def load_soak_module():
    script = Path("scripts/soak-linux.py")
    spec = importlib.util.spec_from_file_location("gitlama_soak_linux", script)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load Linux soak script")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SOAK = load_soak_module()


def sample(elapsed, rss, threads=8, files=20, children=0):
    return {
        "elapsedSeconds": elapsed,
        "rssKiB": rss,
        "threads": threads,
        "openFiles": files,
        "children": children,
    }


class LinuxSoakAcceptanceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.baseline = [sample(i, 100_000) for i in range(5)]
        self.workload = [sample(10 + i, 100_000 + i) for i in range(10)]
        self.final = [sample(30 + i, 100_020) for i in range(5)]

    def test_accepts_bounded_steady_state_and_clean_final_resources(self) -> None:
        acceptance, steady, rss_slope = SOAK.evaluate_samples(
            self.workload, self.baseline, self.final
        )
        self.assertTrue(acceptance["passed"])
        self.assertEqual(acceptance["failures"], [])
        self.assertEqual(len(steady), 8)
        self.assertLess(rss_slope, 32)

    def test_rejects_each_unbounded_resource_condition(self) -> None:
        growing = [sample(10 + i, 100_000 + i * 100) for i in range(10)]
        acceptance, _, _ = SOAK.evaluate_samples(growing, self.baseline, self.final)
        self.assertIn("steady-rss-slope", acceptance["failures"])

        final = [sample(30 + i, 100_020, threads=13, files=25) for i in range(5)]
        acceptance, _, _ = SOAK.evaluate_samples(self.workload, self.baseline, final)
        self.assertIn("thread-growth", acceptance["failures"])
        self.assertIn("open-file-growth", acceptance["failures"])

        final = [sample(30 + i, 100_020, children=1) for i in range(5)]
        acceptance, _, _ = SOAK.evaluate_samples(self.workload, self.baseline, final)
        self.assertIn("remaining-child-process", acceptance["failures"])

    def test_rejects_too_few_samples(self) -> None:
        with self.assertRaisesRegex(ValueError, "at least five workload"):
            SOAK.evaluate_samples(self.workload[:4], self.baseline, self.final)
        with self.assertRaisesRegex(ValueError, "five samples"):
            SOAK.evaluate_samples(self.workload, self.baseline[:4], self.final)


class ForwardBusyRetryTest(unittest.TestCase):
    def forward(self, results, clock=None):
        calls = []
        retries = {"busy": 0}

        def invoke(command, **options):
            calls.append((command, options["env"]))
            code, stderr = results.pop(0)
            return subprocess.CompletedProcess(command, code, "", stderr)

        SOAK.forward(
            Path("/app/gitlama"),
            "--command",
            "repository.refresh",
            environment={"KEEP": "1"},
            retries=retries,
            invoke=invoke,
            sleep=lambda _: None,
            clock=clock or (lambda: 0.0),
        )
        return calls, retries

    def test_retries_busy_rejections_and_counts_them(self) -> None:
        busy = (2, "gitlama_forwarding_failure=busy\nforwarding failed\n")
        calls, retries = self.forward([busy, busy, (0, "")])
        self.assertEqual(len(calls), 3)
        self.assertEqual(retries["busy"], 2)
        command, environment = calls[0]
        self.assertEqual(command, ["/app/gitlama", "--command", "repository.refresh"])
        self.assertEqual(environment["GITLAMA_FORWARDING_DIAGNOSTICS"], "1")
        self.assertEqual(environment["KEEP"], "1")

    def test_other_forwarding_failures_stay_fatal(self) -> None:
        for result in [
            (2, "gitlama_forwarding_failure=precondition\n"),
            (2, "gitlama_forwarding_failure=notRunning\n"),
            (1, "gitlama_forwarding_failure=busy\n"),
        ]:
            with self.assertRaises(subprocess.CalledProcessError):
                self.forward([result])

    def test_busy_beyond_the_deadline_fails(self) -> None:
        times = iter([0.0, 10.0, SOAK.FORWARD_BUSY_DEADLINE_SECONDS + 1])
        busy = (2, "gitlama_forwarding_failure=busy\n")
        with self.assertRaisesRegex(RuntimeError, "stayed busy"):
            self.forward([busy, busy], clock=lambda: next(times))


if __name__ == "__main__":
    unittest.main()

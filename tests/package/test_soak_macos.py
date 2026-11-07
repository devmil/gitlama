import importlib.util
from pathlib import Path
import subprocess
import unittest


def load_soak_module():
    script = Path("scripts/soak-macos.py")
    spec = importlib.util.spec_from_file_location("gitlama_soak_macos", script)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load soak harness")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SOAK = load_soak_module()


def workload_samples(*, rss_step=1):
    return [
        {
            "elapsedSeconds": float(index),
            "rssKiB": 1000 + index * rss_step,
            "threads": 10,
            "openFiles": 20,
            "children": 0,
        }
        for index in range(10)
    ]


def quiescent_samples(*, threads=10, files=20, children=0):
    return [
        {
            "elapsedSeconds": float(index),
            "rssKiB": 1000,
            "threads": threads,
            "openFiles": files,
            "children": children,
        }
        for index in range(5)
    ]


class SoakAcceptanceTest(unittest.TestCase):
    def test_accepts_bounded_steady_state_and_clean_final_resources(self) -> None:
        baseline = quiescent_samples()
        final = quiescent_samples()
        final[-1].update(threads=20, openFiles=40)

        acceptance, steady, rss_slope = SOAK.evaluate_samples(
            workload_samples(), baseline, final
        )

        self.assertTrue(acceptance["passed"])
        self.assertEqual(acceptance["failures"], [])
        self.assertEqual(len(steady), 8)
        self.assertEqual(rss_slope, 1.0)

    def test_rejects_each_unbounded_resource_condition(self) -> None:
        acceptance, _, _ = SOAK.evaluate_samples(
            workload_samples(rss_step=100),
            quiescent_samples(),
            quiescent_samples(threads=15, files=25, children=1),
        )

        self.assertFalse(acceptance["passed"])
        self.assertEqual(
            acceptance["failures"],
            [
                "steady-rss-slope",
                "thread-growth",
                "open-file-growth",
                "remaining-child-process",
            ],
        )

    def test_rejects_too_few_samples(self) -> None:
        baseline = quiescent_samples()
        final = quiescent_samples()
        with self.assertRaisesRegex(ValueError, "five workload"):
            SOAK.evaluate_samples(workload_samples()[:4], baseline, final)
        with self.assertRaisesRegex(ValueError, "each quiescent window"):
            SOAK.evaluate_samples(workload_samples(), baseline[:4], final)
        with self.assertRaisesRegex(ValueError, "each quiescent window"):
            SOAK.evaluate_samples(workload_samples(), baseline, final[:4])


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

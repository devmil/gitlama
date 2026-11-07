from __future__ import annotations

from pathlib import Path
import json
import subprocess
import tempfile
import unittest
from unittest import mock

from scripts import verify

CONNECTION = (
    "Failed to load: Unable to connect to flutter_tester process: "
    "WebSocketException: Invalid WebSocket upgrade request"
)


def suite(identifier: int, path: str) -> dict:
    return {"type": "suite", "suite": {"id": identifier, "path": path}}


def test(identifier: int, suite_id: int) -> dict:
    return {"type": "testStart", "test": {"id": identifier, "suiteID": suite_id}}


def error(identifier: int, message: str) -> dict:
    return {"type": "error", "testID": identifier, "error": message}


def done(identifier: int, result: str) -> dict:
    return {"type": "testDone", "testID": identifier, "result": result}


class HarnessRetryTest(unittest.TestCase):
    def failures(self, *events: dict) -> list[str] | None:
        with tempfile.TemporaryDirectory() as directory:
            report = Path(directory) / "report.json"
            report.write_text(
                "\n".join(json.dumps(event) for event in events), encoding="utf-8"
            )
            return verify.harness_failures(report)

    def test_connection_failures_name_their_files(self) -> None:
        self.assertEqual(
            self.failures(
                suite(0, "/a_test.dart"),
                suite(1, "/b_test.dart"),
                test(1, 0),
                error(1, CONNECTION),
                done(1, "error"),
                test(2, 1),
                done(2, "success"),
            ),
            ["/a_test.dart"],
        )

    def test_any_other_failure_is_not_retried(self) -> None:
        self.assertIsNone(
            self.failures(
                suite(0, "/a_test.dart"),
                suite(1, "/b_test.dart"),
                test(1, 0),
                error(1, CONNECTION),
                done(1, "error"),
                test(2, 1),
                error(2, "Expected: true\n  Actual: <false>"),
                done(2, "failure"),
            )
        )

    def test_a_failure_without_an_error_is_not_retried(self) -> None:
        self.assertIsNone(
            self.failures(suite(0, "/a_test.dart"), test(1, 0), done(1, "error"))
        )

    def test_only_files_that_failed_to_connect_run_again(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            calls: list[tuple[str, ...]] = []

            def run(*args: str) -> None:
                calls.append(args)
                if len(calls) > 1:
                    return
                report = Path(args[-1].removeprefix("--file-reporter=json:"))
                report.write_text(
                    "\n".join(
                        json.dumps(event)
                        for event in (
                            suite(0, str(root / "test" / "a_test.dart")),
                            test(1, 0),
                            error(1, CONNECTION),
                            done(1, "error"),
                        )
                    ),
                    encoding="utf-8",
                )
                raise subprocess.CalledProcessError(1, args)

            with (
                mock.patch.object(verify, "ROOT", root),
                mock.patch.object(verify, "run", side_effect=run),
            ):
                verify.flutter_test("--tags", "remote")
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[1][:4], ("flutter", "test", "--tags", "remote"))
        self.assertEqual(calls[1][-1], str(Path("test") / "a_test.dart"))

    def test_a_real_failure_is_not_run_again(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            run = mock.Mock(side_effect=subprocess.CalledProcessError(1, "flutter"))
            with (
                mock.patch.object(verify, "ROOT", Path(directory)),
                mock.patch.object(verify, "run", run),
                self.assertRaises(subprocess.CalledProcessError),
            ):
                verify.flutter_test()
            self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()

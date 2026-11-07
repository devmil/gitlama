import importlib.util
from pathlib import Path
import sys
import unittest

# The script imports its sibling ``lib`` package, as it does when run from scripts/.
sys.path.insert(0, str(Path("scripts").resolve()))
_spec = importlib.util.spec_from_file_location(
    "qualify_macos_package", Path("scripts/qualify-macos-package.py")
)
qualify = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(qualify)


class MacosPayloadArchitectureTest(unittest.TestCase):
    def test_the_app_is_arm64_and_each_remote_helper_keeps_its_platform(self) -> None:
        self.assertEqual(qualify.expected_architectures("Contents/MacOS/GitLama"), ["arm64"])
        self.assertEqual(
            qualify.expected_architectures("Contents/Frameworks/App.framework/App"), ["arm64"]
        )
        self.assertEqual(
            qualify.expected_architectures(
                "Contents/Resources/remote-helper/macos-arm64/gitlama-remote-helper"
            ),
            ["arm64"],
        )
        self.assertEqual(
            qualify.expected_architectures(
                "Contents/Resources/remote-helper/macos-x86_64/gitlama-remote-helper"
            ),
            ["x86_64"],
        )

    def test_an_unknown_helper_platform_is_refused(self) -> None:
        with self.assertRaises(BaseException):
            qualify.expected_architectures(
                "Contents/Resources/remote-helper/macos-universal/gitlama-remote-helper"
            )


if __name__ == "__main__":
    unittest.main()

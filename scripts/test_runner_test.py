"""Regression checks for skipped/required suite accounting."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

RUNNER = Path(__file__).with_name("test.py")


class RunnerTests(unittest.TestCase):
    def run_suite(self, *flags):
        with tempfile.TemporaryDirectory() as directory:
            suite = Path(directory) / "optional.lua"
            suite.write_text("print('SKIP optional integration: dependency absent')\n")
            return subprocess.run(
                [sys.executable, str(RUNNER), str(suite), *flags],
                capture_output=True, text=True, timeout=10,
            )

    def test_skip_is_not_a_pass(self):
        result = self.run_suite()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 passed, 1 skipped, 0 failed", result.stdout)
        self.assertIn("dependency absent", result.stdout)

    def test_required_skip_fails(self):
        result = self.run_suite("--require-test", "optional.lua")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Required suite skipped", result.stdout)
        self.assertIn("0 passed, 0 skipped, 1 failed", result.stdout)

    def test_missing_required_suite_fails(self):
        result = self.run_suite("--require-test", "missing.lua")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("required suites are not selected", result.stderr)


if __name__ == "__main__":
    unittest.main()

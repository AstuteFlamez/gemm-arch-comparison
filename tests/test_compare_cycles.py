"""Check the calculator against known schedules and useful-operation counts."""

from pathlib import Path
import subprocess
import sys
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/compare_cycles.py"


class CompareCyclesTests(unittest.TestCase):
    def run_cli(self, *args):
        return subprocess.run([sys.executable, "-B", str(SCRIPT), *args],
                              capture_output=True, text=True)

    def test_default_comparison(self):
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("Schedule-based", result.stdout)
        self.assertIn("external input loading/readback excluded", result.stdout)
        rows = [line.split() for line in result.stdout.splitlines()[3:]]
        # Hand-checked values: e.g. 8^3 = 512 useful MACs / (4 * 512 clocks) = 25%.
        self.assertEqual(rows, [
            ["8x8", "systolic", "544", "23.53%"],
            ["8x8", "conventional", "512", "25.00%"],
            ["16x16", "systolic", "3712", "27.59%"],
            ["16x16", "conventional", "3584", "28.57%"],
            ["32x32", "systolic", "27136", "30.19%"],
            ["32x32", "conventional", "26624", "30.77%"],
        ])

    def test_selected_sizes(self):
        result = self.run_cli("--sizes", "32", "8")
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = [line.split() for line in result.stdout.splitlines()[3:]]
        self.assertEqual([row[0] for row in rows], ["32x32", "32x32", "8x8", "8x8"])

    def test_unsupported_sizes_fail_without_results(self):
        for size in ("0", "7", "64", "eight"):
            with self.subTest(size=size):
                result = self.run_cli("--sizes", size)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertIn("error:", result.stderr)
                self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main()

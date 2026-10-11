"""Failure checks for the PPA measurement boundary and report provenance."""

import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("run_gemm_ppa", ROOT / "scripts/run_gemm_ppa.py")
ppa = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ppa)


class PpaChecks(unittest.TestCase):
    def test_saif_time_units_and_capture_window(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.saif"
            path.write_text('(TIMESCALE 1 ps)(DURATION 10000)(INSTANCE dut (NET (clk (TC 2))))')
            ppa.check_saif(path, 10)
            with self.assertRaisesRegex(ValueError, "window"):
                ppa.check_saif(path, 20)
            path.write_text('(TIMESCALE 1 ns)(DURATION 10)(INSTANCE dut (NET (clk (TC 0))))')
            with self.assertRaisesRegex(ValueError, "toggle"):
                ppa.check_saif(path, 10)
            path.write_text('(TIMESCALE 1 ns)(DURATION 10)(INSTANCE wrong (NET (clk (TC 2))))')
            with self.assertRaisesRegex(ValueError, "scope"):
                ppa.check_saif(path, 10)
            # Native VCS can finish and write a header-only file for a bad scope.
            path.write_text('(SAIFILE (TIMESCALE 1 ns)(DURATION 10.00))')
            with self.assertRaisesRegex(ValueError, "scope"):
                ppa.check_saif(path, 10)

    def test_partial_and_mismatched_measurements_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            with self.assertRaisesRegex(ValueError, "finish"):
                ppa.check_benchmark(folder, 8, 1, 10)
            (folder / "benchmark.pass").write_text("PASS")
            with (folder / "cycles.csv").open("w") as stream:
                writer = csv.writer(stream)
                writer.writerow(["case_index", "measured", "compute_cycles", "compute_ns",
                                 "transaction_ns", "outputs_checked"])
                for index in range(11):
                    writer.writerow([index, int(index >= 10), 544, 5440, 6730, 64])
            (folder / "window.csv").write_text("measured_pairs,duration_ns,clock_period_ns\n1,6730,10\n")
            result = ppa.check_benchmark(folder, 8, 1, 10)
            self.assertEqual(result["compute_cycles"], [544])
            (folder / "window.csv").write_text("measured_pairs,duration_ns,clock_period_ns\n1,5440,10\n")
            with self.assertRaisesRegex(ValueError, "window"):
                ppa.check_benchmark(folder, 8, 1, 10)

    def test_shell_success_does_not_hide_vendor_error(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(RuntimeError, "Command failed"):
                ppa.run_command([sys.executable, "-c", "print('Error: license unavailable')"],
                                Path(directory), "vendor.log", [])

    def test_redirected_report_errors_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            (folder / "reports.complete").touch()
            # DC can redirect an error into a report while its main log looks clean.
            (folder / "library.rpt").write_text(
                "Error: Check the installation of Library Compiler. (LCSH-3)\n0\n")
            with self.assertRaisesRegex(ValueError, "library.rpt"):
                ppa.check_dc_reports(folder)

    def test_tcl_paths_are_literal(self):
        value = 'path with spaces/[exec bad];$secret\\file"\nnext'
        script = "set example " + ppa.tcl_word(value) + "\nputs -nonewline $example\n"
        result = subprocess.run(["tclsh"], input=script, text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, value)
        self.assertEqual(result.stderr, "")

    def test_placeholder_generic_and_nonfinite_configs_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            config = json.loads((ROOT / "scripts/synopsys/config.example.json").read_text())
            path = folder / "config.json"
            path.write_text(json.dumps(config))
            with self.assertRaises(ValueError):
                ppa.load_config(path)
            library = folder / "cells.db"
            library.touch()
            config.update(target_db=str(library), library_name="cells", operating_condition="typical",
                          library_note="Unit-test fixture only")
            path.write_text(json.dumps(config))
            self.assertEqual(ppa.load_config(path)["clock_period_ns"], 10)
            config["clock_period_ns"] = float("nan")
            path.write_text(json.dumps(config))
            with self.assertRaises(ValueError):
                ppa.load_config(path)
            config["clock_period_ns"] = 10
            generic = folder / "gtech.db"
            generic.touch()
            config["target_db"] = str(generic)
            path.write_text(json.dumps(config))
            with self.assertRaisesRegex(ValueError, "generic"):
                ppa.load_config(path)

    def test_clock_precision(self):
        ppa.validate_clock(2.002)
        for value in (0, -10, 1.001, float("inf")):
            with self.assertRaises(ValueError):
                ppa.validate_clock(value)


if __name__ == "__main__":
    unittest.main()

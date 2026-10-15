"""Check shared build settings and report export without claiming a Quartus run."""

import csv
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
BOARD = ROOT / "fpga/de2_115"
TCLSH = shutil.which("tclsh")


@unittest.skipUnless(TCLSH, "tclsh is needed for the FPGA setup checks")
class FpgaSetupTests(unittest.TestCase):
    def run_tcl(self, script, **environment):
        return subprocess.run(
            [TCLSH], input=script, text=True, capture_output=True,
            cwd=BOARD if BOARD.is_dir() else ROOT,
            env={**os.environ, **environment}, check=False,
        )

    def settings(self, revision):
        result = self.run_tcl(r'''
foreach command {set_global_assignment set_instance_assignment set_location_assignment set_parameter} {
    proc $command {args} {puts [join [linsert $args 0 [lindex [info level 0] 0]] "\t"]}
}
if {[catch {source $env(TEST_QSF)} message]} {puts stderr $message; exit 1}
''', TEST_QSF=str(BOARD / f"{revision}.qsf"))
        self.assertEqual(result.returncode, 0, result.stderr)
        return [tuple(line.split("\t")) for line in result.stdout.splitlines()]

    @unittest.skipUnless(BOARD.is_dir(), "Optional local FPGA project is not present")
    def test_revisions_share_settings_and_select_only_their_core(self):
        revisions = ("gemm_de2_115", "gemm_de2_115_conventional")
        common = []
        output_dirs = []
        for selection, revision in enumerate(revisions):
            settings = self.settings(revision)
            self.assertIn(("set_parameter", "-name", "UseConventional", str(selection)), settings)
            sources = [row[3] for row in settings if row[1:3] == ("-name", "SYSTEMVERILOG_FILE")]
            for source in sources:
                self.assertTrue((BOARD / source).is_file(), source)
            expected = "conventional_gemm.sv" if selection else "systolic_gemm.sv"
            rejected = "systolic_array" if selection else "conventional_matmul"
            self.assertTrue(any(Path(source).name == expected for source in sources))
            self.assertFalse(any(rejected in source for source in sources))
            output_dirs.extend(row[3] for row in settings
                               if row[1:3] == ("-name", "PROJECT_OUTPUT_DIRECTORY"))
            common.append([row for row in settings if row[0] != "set_parameter" and
                           row[1:3] not in (("-name", "SYSTEMVERILOG_FILE"),
                                            ("-name", "PROJECT_OUTPUT_DIRECTORY"))])
        self.assertEqual(common[0], common[1])
        self.assertEqual(len(set(output_dirs)), 2)
        self.assertIn(("set_global_assignment", "-name", "SEED", "1"), common[0])
        self.assertIn(("set_location_assignment", "PIN_Y2", "-to", "clk"), common[0])

    # These stubs exercise the exporter, not the vendor's implementation.
    MOCK_REPORT_API = r'''
array set quartus [list args [list gemm_de2_115 gemm_de2_115 $env(TEST_OUT)] version MOCK]
proc load_package {name} {}
proc project_open {args} {}
proc project_close {} {}
proc load_report {} {}
proc unload_report {} {}
proc get_global_assignment {args} {return "mock setting"}
set panels [list {Flow Summary} {Fitter||Fitter Summary} \
    {Fitter||Resource Section||Resource Utilization by Entity} \
    {TimeQuest Timing Analyzer||Slow Model||Setup Summary}]
if {$env(MISSING) ne ""} {
    set panels [lreplace $panels $env(MISSING) $env(MISSING)]
}
proc get_report_panel_names {} {return $::panels}
proc get_report_panel_id {name} {return [lsearch -exact $::panels $name]}
proc get_number_of_rows {args} {return 3}
proc get_report_panel_row {args} {
    set row [lindex $args [expr {[lsearch -exact $args -row] + 1}]]
    switch $row {
        0 {return {Metric Value Notes}}
        1 {return [list "Logic, elements" 123 {inclusive "core" count}]}
        2 {return [list "Missing\nvalue" "" "not zero"]}
    }
}
if {[catch {source $env(EXPORT_SCRIPT)} message]} {puts stderr $message; exit 1}
'''

    def export(self, output, missing=""):
        return self.run_tcl(
            self.MOCK_REPORT_API, TEST_OUT=str(output), MISSING=missing,
            EXPORT_SCRIPT=str(ROOT / "scripts/export_quartus_reports.tcl"),
        )

    def test_export_preserves_vendor_text_units_and_missing_values(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = self.export(output)
            self.assertEqual(result.returncode, 0, result.stderr)
            reports = list(output.glob("*.csv"))
            self.assertEqual(len(reports), 4)
            for path in reports:
                with path.open(newline="") as handle:
                    rows = list(csv.reader(handle))
                self.assertEqual(rows[1], ["Logic, elements", "123", 'inclusive "core" count'])
                self.assertEqual(rows[2], ["Missing\nvalue", "", "not zero"])
            self.assertIn("Resource Utilization by Entity", (output / "panels.txt").read_text())

    def test_export_fails_when_a_required_report_group_is_missing(self):
        for index in (1, 2, 3):
            with self.subTest(index=index), tempfile.TemporaryDirectory() as directory:
                result = self.export(Path(directory), str(index))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Incomplete reports", result.stderr)


if __name__ == "__main__":
    unittest.main()

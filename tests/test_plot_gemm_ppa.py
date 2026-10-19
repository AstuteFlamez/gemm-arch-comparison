"""Protect report unit conversions and cycle-based extrapolation."""
import sys
import json
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from plot_gemm_ppa import power_mw, scheduled_cycles, read_area_units_review


class PlotDataTests(unittest.TestCase):
    def test_mixed_vendor_units(self):
        for unit, value in (("W", 1e-3), ("mW", 1), ("uW", 1000), ("nW", 1e6), ("pW", 1e9)):
            self.assertAlmostEqual(power_mw("Cell Leakage Power", f"Cell Leakage Power = {value} {unit}"), 1)

    def test_unit_required(self):
        with self.assertRaises(ValueError):
            power_mw("Total Dynamic Power", "Total Dynamic Power = 3.0")

    def test_nonfinite_power_rejected(self):
        for value in ("1e309 mW", "-1e309 mW", "1e308 W", "-1e308 W"):
            with self.subTest(value=value):
                with self.assertRaisesRegex(ValueError, "Non-finite power: Cell Leakage Power"):
                    power_mw("Cell Leakage Power", f"Cell Leakage Power = {value}")

    def test_observed_cycles_and_64_schedule(self):
        for size, systolic, conventional in ((8,544,512),(16,3712,3584),(32,27136,26624),(64,206848,204800)):
            self.assertEqual(scheduled_cycles(size,"systolic"),systolic)
            self.assertEqual(scheduled_cycles(size,"conventional"),conventional)

    def test_area_unit_evidence_must_match_library(self):
        review_path = Path(__file__).resolve().parents[1] / "docs/json/saed32-area-units.json"
        evidence = json.loads(review_path.read_text())
        metadata = {"library_sha256": evidence["library_sha256"],
                    "config": {"library_name": evidence["library_name"]}}
        self.assertEqual(read_area_units_review(review_path, metadata)["unit"], "um^2")
        metadata["library_sha256"] = "a different library build"
        with self.assertRaises(ValueError):
            read_area_units_review(review_path, metadata)


if __name__ == "__main__":
    unittest.main()

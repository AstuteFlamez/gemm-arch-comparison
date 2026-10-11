#!/usr/bin/env python3
"""Reproducible single-core benchmarks and Synopsys pre-layout PPA reports.

local: Icarus correctness/cycle/window checks (no power).
activity: VCS correctness/cycles plus native RTL SAIF (no library needed).
ppa: activity, then DC mapping/reports and Power Compiler estimation.
"""

import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from gen_gemm_vectors import render_vectors  # noqa: E402

COMMON = ["mac.sv", "fifo.sv", "memory/sram.sv", "memory/memory_wrapper.sv",
          "top_level_controller.sv"]
ARCHITECTURES = {
    "systolic": ["systolic_array/pe.sv", "systolic_array/systolic_array.sv",
                 "systolic_array/systolic_tile_controller.sv", "systolic_array/systolic_gemm.sv"],
    "conventional": ["conventional_matmul/conventional_tile_controller.sv",
                     "conventional_matmul/conventional_gemm.sv"],
}


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def tcl_word(value):
    """One literal Tcl word, including paths containing Tcl metacharacters."""
    result = str(value)
    for old, new in (("\\", "\\\\"), ("$", "\\$"), ("[", "\\["), ("]", "\\]"),
                     ('"', '\\"'), ("\n", "\\n"), ("\r", "\\r")):
        result = result.replace(old, new)
    return '"' + result + '"'


def load_config(path):
    config = json.loads(path.read_text())
    example = json.loads((ROOT / "scripts/synopsys/config.example.json").read_text())
    if set(config) != set(example):
        raise ValueError("Config keys must match scripts/synopsys/config.example.json")
    for key in ("library_name", "operating_condition", "library_note", "target_db"):
        if not isinstance(config[key], str) or not config[key] or "REPLACE" in config[key].upper():
            raise ValueError(f"Set {key} to the actual library/corner information")
    if not isinstance(config["wire_load_model"], str):
        raise ValueError("wire_load_model must be a string")
    for key in ("library_time_unit_ns", "clock_period_ns", "clock_uncertainty_ns", "clock_transition_ns",
                "input_delay_ns", "output_delay_ns", "input_transition_ns", "output_load_library_units"):
        value = config[key]
        if type(value) not in (float, int) or not math.isfinite(value) or value < 0:
            raise ValueError(f"{key} must be a finite nonnegative number")
    if config["library_time_unit_ns"] <= 0:
        raise ValueError("library_time_unit_ns must be positive")
    validate_clock(config["clock_period_ns"])
    db = Path(config["target_db"]).expanduser()
    if not db.is_absolute() or not db.is_file():
        raise ValueError("target_db must be an existing absolute .db file path")
    if db.suffix != ".db" or db.stem.lower() in {"gtech", "pgtech", "standard", "dw_foundation"}:
        raise ValueError("target_db must be a technology cell library, not a generic synthesis library")
    config["target_db"] = str(db.resolve())
    return config


def validate_clock(clock):
    # Both half cycles must be representable in the bench's 1 ps time precision.
    if (not math.isfinite(clock) or clock < 0.01 or
            not math.isclose(clock * 500, round(clock * 500), abs_tol=1e-8, rel_tol=0)):
        raise ValueError("clock period must be >= 0.01 ns and an exact multiple of 0.002 ns")


def check_benchmark(folder, size, count, clock):
    if not (folder / "benchmark.pass").is_file():
        raise ValueError(f"Simulation did not finish successfully: {folder}")
    with (folder / "cycles.csv").open() as stream:
        rows = list(csv.DictReader(stream))
    with (folder / "window.csv").open() as stream:
        windows = list(csv.DictReader(stream))
    if len(rows) != count + 10 or len(windows) != 1:
        raise ValueError("Incomplete benchmark CSV")
    measured = []
    for index, row in enumerate(rows):
        cycles = int(row["compute_cycles"])
        compute_ns = float(row["compute_ns"])
        transaction_ns = float(row["transaction_ns"])
        if (int(row["case_index"]) != index or int(row["measured"]) != int(index >= 10) or
                int(row["outputs_checked"]) != size**2 or cycles <= 0 or
                not math.isclose(compute_ns, cycles * clock, abs_tol=0.002) or
                not math.isclose(transaction_ns, (cycles + 2 * size**2 + 1) * clock, abs_tol=0.002)):
            raise ValueError(f"Invalid benchmark row {index}")
        if index >= 10:
            measured.append(row)
    window = windows[0]
    duration = float(window["duration_ns"])
    if (int(window["measured_pairs"]) != count or
            not math.isclose(float(window["clock_period_ns"]), clock, abs_tol=0.0001) or
            not math.isclose(sum(float(row["transaction_ns"]) for row in measured), duration, abs_tol=0.002)):
        raise ValueError("Activity window does not equal the sum of measured transactions")
    return {"measured_pairs": count, "duration_ns": duration,
            "compute_cycles": sorted({int(row["compute_cycles"]) for row in measured}),
            "mean_transaction_ns": duration / count,
            "pairs_per_second_at_requested_clock": count * 1e9 / duration}


def check_saif(path, expected_ns):
    # Metadata only: leave detailed signal coverage to report_saif in DC.
    text = path.read_text(errors="replace")
    scale = re.search(r"\(TIMESCALE\s+([\d.eE+-]+)\s+(s|ms|us|ns|ps|fs)\s*\)", text)
    duration = re.search(r"\(DURATION\s+([\d.eE+-]+)\s*\)", text)
    if not scale or not duration or not re.search(r'\(INSTANCE\s+"?dut"?(?:\s|\))', text):
        raise ValueError("SAIF is missing timescale, duration, or dut scope")
    units = {"s": 1e9, "ms": 1e6, "us": 1e3, "ns": 1, "ps": 1e-3, "fs": 1e-6}
    measured_ns = float(scale[1]) * units[scale[2]] * float(duration[1])
    if not math.isclose(measured_ns, expected_ns, rel_tol=1e-8, abs_tol=0.002):
        raise ValueError(f"SAIF window {measured_ns} ns != benchmark window {expected_ns} ns")
    if not re.search(r"\(TC\s+[1-9]\d*\s*\)", text):
        raise ValueError("SAIF contains no nonzero toggle counts")


def run_command(command, folder, name, commands):
    commands.append({"cwd": str(folder), "argv": command, "log": name})
    preview = " ".join(shlex.quote(word) for word in command[:4])
    print(f"{folder.name}: {preview} ... -> {name}", flush=True)
    with (folder / name).open("w") as log:
        result = subprocess.run(command, cwd=folder, stdin=subprocess.DEVNULL,
                                stdout=log, stderr=subprocess.STDOUT, check=False)
    output = (folder / name).read_text(errors="replace")
    # Some Synopsys shells/wrappers return zero despite command errors.
    if result.returncode or re.search(r"(?m)^\s*(Error[:\-]|Fatal:|FAIL PPA:)", output):
        raise RuntimeError(f"Command failed; inspect {folder / name}")


def check_dc_reports(folder):
    # redirect puts vendor errors in the report, outside the main dc.log.
    reports = ("library", "units", "area", "timing", "constraints", "timing_checks",
               "qor", "references", "design", "activity", "activity_missing", "power",
               "power_hierarchy")
    if not (folder / "reports.complete").is_file():
        raise ValueError(f"DC did not complete its reports in {folder}")
    for name in reports:
        report = folder / f"{name}.rpt"
        content = report.read_text(errors="replace") if report.is_file() else ""
        if not content.strip() or re.search(r"(?m)^\s*(Error[:\-]|Fatal:|FAIL PPA:)", content):
            raise ValueError(f"Missing or failed DC report: {report}")
    for name in ("mapped.ddc", "mapped.sdc", "mapped.v", "saifmap.primepower.tcl"):
        artifact = folder / name
        if not artifact.is_file() or not artifact.stat().st_size:
            raise ValueError(f"Missing mapped artifact: {artifact}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flow", choices=("local", "activity", "ppa"), default="local")
    parser.add_argument("--sizes", type=int, choices=(8, 16, 32), nargs="+", default=[32])
    parser.add_argument("--seed", type=int, default=20261008)
    parser.add_argument("--random-count", type=int, default=100)
    parser.add_argument("--clock-ns", type=float, help="local/activity only; ppa takes clock from config")
    parser.add_argument("--config", type=Path, help="required for ppa")
    parser.add_argument("--tool-prefix", default="", help='e.g. "synopsys-run" on CAE (argv, not shell code)')
    parser.add_argument("--out", type=Path, help="new run directory; existing paths are never overwritten")
    args = parser.parse_args()
    if args.random_count <= 0 or len(set(args.sizes)) != len(args.sizes):
        parser.error("need a positive random count and distinct sizes")
    if args.flow == "ppa" and (not args.config or args.clock_ns is not None):
        parser.error("ppa requires --config; set the clock in that file")
    if args.flow != "ppa" and args.config:
        parser.error("--config applies only to ppa")

    config = load_config(args.config) if args.config else None
    clock = config["clock_period_ns"] if config else (args.clock_ns if args.clock_ns is not None else 10.0)
    validate_clock(clock)
    prefix = shlex.split(args.tool_prefix)
    required = ["iverilog", "vvp"] if args.flow == "local" else ["vcs"]
    if args.flow == "ppa":
        required.append("dc_shell")
    # Container binaries may not be visible outside; actual calls must still pass.
    for tool in ([prefix[0]] if prefix else required):
        if not shutil.which(tool):
            raise ValueError(f"Tool not found: {tool}")
    out = (args.out or ROOT / "build/ppa" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")).resolve()
    out.mkdir(parents=True, exist_ok=False)
    source_paths = sorted({ROOT / "rtl" / path for arch in ARCHITECTURES.values() for path in COMMON + arch})
    support_paths = [ROOT / path for path in ("tb/tb_gemm_ppa.sv", "scripts/run_gemm_ppa.py",
                    "scripts/synopsys/dc_ppa.tcl", "tests/gen_gemm_vectors.py", "tests/gen_vectors.py")]
    hashes = {str(path.relative_to(ROOT)): digest(path) for path in source_paths + support_paths}
    metadata = {"format": "gemm-ppa-v1", "status": "running", "flow": args.flow,
                "started_utc": datetime.now(timezone.utc).isoformat(), "sizes": args.sizes,
                "seed": args.seed, "random_count": args.random_count, "warmup_count": 10,
                "clock_period_ns": clock, "config": config, "source_sha256": hashes,
                "commands": [], "benchmarks": [],
                "scope": "RTL simulation; PPA reports are pre-layout estimates requiring review"}
    if config:
        metadata["library_sha256"] = digest(Path(config["target_db"]))
    write_json(out / "run.json", metadata)
    try:
        # Serial runs avoid contention and excessive licensing on shared machines.
        for size in args.sizes:
            vectors = render_vectors(args.seed, args.random_count, size)
            for architecture, rtl in ARCHITECTURES.items():
                folder = out / str(size) / architecture
                sim = folder / "sim"
                sim.mkdir(parents=True)
                for filename, content in vectors.items():
                    (sim / filename).write_text(content, encoding="ascii")
                files = [str(ROOT / "rtl" / path) for path in COMMON + rtl]
                bench = str(ROOT / "tb/tb_gemm_ppa.sv")
                if args.flow == "local":
                    command = ["iverilog", "-g2012", "-Wall", "-I.", "-s", "tb_gemm_ppa",
                               f"-Ptb_gemm_ppa.MatrixDim={size}", f"-Ptb_gemm_ppa.ClockPeriodNs={clock}"]
                    if architecture == "conventional":
                        command += ["-DPPA_CONVENTIONAL"]
                    command += ["-o", "sim.vvp"] + files + [bench]
                    execute = ["vvp", "sim.vvp"]
                else:
                    command = ["vcs", "-full64", "-sverilog", "-debug_access+pp", "-top", "tb_gemm_ppa", "+incdir+.",
                               "+define+PPA_SAIF", f"-pvalue+tb_gemm_ppa.MatrixDim={size}",
                               f"-pvalue+tb_gemm_ppa.ClockPeriodNs={clock}"]
                    if architecture == "conventional":
                        command += ["+define+PPA_CONVENTIONAL"]
                    command += files + [bench, "-o", "simv"]
                    # CAE Y-2026.03 requires -lca for native SV/memory SAIF.
                    execute = ["./simv", "-no_save", "-lca"]
                run_command(prefix + command, sim, "compile.log", metadata["commands"])
                run_command(prefix + execute, sim, "simulation.log", metadata["commands"])
                stats = check_benchmark(sim, size, args.random_count, clock)
                stats.update({"matrix_dim": size, "architecture": architecture,
                              "fixture_sha256": {name: digest(sim / name) for name in vectors}})
                if args.flow != "local":
                    check_saif(sim / "activity.saif", stats["duration_ns"])
                    stats["saif_sha256"] = digest(sim / "activity.saif")
                metadata["benchmarks"].append(stats)
                write_json(out / "run.json", metadata)
                if args.flow == "ppa":
                    dc = folder / "dc"
                    dc.mkdir()
                    values = dict(config, top=f"{architecture}_gemm", matrix_dim=size)
                    tcl = "".join(f"set {key} {tcl_word(value)}\n" for key, value in values.items())
                    tcl += "set rtl_sources [list " + " ".join(tcl_word(path) for path in files) + "]\n"
                    (dc / "run_config.tcl").write_text(tcl)
                    run_command(prefix + ["dc_shell", "-f", str(ROOT / "scripts/synopsys/dc_ppa.tcl")],
                                dc, "dc.log", metadata["commands"])
                    check_dc_reports(dc)
        # Detect edits while a long run was using the shared source tree.
        if any(digest(ROOT / name) != sha for name, sha in hashes.items()):
            raise ValueError("Source files changed during the run; rerun from a stable checkout")
        if config and digest(Path(config["target_db"])) != metadata["library_sha256"]:
            raise ValueError("Library changed during the run")
        metadata["status"] = "reports_need_review" if args.flow == "ppa" else "passed"
    except Exception as error:
        metadata["status"] = "failed"
        metadata["error"] = str(error)
        raise
    finally:
        write_json(out / "run.json", metadata)
    print(f"{metadata['status']}: {out}")
    if args.flow == "ppa":
        print("Review library/units, timing constraints, SAIF coverage and power warnings before comparing PPA.")
    else:
        print("No area, achieved frequency, or power result is claimed by this flow.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, OSError) as error:
        sys.exit(f"FAIL: {error}")

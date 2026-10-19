#!/usr/bin/env python3
"""Validate exported Synopsys reports, summarize seed repeats, and plot PPA.

Run with the Python environment in scripts/requirements-ppa-plots.txt.
Inputs are seed directories containing run.json and size/architecture reports.
64x64 values are conditional extrapolations, never synthesized measurements.
"""

import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import statistics

from run_gemm_ppa import check_benchmark

ARCHITECTURES = ("systolic", "conventional")
SIZES = (8, 16, 32)
NUMBER = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(pattern, text):
    match = re.search(pattern + r"\s*(" + NUMBER + r")", text)
    require(match is not None, f"Missing report field: {pattern}")
    value = float(match[1])
    require(math.isfinite(value), f"Non-finite report field: {pattern}")
    return value


def power_mw(label, text):
    match = re.search(re.escape(label) + r"\s*=\s*(" + NUMBER + r")\s*(pW|nW|uW|mW|W)\b", text)
    require(match is not None, f"Missing power or explicit unit: {label}")
    value = float(match[1]) * {"pW": 1e-9, "nW": 1e-6, "uW": 1e-3, "mW": 1, "W": 1000}[match[2]]
    require(math.isfinite(value), f"Non-finite power: {label}")
    return value


def scheduled_cycles(size, architecture):
    require(size > 0 and size % 2 == 0, "Expected a positive even matrix dimension")
    require(architecture in ARCHITECTURES, "Unknown architecture")
    return (size // 2) ** 2 * (3 * size + (10 if architecture == "systolic" else 8))


def read_area_units_review(path, metadata):
    if path is None:
        return None
    review = json.loads(path.read_text())
    require(review["status"] == "verified" and review["unit"] == "um^2"
            and review["scale_from_report"] == 1, "Unsupported area-unit review")
    require(review["library_sha256"] == metadata["library_sha256"]
            and review["library_name"] == metadata["config"]["library_name"],
            "Area-unit evidence belongs to a different library")
    return review


def parse_reports(dc):
    require((dc / "reports.complete").is_file(), f"Incomplete synthesis: {dc}")
    reports = {p.stem: p.read_text() for p in dc.glob("*.rpt")}
    for name in ("area", "qor", "power", "activity", "activity_missing", "constraints", "timing_checks"):
        require(name in reports, f"Missing {dc}/{name}.rpt")
    for name, content in reports.items():
        require(not re.search(r"(?m)^\s*(Error[:\-]|Fatal:)", content), f"Vendor error in {dc}/{name}.rpt")
    require("This design has no violated constraints." in reports["constraints"], f"Constraints failed: {dc}")
    require("Warning:" not in reports["timing_checks"], f"Timing setup needs review: {dc}")
    require("Warning:" not in reports["power"], f"Power warning needs review: {dc}")
    require("-analysis_effort high" in reports["power"], f"Expected high-effort primary power report: {dc}")
    missing = reports["activity_missing"]
    for label in ("ports", "sequential cells", "three-state cells"):
        require(re.search(r"(?m)^\s*0 " + label + r"\s*$", missing), f"Unannotated {label}: {dc}")
    for label in ("Ports", "Seq Cells"):
        require(re.search(label + r"\s+\d+\(100\.00%\)", reports["activity"]), f"Activity coverage failed: {dc}")
    qor = reports["qor"]
    slack = number(r"Critical Path Slack:", qor)
    require(slack >= 0, f"Clock target not met: {dc}")
    for label in ("No. of Violating Paths", "No. of Hold Violations", "Nets With Violations"):
        require(number(re.escape(label) + ":", qor) == 0, f"{label}: {dc}")
    dynamic = power_mw("Total Dynamic Power", reports["power"])
    leakage = power_mw("Cell Leakage Power", reports["power"])
    internal = power_mw("Cell Internal Power", reports["power"])
    switching = power_mw("Net Switching Power", reports["power"])
    require(dynamic > 0 and leakage > 0, f"Missing or zero power characterization: {dc}")
    require(abs(dynamic - internal - switching) <= 0.001,
            f"Inconsistent dynamic power components: {dc}")
    return {
        "cell_area_library_units": number("Total cell area:", reports["area"]),
        "memory_area_library_units": number(r"(?m)^u_memory\s+", reports["area"]),
        "leaf_cells": int(number("Leaf Cell Count:", qor)),
        "sequential_cells": int(number("Sequential Cell Count:", qor)),
        "slack_ns": slack,
        "internal_power_mw": internal,
        "net_switching_power_mw": switching,
        "dynamic_power_mw": dynamic,
        "leakage_power_mw": leakage,
        "total_power_mw": dynamic + leakage,
    }


def collect(runs):
    rows, metadata, warnings = [], [], []
    sdc_constraints = {}
    normalized_constraints = None
    for folder in runs:
        meta = json.loads((folder / "run.json").read_text())
        require(meta["status"] == "reports_need_review" and meta["flow"] == "ppa", f"Unfinished PPA run: {folder}")
        require(sorted(meta["sizes"]) == list(SIZES), "Need complete 8/16/32 sweep")
        require(meta["random_count"] == 100 and meta["warmup_count"] == 10, "Expected 100 random + 10 warmup pairs")
        if metadata:
            for key in ("source_sha256", "library_sha256", "config", "clock_period_ns"):
                require(meta[key] == metadata[0][key], f"Inconsistent {key}")
        metadata.append(meta)
        require(len(meta["benchmarks"]) == 6, f"Incomplete benchmark metadata: {folder}")
        benchmarks = {(b["matrix_dim"], b["architecture"]): b for b in meta["benchmarks"]}
        require(len(benchmarks) == 6, f"Duplicate benchmark metadata: {folder}")
        for size in SIZES:
            require(benchmarks[size, "systolic"]["fixture_sha256"] == benchmarks[size, "conventional"]["fixture_sha256"], "Architectures used different fixtures")
            for architecture in ARCHITECTURES:
                base = folder / str(size) / architecture
                stats = check_benchmark(base / "sim", size, meta["random_count"], meta["clock_period_ns"])
                require(stats["compute_cycles"] == [scheduled_cycles(size, architecture)], f"Unexpected cycle schedule: {base}")
                for key, value in stats.items():
                    require(value == benchmarks[size, architecture][key], f"Metadata differs from CSV: {base}/{key}")
                saif = json.loads((base / "sim" / "activity_review.json").read_text())
                require(saif["sha256"] == benchmarks[size, architecture]["saif_sha256"], "SAIF hash mismatch")
                require(saif["nonzero_tx_records"] == 0, f"Unknown state activity: {base}")
                require(saif["fixture_sha256"] == benchmarks[size, architecture]["fixture_sha256"], "Fixture export hash mismatch")
                commands = tuple(line.strip() for line in (base / "dc" / "mapped.sdc").read_text().splitlines()
                                 if line.startswith(("create_clock", "set_clock_", "set_input_", "set_output_", "set_load", "set_operating_conditions", "set_wire_load")))
                require(commands, "Missing exported constraints")
                if size not in sdc_constraints:
                    sdc_constraints[size] = commands
                require(commands == sdc_constraints[size], f"Different same-size constraints: {base}")
                # Address buses grow with N; compare per-bus settings across sizes.
                normalized = set(re.sub(r"\[\d+\]", "[bit]", line) for line in commands)
                if normalized_constraints is None:
                    normalized_constraints = normalized
                require(normalized == normalized_constraints, f"Different per-bus constraints: {base}")
                metrics = parse_reports(base / "dc")
                transaction_us = stats["mean_transaction_ns"] / 1000
                rows.append({"seed": meta["seed"], "matrix_dim": size, "architecture": architecture,
                             "measured_pairs": meta["random_count"], "compute_cycles": stats["compute_cycles"][0],
                             "compute_us": stats["compute_cycles"][0] * meta["clock_period_ns"] / 1000,
                             "transaction_us": transaction_us, **metrics,
                             "transaction_energy_nj": metrics["total_power_mw"] * transaction_us})
                for file in [base / "dc" / "dc.log", *(base / "dc").glob("*.rpt")]:
                    require(not re.search(r"(?m)^\s*(Error[:\-]|Fatal:|FAIL PPA:)", file.read_text()), f"Vendor error: {file}")
                    require(not re.search(r"Warning:.*\(PWR-", file.read_text()), f"Power warning: {file}")
                    counts = Counter()
                    for line in file.read_text().splitlines():
                        if "Warning:" in line:
                            match = re.search(r"\(([^()]*)\)\.?$", line)
                            counts[match[1] if match else line.strip()] += 1
                    if counts:
                        warnings.append({"seed": meta["seed"], "matrix_dim": size, "architecture": architecture,
                                         "file": file.name, "warning_counts": dict(counts)})
    require(len(metadata) >= 3 and len({m["seed"] for m in metadata}) == len(metadata), "Need at least three distinct seeds")
    require(all(not m.get("synthesis_mode") for m in metadata), "This study requires the same fresh synthesis flow for every seed")
    for size in SIZES:
        for architecture in ARCHITECTURES:
            subset = [r for r in rows if r["matrix_dim"] == size and r["architecture"] == architecture]
            for key in ("cell_area_library_units", "leaf_cells", "sequential_cells", "slack_ns", "compute_cycles"):
                require(len({r[key] for r in subset}) == 1, f"Seed-dependent synthesis/schedule: {size}/{architecture}/{key}")
    return rows, metadata, warnings


def summarize(rows, clock_ns):
    import numpy as np
    groups, predictions = [], []
    metrics = ("compute_us", "cell_area_library_units", "total_power_mw", "internal_power_mw",
               "net_switching_power_mw", "dynamic_power_mw", "leakage_power_mw", "transaction_energy_nj")
    for architecture in ARCHITECTURES:
        by_size = []
        for size in SIZES:
            subset = [r for r in rows if r["matrix_dim"] == size and r["architecture"] == architecture]
            group = {"architecture": architecture, "matrix_dim": size, "seeds": len(subset)}
            for key in metrics:
                values = [r[key] for r in subset]
                group[key] = statistics.mean(values)
                group[key + "_min"] = min(values)
                group[key + "_max"] = max(values)
            groups.append(group)
            by_size.append(group)
        prediction = {"architecture": architecture, "matrix_dim": 64,
                      "compute_cycles": scheduled_cycles(64, architecture),
                      "compute_us": scheduled_cycles(64, architecture) * clock_ns / 1000,
                      "compute_model": "N^2/4 * (3N + overhead), overhead=10 systolic or 8 conventional; unchanged schedule and clock assumed"}
        for key in ("cell_area_library_units", "total_power_mw"):
            x, y = np.array(SIZES, dtype=float), np.array([g[key] for g in by_size])
            # Two parameters and three measured sizes. N^2 represents the fixed-width memories.
            slope, intercept = np.polyfit(x ** 2, y, 1)
            estimate = slope * 64 ** 2 + intercept
            # A local N^2 slope and a log-log power law show model-choice sensitivity.
            local = y[-1] + (y[-1] - y[-2]) / (x[-1] ** 2 - x[-2] ** 2) * (64 ** 2 - x[-1] ** 2)
            exponent, log_scale = np.polyfit(np.log(x), np.log(y), 1)
            power_law = float(np.exp(log_scale) * 64 ** exponent)
            prediction[key] = float(estimate)
            prediction[key + "_models"] = {
                "quadratic_storage_fit": float(estimate), "last_two_sizes_quadratic_fit": float(local),
                "power_law_fit": power_law, "sensitivity_min": float(min(estimate, local, power_law)),
                "sensitivity_max": float(max(estimate, local, power_law)),
                "quadratic_coefficient": float(slope), "intercept": float(intercept),
                "max_measured_relative_residual": float(max(abs((slope * x ** 2 + intercept - y) / y))),
                "power_law_exponent": float(exponent),
                "warning": "Model-choice sensitivity only; not a confidence interval or a physical implementation bound."}
        predictions.append(prediction)
    return groups, predictions


def plots(groups, predictions, out, config, area_unit="library units"):
    """Render report figures using the architecture diagrams' visual language."""
    os.environ.setdefault("MPLCONFIGDIR", str(out / ".matplotlib"))
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np
    from matplotlib import font_manager
    from matplotlib.lines import Line2D
    from matplotlib.patches import FancyBboxPatch, Rectangle
    from matplotlib.ticker import MaxNLocator, StrMethodFormatter
    from matplotlib.backends.backend_pdf import PdfPages

    # These colors and the 20 px background grid match docs/*-matmul.svg
    # and docs/systolic-array.svg. Bars always share a zero-based linear axis.
    background, ink, muted = "#111111", "#F5F5F5", "#D3D3D3"
    purple, border = "#E6A0F5", "#A6B5C8"
    colors = {"systolic": "#8ABEFF", "conventional": "#65C4BC"}
    fills = {"systolic": "#153747", "conventional": "#193F3C"}
    names = {"systolic": "Systolic", "conventional": "Conventional"}
    available_fonts = {f.name for f in font_manager.fontManager.ttflist}
    font = "Helvetica" if "Helvetica" in available_fonts else "DejaVu Sans"
    plt.rcParams.update({"font.family": font, "font.size": 12,
                         "text.color": ink, "axes.labelcolor": muted,
                         "xtick.color": ink, "ytick.color": muted,
                         "svg.fonttype": "none", "pdf.fonttype": 42,
                         "savefig.facecolor": background})
    frequency_mhz = 1000 / config["clock_period_ns"]
    library_label = ("SAED32 RVT · 1.05 V · 25 °C"
                     if config["library_name"] == "saed32rvt_tt1p05v25c"
                     and config["operating_condition"] == "tt1p05v25c"
                     else f"{config['library_name']} · {config['operating_condition']}")
    qualified_area = area_unit == "µm²"
    specs = (
        ("compute_us", "compute-time", "COMPUTE TIME", "Time per pair (µs)", "µs", 1, 2),
        ("cell_area_library_units", "cell-area", "MAPPED CELL AREA",
         "Cell area (mm²)" if qualified_area else "Cell area (thousand library units)",
         "mm²" if qualified_area else "k units", 1e6 if qualified_area else 1e3, 4 if qualified_area else 2),
        ("total_power_mw", "average-power", "AVERAGE TOTAL POWER", "Power (mW)", "mW", 1, 3),
    )

    def panel(fig, box, face, edge, dashed=False):
        patch = FancyBboxPatch(box[:2], box[2], box[3], transform=fig.transFigure,
                              boxstyle="round,pad=0.004,rounding_size=0.018",
                              facecolor=face, edgecolor=edge, linewidth=1.5,
                              linestyle=(0, (6, 4)) if dashed else "solid", zorder=1)
        fig.add_artist(patch)

    with PdfPages(out / "ppa-graphs.pdf") as pdf:
        for key, filename, title, ylabel, unit, divisor, decimals in specs:
            fig = plt.figure(figsize=(12.8, 7.36), facecolor=background)
            for column in range(81):
                fig.add_artist(Line2D([column / 80] * 2, [0, 1],
                                     transform=fig.transFigure, zorder=0,
                                     color="#373737" if column % 5 == 0 else "#222222", lw=0.45))
            for row in range(47):
                fig.add_artist(Line2D([0, 1], [row / 46] * 2,
                                     transform=fig.transFigure, zorder=0,
                                     color="#373737" if row % 5 == 0 else "#222222", lw=0.45))
            fig.text(.5, .932, title, ha="center", fontsize=24, weight="bold")
            fig.text(.5, .886, "Systolic array vs. conventional matrix multiplier",
                     ha="center", fontsize=13, color=muted)
            panel(fig, (.035, .808, .93, .046), background, "#6B7280")
            for x, text in ((.19, "4 MACs in each core"), (.46, f"{frequency_mhz:g} MHz"),
                            (.76, library_label)):
                fig.text(x, .83, text, ha="center", va="center", fontsize=12, weight="bold")

            panel(fig, (.035, .197, .62, .58), "#191919", border)
            panel(fig, (.685, .197, .28, .58), "#302536", purple, dashed=True)
            fig.text(.055, .739, "MEASURED SIZES", fontsize=13, weight="bold", color=border)
            for x, architecture in ((.33, "systolic"), (.472, "conventional")):
                fig.add_artist(Rectangle((x, .729), .012, .016, transform=fig.transFigure,
                                         facecolor=fills[architecture], edgecolor=colors[architecture],
                                         linewidth=1.5, zorder=3))
                fig.text(x + .019, .737, names[architecture], fontsize=11.5, va="center")

            ax = fig.add_axes([.1, .317, .515, .337], facecolor="#191919", zorder=2)
            maxima = []
            for index, architecture in enumerate(ARCHITECTURES):
                subset = [next(g for g in groups if g["architecture"] == architecture
                               and g["matrix_dim"] == size) for size in SIZES]
                values = np.array([g[key] / divisor for g in subset])
                positions = np.arange(len(SIZES)) + (-.18 if index == 0 else .18)
                ax.bar(positions, values, width=.29, color=fills[architecture],
                       edgecolor=colors[architecture], linewidth=1.6, zorder=3)
                if key == "total_power_mw":
                    lower = [g[key + "_min"] / divisor for g in subset]
                    upper = [g[key + "_max"] / divisor for g in subset]
                    ax.errorbar(positions, values, yerr=[values-lower, upper-values],
                                fmt="none", color=colors[architecture], capsize=4, lw=1, zorder=4)
                for x, value in zip(positions, values):
                    ax.annotate(f"{value:,.{decimals}f}", (x, value), xytext=(0, 8),
                                textcoords="offset points", ha="center", va="bottom",
                                fontsize=11, color=colors[architecture], weight="bold")
                maxima.extend(values)
            ax.set_ylim(0, max(maxima) * 1.23)
            ax.set_xlim(-.65, 2.65)
            ax.set_xticks(range(3), [f"{n}×{n}" for n in SIZES], fontsize=13, weight="bold")
            ax.set_ylabel(ylabel, labelpad=12, fontsize=11)
            ax.yaxis.set_major_locator(MaxNLocator(nbins=4, min_n_ticks=3))
            ax.yaxis.set_major_formatter(StrMethodFormatter("{x:g}"))
            ax.tick_params(axis="both", length=0, pad=9)
            ax.grid(axis="y", color="#373737", linewidth=.65, zorder=0)
            ax.axhline(0, color=border, lw=1)
            for spine in ax.spines.values():
                spine.set_visible(False)

            end_values = {a: next(g[key] for g in groups if g["architecture"] == a
                                 and g["matrix_dim"] == 32) for a in ARCHITECTURES}
            reduction = 100 * (1 - end_values["conventional"] / end_values["systolic"])
            precision = 1 if key == "compute_us" else 3
            finding = (f"At 32×32: conventional uses {reduction:.{precision}f}% less time."
                       if key == "compute_us" else
                       f"Nearly tied at 32×32: {reduction:.{precision}f}% {'area' if key == 'cell_area_library_units' else 'power'} gap.")
            fig.text(.345, .23, finding, ha="center", fontsize=12, color="#FF969E")

            fig.text(.705, .739, "64×64 PROJECTION", fontsize=13, weight="bold", color=purple)
            fig.text(.705, .696, "Four MACs; larger matrices", fontsize=11, color=muted)
            for architecture, y in (("systolic", .62), ("conventional", .438)):
                pred = next(p for p in predictions if p["architecture"] == architecture)
                fig.text(.708, y, names[architecture].upper(), fontsize=11, weight="bold",
                         color=colors[architecture])
                fig.text(.708, y - .052, f"{pred[key] / divisor:,.{decimals}f} {unit}",
                         fontsize=21, weight="bold", color=ink)
                if key != "compute_us":
                    model = pred[key + "_models"]
                    lo, hi = model["sensitivity_min"] / divisor, model["sensitivity_max"] / divisor
                    fig.text(.708, y - .088, f"Model range: {lo:,.2f}-{hi:,.2f} {unit}",
                             fontsize=10.5, color=muted)
            model_note = (f"Schedule formula at {frequency_mhz:g} MHz" if key == "compute_us"
                          else "Main estimate: aN² + b fit")
            fig.text(.708, .273, model_note, fontsize=11, color=muted)
            fig.text(.708, .23, "Not simulated or synthesized", fontsize=10.5, color=purple)

            notes = {
                "compute_us": ("Accepted start through done, including internal tile loading; external input load/readback excluded.",
                               "64×64 assumes extended size support, the same schedule, and successful timing closure."),
                "cell_area_library_units": ("Mapped standard-cell area, including register-based storage; placement and routing excluded.",
                                             "Prediction ranges compare three models; they are not confidence intervals."),
                "total_power_mw": (f"Dynamic + leakage over load/compute/readback. Mean of {groups[0]['seeds']} seeds × 100 random pairs.",
                                    "Bar whiskers: seed min-max (very small). Prediction ranges: model choice, not confidence intervals."),
            }
            for y, note in zip((.125, .087), notes[key]):
                fig.text(.04, y, note, fontsize=10.5, color=muted)
            fig.text(.04, .035, "PRE-LAYOUT ASIC COMPARISON", fontsize=9.5, color=border)
            fig.text(.96, .035, "INT8 INPUTS  /  INT32 RESULTS", fontsize=9.5, color=border, ha="right")
            fig.savefig(out / (filename + ".svg"), facecolor=background)
            fig.savefig(out / (filename + ".png"), dpi=125, facecolor=background)
            pdf.savefig(fig, facecolor=background)
            plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs="+", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--area-units-review", type=Path,
                        help="Verified library-specific evidence for labeling raw report area in µm²")
    args = parser.parse_args()
    rows, metadata, warnings = collect(args.runs)
    area_review = read_area_units_review(args.area_units_review, metadata[0])
    groups, predictions = summarize(rows, metadata[0]["clock_period_ns"])
    args.out.mkdir(parents=True, exist_ok=False)
    for filename, records in (("measurements.csv", rows), ("means.csv", groups)):
        with (args.out / filename).open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(records[0]))
            writer.writeheader()
            writer.writerows(records)
    result = {"generated_utc": datetime.now(timezone.utc).isoformat(), "seeds": [m["seed"] for m in metadata],
              "synthesis_modes": {m["seed"]: m.get("synthesis_mode", "fresh_compile") for m in metadata},
              "config": metadata[0]["config"], "source_sha256": metadata[0]["source_sha256"],
              "library_sha256": metadata[0]["library_sha256"], "measurements": rows, "means": groups,
              "area_unit": "um^2" if area_review else "library units", "area_unit_review": area_review,
              "predictions_64": predictions, "report_warnings_for_review": warnings,
              "input_run_sha256": {str(p): hashlib.sha256((p / "run.json").read_bytes()).hexdigest() for p in args.runs},
              "scope": "Pre-layout estimates. Automated numerical checks passed; vendor warnings still require human review. No physical signoff or gate-level equivalence claimed."}
    (args.out / "results.json").write_text(json.dumps(result, indent=2) + "\n")
    plots(groups, predictions, args.out, metadata[0]["config"], "µm²" if area_review else "library units")
    print(f"Validated {len(rows)} combinations; wrote graphs and data to {args.out}")


if __name__ == "__main__":
    main()

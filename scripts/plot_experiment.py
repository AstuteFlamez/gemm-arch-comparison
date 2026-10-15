#!/usr/bin/env python3
"""Generate the Markdown experiment charts from recorded PPA results.

Uses scripts/requirements-ppa-plots.txt; no Synopsys tools or new runs needed.
Run from the repository root:
    build/ppa-plot-venv/bin/python scripts/plot_experiment.py
"""

import argparse
import json
import math
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SIZES = (8, 16, 32)
ARCHITECTURES = ("systolic", "conventional")
COLORS = {"systolic": "#F28E2B", "conventional": "#4C78A8"}
HATCHES = {8: "///", 16: "|||", 32: "---"}


def render(results_path, output_dir):
    results = json.loads(results_path.read_text())
    if results["area_unit"] != "um^2":
        raise ValueError("Area must be verified in µm² before converting to mm².")
    means = results["means"]
    groups = {(row["matrix_dim"], row["architecture"]): row for row in means}
    if len(groups) != len(means):
        raise ValueError("Duplicate matrix-size/architecture means in results.")
    clock_ns = results["config"]["clock_period_ns"]
    if not math.isfinite(clock_ns) or clock_ns <= 0:
        raise ValueError("Expected a positive, finite clock period.")
    frequency_mhz = 1000 / clock_ns
    specs = (
        ("compute_us", "compute-time", f"Compute time at {frequency_mhz:g} MHz",
         "Time per pair (µs)", 1, 2),
        ("cell_area_library_units", "cell-area", "Mapped standard-cell area",
         "Cell area (mm²)", 1e6, 4),
        ("total_power_mw", "average-power", "Estimated average total power",
         "Power (mW)", 1, 3),
    )
    # Validate all inputs before writing any chart.
    seeds = set()
    for size in SIZES:
        for architecture in ARCHITECTURES:
            row = groups[size, architecture]
            seeds.add(row["seeds"])
            for field, *_ in specs:
                if not math.isfinite(row[field]) or row[field] < 0:
                    raise ValueError(f"Invalid {field} for {size}/{architecture}.")
    if len(seeds) != 1 or next(iter(seeds)) <= 0:
        raise ValueError("Expected the same positive seed count for each mean.")
    seed_count = next(iter(seeds))

    # Keep the font cache in the ignored build directory, outside the figures.
    os.environ.setdefault("MPLCONFIGDIR", str(ROOT / "build" / ".matplotlib"))
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Patch
    from matplotlib.ticker import MaxNLocator, StrMethodFormatter

    output_dir.mkdir(parents=True, exist_ok=True)
    ink, muted = "#263445", "#526171"
    style = {
        "font.family": "DejaVu Sans",
        "font.size": 12,
        "text.color": ink,
        "axes.labelcolor": ink,
        "xtick.color": ink,
        "ytick.color": muted,
        "hatch.linewidth": 0.8,
        "savefig.facecolor": "white",
    }
    with plt.rc_context(style):
        for field, filename, title, ylabel, divisor, decimals in specs:
            fig = plt.figure(figsize=(9.6, 5.8), facecolor="white")
            fig.text(.11, .955, title, fontsize=19, weight="bold", va="top")
            fig.text(.11, .9, f"Mean of {seed_count} seeds · {frequency_mhz:g} MHz",
                     fontsize=11, color=muted, va="top")

            architecture_key = [
                Patch(facecolor=COLORS[architecture], edgecolor=ink,
                      linewidth=.6, label=architecture.title())
                for architecture in ARCHITECTURES
            ]
            size_key = [
                Patch(facecolor="#F3F5F7", edgecolor=ink, linewidth=.6,
                      hatch=HATCHES[size], label=f"{size}×{size}")
                for size in SIZES
            ]
            fig.legend(handles=architecture_key, title="Architecture · color",
                       loc="upper left", bbox_to_anchor=(.1, .853), ncol=2,
                       frameon=False, fontsize=10.5, title_fontsize=10.5,
                       handlelength=1.8, handleheight=1.3, columnspacing=1.3)
            fig.legend(handles=size_key, title="Matrix size · stripes",
                       loc="upper left", bbox_to_anchor=(.56, .853), ncol=3,
                       frameon=False, fontsize=10.5, title_fontsize=10.5,
                       handlelength=1.8, handleheight=1.3, columnspacing=1.3)

            ax = fig.add_axes([.11, .15, .85, .55], facecolor="white")
            maximum = max(groups[size, architecture][field] / divisor
                          for size in SIZES for architecture in ARCHITECTURES)
            for index, size in enumerate(SIZES):
                for architecture, offset in zip(ARCHITECTURES, (-.17, .17)):
                    value = groups[size, architecture][field] / divisor
                    position = index + offset
                    ax.bar(position, value, width=.29, color=COLORS[architecture],
                           edgecolor=ink, linewidth=.65, hatch=HATCHES[size], zorder=3)
                    ax.annotate(f"{value:.{decimals}f}", (position, value),
                                xytext=(0, 6), textcoords="offset points",
                                ha="center", va="bottom", fontsize=10.5, color=ink)

            ax.set_xlim(-.6, len(SIZES) - .4)
            ax.set_ylim(0, maximum * 1.18 if maximum else 1)
            ax.set_xticks(range(len(SIZES)), [f"{size}×{size}" for size in SIZES],
                          fontsize=13)
            ax.set_xlabel("Matrix size", labelpad=10)
            ax.set_ylabel(ylabel, labelpad=10)
            ax.yaxis.set_major_locator(MaxNLocator(nbins=6, min_n_ticks=4))
            ax.yaxis.set_major_formatter(StrMethodFormatter("{x:g}"))
            ax.tick_params(axis="both", length=0, pad=8)
            ax.set_axisbelow(True)
            ax.grid(axis="y", color="#E4E9EE", linewidth=.8)
            for side in ("top", "right", "left"):
                ax.spines[side].set_visible(False)
            ax.spines["bottom"].set_color("#9AA7B4")

            destination = output_dir / f"{filename}.png"
            fig.savefig(destination, dpi=200)
            plt.close(fig)
            print(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=Path,
                        default=ROOT / "docs/results/saed32-2026-10-08/results.json")
    parser.add_argument("--out", type=Path, default=ROOT / "docs/figures")
    args = parser.parse_args()
    render(args.results, args.out)


if __name__ == "__main__":
    main()

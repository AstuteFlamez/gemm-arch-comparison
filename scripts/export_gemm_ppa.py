#!/usr/bin/env python3
"""Bundle generated PPA evidence without copying a licensed technology library.

Run on the synthesis host. The archive uses seed-<seed>/ directories, accepted
by plot_gemm_ppa.py after extraction. Raw SAIF, mapped netlists and DDCs stay on
that host; their hashes and activity checks are included in the export.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile


def sha256(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runs", nargs="+", type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.out, "x", zipfile.ZIP_DEFLATED) as archive:
        seeds = set()
        for run in args.runs:
            meta = json.loads((run / "run.json").read_text())
            if meta["status"] != "reports_need_review" or meta["flow"] != "ppa":
                raise ValueError(f"Run has not completed PPA: {run}")
            if meta["seed"] in seeds:
                raise ValueError("Duplicate seed")
            seeds.add(meta["seed"])
            prefix = Path(f"seed-{meta['seed']}")
            archive.write(run / "run.json", prefix / "run.json")
            if (run / "power-replay-verified.json").is_file():
                archive.write(run / "power-replay-verified.json", prefix / "power-replay-verified.json")
            for benchmark in meta["benchmarks"]:
                relative = Path(str(benchmark["matrix_dim"])) / benchmark["architecture"]
                base = run / relative
                sim, dc = base / "sim", base / "dc"
                if not (dc / "reports.complete").is_file():
                    raise ValueError(f"Reports incomplete: {dc}")
                saif = sim / "activity.saif"
                review = {"sha256": sha256(saif),
                          "nonzero_tx_records": sum(int(value) != 0 for value in re.findall(r"\(TX\s+(\d+)\s*\)", saif.read_text())),
                          "fixture_sha256": {name: sha256(sim / name) for name in benchmark["fixture_sha256"]},
                          "mapped_ddc_sha256": sha256(dc / "mapped.ddc"),
                          "mapped_verilog_sha256": sha256(dc / "mapped.v")}
                archive.writestr(str(prefix / relative / "sim/activity_review.json"), json.dumps(review, indent=2) + "\n")
                files = [sim / name for name in ("compile.log", "simulation.log", "benchmark.pass", "cycles.csv", "window.csv")]
                files += [p for p in dc.glob("*.rpt") if p.name != "library.rpt"]
                files += [dc / name for name in ("dc.log", "mapped.sdc", "run_config.tcl", "reports.complete")]
                for path in files:
                    archive.write(path, prefix / path.relative_to(run))
    print(f"Exported {len(seeds)} seeds to {args.out}; SHA256 {sha256(args.out)}")


if __name__ == "__main__":
    main()

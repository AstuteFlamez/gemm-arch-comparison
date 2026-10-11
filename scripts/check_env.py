#!/usr/bin/env python3
"""Inventory this shell without exposing license-server or credential values.

Finding an executable does not establish that it runs or can obtain a license.
The separate smoke targets exercise compilation and simulation.
"""

import argparse
import json
import os
import platform
from pathlib import Path
import shutil
import sys
from datetime import datetime, timezone


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("build/environment.json"))
    args = parser.parse_args()
    names = (
        "python3", "make", "git", "ssh", "vcs", "dc_shell", "pt_shell", "icc2_shell",
        "lc_shell", "synopsys-run", "vivado", "quartus_sh",
        "iverilog", "vvp", "verilator", "yosys", "gtkwave", "aws",
    )
    setup_names = (
        "VCS_HOME", "SYNOPSYS", "SYNOPSYS_HOME", "SYNOPSYS_ROOT",
        "SYNOPSYS_DC_ROOT", "XILINX_VIVADO", "LM_LICENSE_FILE",
        "SNPSLMD_LICENSE_FILE", "AWS_FPGA_REPO_DIR",
    )
    report = {
        "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "python_version": platform.python_version(),
        "python_executable": sys.executable,
        "tools_on_path": {name: shutil.which(name) for name in names},
        "setup_variable_present": {name: name in os.environ for name in setup_names},
        "scope": "Current shell only; no remote access, license checkout, or synthesis performed.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Platform: {report['system']} {report['release']} {report['machine']}")
    print(f"Running Python: {report['python_version']}")
    for name, path in report["tools_on_path"].items():
        print(f"{name}: {path or 'NOT FOUND in this shell PATH'}")
    print(f"Inventory saved to {args.output}")
    print("Availability only. Use a smoke test to establish that a tool works.")


if __name__ == "__main__":
    main()

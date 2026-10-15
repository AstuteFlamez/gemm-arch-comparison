# Setup guide

Run commands from the repository root. The supported matrix dimensions are
**8, 16, and 32**. Use a stable source snapshot and fresh output paths for each
study; the runner, exporter, and plotter reject existing output paths.

## Local simulation

Install Python 3.10+, Make, Icarus Verilog (`iverilog` and `vvp`), and Tcl
(`tclsh`, used by the Python tests for FPGA configuration and report tooling).
No third-party Python packages are needed for the regression suite.

Run the same regression used by GitHub Actions:

```sh
make check
```

This inventories the local tools, checks the Python helpers, runs RTL unit and
controller tests, exercises both cores and matched comparisons at 8×8, 16×16,
and 32×32, and simulates both DE2-115 wrappers. Any failed check exits nonzero.
`make smoke` is a shorter tool check using the existing MAC testbench;
`make smoke-vcs` runs that testbench on a configured VCS machine.

To run just the GEMM regressions and the isolated PPA benchmark:

```sh
make env
make test-gemm-all-sizes
make test-gemm-ppa PPA_SIZES="8 16 32"
```

Logs and cycle counts go under `build/`. For a smaller check, use
`make test-gemm-comparison MATRIX_DIM=8`. With the default seed and case count,
this checks 110 identical matrix pairs, prints `PASS` for both cores, and reports
544 systolic clocks versus 512 conventional clocks per multiplication.
Local simulation produces correctness and timing counts; area and power require
the Synopsys flow below.

The [CI workflow](../.github/workflows/ci.yml) uses Ubuntu 24.04 and Python 3.12,
installs Icarus and Tcl, and runs `make check` on pushes, pull requests, or manual
dispatches. It retains simulation logs, cycle counts, and fixture manifests as
the `regression-evidence` artifact for 14 days, including logs from failed runs.
The README's status badge reflects workflow runs on `master` after publication;
it does not represent a new Synopsys PPA study or a physical board test.

## GitHub presentation metadata

[github-about.json](github-about.json) is a local draft of the repository's
About description and topics. Copy those values into GitHub's About settings
when ready; GitHub does not apply this file automatically.

## Synopsys on CAE (UW-Madison's Engieering Machines)

The study used **VCS and Design Compiler/Power Compiler Y-2026.03** through CAE's
supported container. Use your normal account; project scripts need no admin
access. Tool licenses and read access to the target library are required.
The paths below were verified on October 8, 2026.

From a CAE host shell containing your copy of this repository:

```sh
module load synopsys/suite
export PPA_TOOL_PREFIX="synopsys-run env SYNOPSYS_LC_ROOT=/srv/auto/apps/synopsys-2026/lc/Y-2026.03"
make gemm-ppa PPA_SIZES=8 GEMM_RANDOM_COUNT=1
```

This small setup check runs both architectures. The Library Compiler path
resolves CAE's `LCSH-3` library-report error. The runner already supplies VCS's
64-bit and SAIF-capture options.

The default [SAED32 configuration](../scripts/synopsys/config.saed32.json) uses
RVT typical cells at **1.05 V, 25 °C**, a **10 ns clock**, equal I/O constraints,
and fixed wire-load model `8000`. Its absolute library path is CAE-specific.
Synthesis uses one CPU, high mapping effort, and no retiming or added clock gating.
The full numerical settings are in that JSON file.

For another environment, copy [the example config](../scripts/synopsys/config.example.json)
and supply `--config` or `PPA_CONFIG`. Verify the library name, corner, time and
capacitance units, and timing/internal-power/leakage models. Use identical settings
for both cores. A generic example library is not automatically suitable for PPA.

## Run the three-seed study

After the setup check succeeds, use the same module-loaded shell. The subshell
stops on failure; runs and synthesis remain serial.

```sh
(
  set -e
  for seed in 20261008 20261009 20261010; do
    python3 scripts/run_gemm_ppa.py --flow ppa --sizes 8 16 32 \
      --random-count 100 --seed "$seed" \
      --config scripts/synopsys/config.saed32.json \
      --tool-prefix "$PPA_TOOL_PREFIX" \
      --out "build/study/seed-$seed"
  done
  python3 scripts/export_gemm_ppa.py build/study/seed-* \
    --out build/study-reports.zip
)
```

Each configuration checks ten directed warmups plus 100 random pairs. `run.json`
records commands, settings, hashes, and status; each size/architecture directory
contains simulation evidence in `sim/` and synthesis reports in `dc/`.

**`reports_need_review` means generation finished, not final acceptance.** Check:

- Library units, applied constraints, vendor errors, and warning categories.
- Setup/hold/design-rule results and unconstrained endpoints before claiming speed.
- Correct activity scope, full port/register annotation, and unknown-state activity.
- Consistent full-core area/power scope and separate dynamic/leakage components.

Compute time is cycles × clock period. Energy is average total power × complete
transaction time. A single passing clock target does not establish Fmax.

## Export and graph the results

The archive contains selected reports, checks, and hashes. Licensed library data,
raw SAIF, and mapped netlists/DDCs stay on CAE. Copy `build/study-reports.zip`
through your normal authenticated connection into the local repository's `build/`.

On the local machine, use **Python 3.12 or newer** for the pinned plotting packages
and choose unused extraction and graph directories:

```sh
python3 -m zipfile -e build/study-reports.zip build/study-reports
python3 -m venv build/ppa-plot-venv
build/ppa-plot-venv/bin/python -m pip install -r scripts/requirements-ppa-plots.txt
build/ppa-plot-venv/bin/python scripts/plot_gemm_ppa.py \
  build/study-reports/seed-* --out build/study-graphs \
  --area-units-review docs/saed32-area-units.json
```

The plotter requires three complete seeds and checks fixture/source consistency,
correctness, timing, and activity coverage. It writes SVG/PNG graphs, a PDF,
CSV measurements, and JSON model details. Vendor warnings still need review.

The [area-unit evidence](saed32-area-units.json) must match the library hash to
show physical area; the graphs convert µm² to mm². With another library, omit
that option until its units are qualified. CSV fields retain `*_library_units`;
for this SAED32 library, one report unit equals one µm².

Read the [experiment](EXPERIMENT.md) for the completed findings and limitations.
The optional 8×8 FPGA demo has a separate [DE2-115 guide](../fpga/de2_115/README.md).

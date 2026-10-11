# GEMM on the DE2-115

This is the FPGA demo for the personal GEMM project. Each button press runs
**110 matrix multiplications: 10 directed cases and 100 seeded random pairs**.
Each pair contains two signed 8×8 INT8 matrices, A and B. The selected four-MAC
GEMM core computes C, and the wrapper checks all 64 INT32 outputs per pair.
The computer is needed to compile and program the board; the test runs on its own
after programming.

## Two matching FPGA builds

The project has two revisions, each containing exactly one compute core:

- **gemm_de2_115:** systolic; `UseConventional=0`.
- **gemm_de2_115_conventional:** conventional; `UseConventional=1`.

`de2_115_gemm_top.sv` selects the core at elaboration through a named generate
block. This adds no runtime selector or second compute core. Both revisions use
`gemm_de2_115_common.qsf` for the device, pins, source files shared by both cores,
clock constraint, and placement seed (1). They use the same Quartus default
synthesis and multiplier-inference settings. Apply any future optimization
settings to the common file, and inspect the reports for actual multiplier and
RAM mapping. Four RTL MACs do not necessarily mean four physical DSP blocks.

Use the same Quartus installation for both builds. The revisions have separate
output directories but share the project database, so compile them sequentially.

## Run it on the CAE lab PC

1. Copy the project to a writable folder on the lab PC or your CAE drive. Keep
   `rtl/` and `fpga/de2_115/` in the same relative locations. If using the supplied
   ZIP, extract the whole ZIP first. Keep `inputs_a.hex`, `inputs_b.hex`,
   `expected.hex`, and `gemm_vectors.svh` beside the `.qpf` file. These files are
   checked in together, so Python is not needed to compile from the Quartus GUI.
2. Open **Quartus Prime Lite**, then **File → Open Project** and select
   `fpga/de2_115/gemm_de2_115.qpf`. In **Project → Revisions**, select
   `gemm_de2_115` for the first run, then repeat these steps with
   `gemm_de2_115_conventional` for the second run.
3. Confirm the device is **EP4CE115F29C7** (Cyclone IV E) and the top-level entity
   is **de2_115_gemm_top**. If the device is missing, the installation needs the
   Cyclone IV device support package. Only synthesizable RTL belongs in this
   project; simulation testbenches are already excluded.
4. Choose **Processing → Start Compilation**. Inspect the messages for errors,
   missing sources or initialization files, and ignored assignments. In the
   Timing Analyzer reports, confirm the 20 ns clock constraint was applied and
   setup/hold/recovery/removal timing passes. Internal paths must not be
   unconstrained. A generated `.sof` alone does not establish timing closure.
5. Power the DE2-115 and connect the PC to its **USB-Blaster** USB port. Set
   **SW19 to RUN** for JTAG programming. This project assumes the normal **2.5 V
   JP7 setting** for the button pins; match the lab board's actual setting before
   programming. The clock pin uses 3.3 V and the LED pins use 2.5 V.
6. Open **Tools → Programmer**, choose **USB-Blaster** in Hardware Setup, and
   select JTAG mode. Add the matching bitstream from the project root:
   `build/quartus/de2_115/gemm_de2_115.sof` for systolic, or
   `build/quartus/de2_115-conventional/gemm_de2_115_conventional.sof` for conventional. Select
   **Program/Configure** for the Cyclone IV device and click **Start**.
7. Green **LEDG2** means ready. Press and release **KEY1**. Green **LEDG0** means
   all **7,040 results across 110 pairs** matched; red **LEDR0** means a mismatch
   or timeout in any pair. Press **KEY0** to reset, or press KEY1 again to repeat
   the entire suite from case zero.

The button polarity, pins, clock, voltages, and JTAG setup come from the
[Terasic DE2-115 manual](https://www.terasic.com.tw/attachment/archive/502/DE2_115_User_manual.pdf),
sections 4.1–4.5 and 4.7, tables 4-2, 4-3, 4-5, and 4-8. An accessible copy of
the same manual is [hosted by Mouser](https://www.mouser.com/pdfdocs/Terasic_DE2115_User_manual.pdf).

This uses a volatile JTAG `.sof` load. Power cycling removes this design from
the FPGA; it does not replace the board's flash image.

## Buttons and LEDs

- **KEY0:** reset. Release it before running the test.
- **KEY1:** run the full suite once per press. Holding it does not repeat; presses while busy
  are ignored. The board already debounces these buttons; the wrapper adds
  clock-domain synchronization and edge detection.
- **LEDG0 / LED_PASS:** every result in every pair matched. Holds until reset or the next run.
- **LEDR0 / LED_FAIL:** a result differed or completion timed out. Also holds.
- **LEDG1 / LED_BUSY:** loading, computing, or checking. The run is too short
  for this LED to be reliably visible by eye.
- **LEDG2 / LED_READY:** idle or showing a completed result; another run is allowed.

## How the hardware test works

`de2_115_gemm_top.sv` replaces the simulator's host driver with a small state
machine. It resets the core once at the start of a suite, then repeats these
steps for each pair:

1. Read one A/B word pair from the input ROMs, then write it into GEMM's A/B
   memories on the next clock. Loading 64 addresses takes 128 clocks.
2. Pulse `start` and wait for `done`. Systolic takes 544 work clocks per pair;
   conventional takes 512.
3. Read one C word and its stored expected answer, then compare on the next
   clock. Checking all 64 outputs takes 128 clocks.
4. Load the next pair without resetting the core. PASS is asserted only after
   the last pair; a mismatch stops the suite immediately with FAIL.

The core handles **one pair at a time** and computes its 16 output tiles in
sequence. It supports repeated jobs, but has no queue or second operand bank
for loading another pair during computation. This suite exercises the normal
restart path between jobs, including clearing the previous sticky `done` on
the next `start`. Reset also runs automatically after FPGA configuration. Each
pair has its own 4096-clock completion timeout. At 50 MHz, core computation is
**10.88 microseconds for systolic** and **10.24 microseconds for conventional**.
Including loading, checking, and wrapper transitions, the default suite takes
about **1.76 ms for systolic** or **1.69 ms for conventional** in simulation.
These are simulation-derived times, not physical measurements or maximum
operating frequencies. The LEDs indicate correctness, not execution time.

## Test data and randomness

The 10 directed cases cover zero A, zero B, left and right identity, all ones,
the original signed ramp pair, maximum positive/negative sums, positive INT8
extremes, and mixed signs. The next 100 cases use independent pseudorandom A/B
entries across the full signed INT8 range, -128 through 127, with seed
**20261008**. The case order and seed are recorded in `vectors_manifest.json`.

Python generates both operands and exact integer matrix products before
compilation. `inputs_a.hex` and `inputs_b.hex` contain two hexadecimal digits per
word; `expected.hex` contains eight. All use two's-complement encoding and
case-major, then row-major order: case 0's 64 words, then case 1's 64 words, etc.
`gemm_vectors.svh` supplies the matching dimensions and case count; this board
wrapper remains fixed at 8×8. The manifest also records the input/result widths.
The hardware reads these ROMs synchronously to support embedded-memory inference.

Random inputs are **prepared ahead of time**, not generated anew on the FPGA.
Every button press replays the same suite, so failures are reproducible. The
FPGA still computes every C matrix itself; expected answers are only used for
comparison. No inputs are streamed from the computer during a run.

Regenerate all fixture files together from the repository root:

```sh
make de2-115-vectors
make check-de2-115-vectors
```

To change the seed or random-case count, pass matching `BOARD_SEED` and
`BOARD_RANDOM_COUNT` values when regenerating, testing, and compiling with Make.
Recompile and reprogram the board to use the changed data.

For 16×16 or 32×32 simulation, use `make test-gemm-comparison MATRIX_DIM=32`
or `make test-gemm-all-sizes`. Those commands generate separate fixtures under
`build/` using `GEMM_SEED` and `GEMM_RANDOM_COUNT`; they do not change the board ROMs.

GEMM's memories, FIFOs, and the test ROMs are inside the FPGA; this demo does not
connect to external SRAM or SDRAM. The default test ROM payload is **42,240
bytes (41.25 KiB)**, before FPGA memory-block packing. This is demo overhead,
separate from the GEMM core's resource use. Check the Fitter report to confirm
memory inference and actual utilization. The LED result reports correctness;
power estimation and timing/resource reports are separate PPA work.

## Build and verification

From the repository root, run `make test-de2-115` for both board-wrapper
configurations, or `make test-de2-115-systolic` / `make test-de2-115-conventional`
to select one. It first verifies that checked-in fixtures match the generator,
then checks every expected word with a separate SystemVerilog mathematical
reference. It verifies all operand loads, ordered consecutive jobs, every
result read, and no early PASS. It also covers held/busy buttons, power-up and
manual reset, faults in the first/middle/final case, a later-case timeout, and
reset/restart between pairs. It also checks accepted-start-to-done latency on
every normally completed job, excluding the intentionally stalled core.
`make test-python` checks the generator with
hand-derived answers, independent outer-product accumulation, and encoding and
reproducibility checks. `make test-gemm` runs the existing core regression.

On a machine with Quartus on PATH, run:

```sh
make quartus-de2-115-comparison
```

This compiles both revisions serially and exports their saved report tables.
`make quartus-de2-115` builds only systolic;
`make quartus-de2-115-conventional` builds only conventional.

Without Make, open a Quartus command prompt in `fpga/de2_115/` and run these
commands in order. Stop and resolve any compile/export error before continuing:

```sh
quartus_sh --flow compile gemm_de2_115 -c gemm_de2_115
quartus_sh -t ../../scripts/export_quartus_reports.tcl gemm_de2_115 gemm_de2_115 ../../build/quartus/de2_115/comparison
quartus_sh --flow compile gemm_de2_115 -c gemm_de2_115_conventional
quartus_sh -t ../../scripts/export_quartus_reports.tcl gemm_de2_115 gemm_de2_115_conventional ../../build/quartus/de2_115-conventional/comparison
```

The `.qsf` lists the device, sources, and physical pins. The `.sdc` constrains
the board clock to 50 MHz. Its only timing exceptions are the asynchronous
button inputs and human-observed LED outputs; core register paths remain timed.
Unused board pins are configured as inputs with no output drive.

## Collecting a comparison

After compiling, each output directory contains a `comparison/` directory.
Open `panels.txt` first: it records the revision, Quartus version, device, seed,
and the CSV filename for each exported table. Only files listed in that manifest
belong to the current export. The script preserves the report's labels, units,
and empty values, and returns an error if a required report group is absent.
It exports evidence; it does not declare that the design meets timing.

Keep the original `.fit.rpt`, `.sta.rpt`, compile messages, and the exported
tables with the Git commit used for the experiment. Check Flow Summary/Settings
for the actual compile version/date and review ignored assignments or warnings.

For each revision, record:

- **Hardware correctness:** whether the full suite passes on the board, and
  whether reset and a second KEY1 press work. Record which `.sof` was programmed.
- **Whole-design resources:** logic elements, registers, embedded multiplier
  elements, RAM blocks, and memory bits from the Fitter summary/resource reports.
- **GEMM resources:** the `u_gemm` subtree under `gen_systolic` or
  `gen_conventional` in **Resource Utilization by Entity**, including its MACs,
  controllers, FIFOs, and A/B/C memories. Follow the report's inclusive/exclusive
  column definitions; do not add parent totals to their children. Keep the board
  wrapper, input ROMs, and expected-result ROM outside the core count. Report
  whole-design totals too, because fitting can move or share resources across
  hierarchy boundaries. If attribution is unclear, label it unresolved rather
  than treating the whole board design as the core.
- **Timing at 50 MHz:** clock period and worst setup/hold/recovery/removal slack
  across reported operating corners, plus unconstrained-path checks. Internal
  core paths must be constrained. The expected asynchronous-button and LED
  exceptions are documented in the SDC. An exported report or `.sof` is not a
  timing pass. Record Fmax separately if available; it is an estimate and does
  not replace checking all timing constraints.
- **Latency:** 544 and 512 core clocks are verified in simulation. A passing LED
  only confirms correct completion within the timeout; it does not independently
  measure these exact cycle counts on the physical board.

Compare FPGA resources separately; adding logic elements, RAM blocks, and
multiplier blocks into one unweighted "area" number would be misleading.
The existing 50 MHz constraint is the first common operating point. A later
maximum-frequency experiment needs matching timing targets and successful timing
closure for each build. If a difference is small, repeat both with the same set
of placement seeds before making a strong claim from one placement.

Power is the next measurement stage, after these builds are validated. Generate
representative activity for the same matrix sequence at the same clock, use
matching voltage/temperature settings, and check activity-mapping coverage and
the analyzer's confidence. Exclude long button-wait idle periods from an active
workload estimate. Report core versus whole-design scope and dynamic versus
static power explicitly. For energy per matrix, use average power and elapsed
time over the same defined workload window. A wall-plug board reading includes
other components and is not a measurement of GEMM-core power.

Relevant vendor references: [Quartus report scripting API](https://cdrdv2-public.intel.com/654662/tclscriptrefmnl.pdf)
and [Standard Edition power analysis](https://www.intel.com/programmable/technical-pdfs/683506.pdf).

Local simulations cover both revisions. The Tcl configuration and exporter logic
are checked with local stubs, which do not validate Quartus itself. Quartus
compilation, report export against a real report database, resource usage, timing
closure, and physical board operation still need verification on the CAE PC.
This repository does not include prebuilt or hardware-validated `.sof` files.

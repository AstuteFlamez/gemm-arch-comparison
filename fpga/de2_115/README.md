# GEMM on the DE2-115

This is the FPGA demo for the personal GEMM project. Each button press runs
**110 matrix multiplications: 10 directed cases and 100 seeded random pairs**.
Each pair contains two signed 8×8 INT8 matrices, A and B. The existing 2×2
systolic GEMM computes C, and the wrapper checks all 64 INT32 outputs per pair.
The computer is needed to compile and program the board; the test runs on its own
after programming.

## Run it on the CAE lab PC

1. Copy the project to a writable folder on the lab PC or your CAE drive. Keep
   `rtl/` and `fpga/de2_115/` in the same relative locations. If using the supplied
   ZIP, extract the whole ZIP first. Keep `inputs_a.hex`, `inputs_b.hex`,
   `expected.hex`, and `gemm_vectors.svh` beside the `.qpf` file. These files are
   checked in together, so Python is not needed to compile from the Quartus GUI.
2. Open **Quartus Prime Lite**, then **File → Open Project** and select
   `fpga/de2_115/gemm_de2_115.qpf`.
3. Confirm the device is **EP4CE115F29C7** (Cyclone IV E) and the top-level entity
   is **de2_115_gemm_top**. If the device is missing, the installation needs the
   Cyclone IVV device support package. Only synthesizable RTL belongs in this
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
   select JTAG mode. Add
   `build/quartus/de2_115/gemm_de2_115.sof` from the project root. Select
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
2. Pulse `start` and wait for `done`. The core takes 544 work clocks per pair.
3. Read one C word and its stored expected answer, then compare on the next
   clock. Checking all 64 outputs takes 128 clocks.
4. Load the next pair without resetting the core. PASS is asserted only after
   the last pair; a mismatch stops the suite immediately with FAIL.

The core handles **one pair at a time** and computes its 16 output tiles in
sequence. It supports repeated jobs, but has no queue or second operand bank
for loading another pair during computation. This suite exercises the normal
restart path between jobs, including clearing the previous sticky `done` on
the next `start`. Reset also runs automatically after FPGA configuration. Each
pair has its own 4096-clock completion timeout. Including load and check
overhead, the default suite takes about **1.76 ms at 50 MHz** in simulation;
544 clocks / 50 MHz = **10.88 microseconds** is the core computation per pair.

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
`gemm_vectors.svh` supplies the matching case count to the RTL and testbench.
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

GEMM's memories, FIFOs, and the test ROMs are inside the FPGA; this demo does not
connect to external SRAM or SDRAM. The default test ROM payload is **42,240
bytes (41.25 KiB)**, before FPGA memory-block packing. This is demo overhead,
separate from the GEMM core's resource use. Check the Fitter report to confirm
memory inference and actual utilization. The LED result reports correctness;
power estimation and timing/resource reports are separate PPA work.

## Build and verification

From the repository root, run `make test-de2-115` for the board-wrapper
simulation. It first verifies that checked-in fixtures match the generator,
then checks every expected word with a separate SystemVerilog mathematical
reference. It verifies all operand loads, ordered consecutive jobs, every
result read, and no early PASS. It also covers held/busy buttons, power-up and
manual reset, faults in the first/middle/final case, a later-case timeout, and
reset/restart between pairs. `make test-python` checks the generator with
hand-derived answers, independent outer-product accumulation, and encoding and
reproducibility checks. `make test-gemm` runs the existing core regression.

On a machine with Quartus on PATH, `make quartus-de2-115` compiles the project.
Without Make, open a Quartus command prompt in `fpga/de2_115/` and run:

```sh
quartus_sh --flow compile gemm_de2_115
```

The `.qsf` lists the device, sources, and physical pins. The `.sdc` constrains
the board clock to 50 MHz. Its only timing exceptions are the asynchronous
button inputs and human-observed LED outputs; core register paths remain timed.
Unused board pins are configured as inputs with no output drive.

Local RTL simulation passes. Quartus compilation, resource usage, timing closure,
and a physical board run still need verification on the CAE PC; this repository
does not include a prebuilt or hardware-validated `.sof`.

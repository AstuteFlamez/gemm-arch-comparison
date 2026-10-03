# GEMM on the DE2-115

This is the FPGA demo for the personal GEMM project. It loads two signed 8×8
matrices, runs the existing 2×2 systolic GEMM, and checks every output in hardware.
The computer is needed to compile and program the board; the test runs on its own
after programming.

## Run it on the CAE lab PC

1. Copy the project to a writable folder on the lab PC or your CAE drive. Keep
   `rtl/` and `fpga/de2_115/` in the same relative locations. If using the supplied
   ZIP, extract the whole ZIP first. Keep `expected.hex` beside the `.qpf` file.
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
   all 64 results matched; red **LEDR0** means a mismatch or timeout. Press
   **KEY0** to reset, or press KEY1 again to repeat the test.

The button polarity, pins, clock, voltages, and JTAG setup come from the
[Terasic DE2-115 manual](https://www.terasic.com.tw/attachment/archive/502/DE2_115_User_manual.pdf),
sections 4.1–4.5 and 4.7, tables 4-2, 4-3, 4-5, and 4-8. An accessible copy of
the same manual is [hosted by Mouser](https://www.mouser.com/pdfdocs/Terasic_DE2115_User_manual.pdf).

This uses a volatile JTAG `.sof` load. Power cycling removes this design from
the FPGA; it does not replace the board's flash image.

## Buttons and LEDs

- **KEY0:** reset. Release it before running the test.
- **KEY1:** run once per press. Holding it does not repeat; presses while busy
  are ignored. The board already debounces these buttons; the wrapper adds
  clock-domain synchronization and edge detection.
- **LEDG0 / LED_PASS:** every result matched. Holds until reset or the next run.
- **LEDR0 / LED_FAIL:** a result differed or completion timed out. Also holds.
- **LEDG1 / LED_BUSY:** loading, computing, or checking. The run is too short
  for this LED to be reliably visible by eye.
- **LEDG2 / LED_READY:** idle or showing a completed result; another run is allowed.

## How the hardware test works

`de2_115_gemm_top.sv` replaces the simulator's host driver with a small state
machine. It resets the core, writes all 64 A/B entries, pulses `start`, waits for
`done`, and reads and compares all 64 C entries. Each C read has a request cycle
and a comparison cycle because the SRAM read is synchronous. Reset also runs
automatically after FPGA configuration. The core has a 4096-cycle completion
timeout, compared with its normal 544-cycle computation.

The test uses row-major `A[r][k] = 8*r + k - 32` and
`B[k][c] = 31 - 8*k - c`. Both contain positive and negative values.
`expected.hex` holds the 64 signed 32-bit dot products in row-major order,
written as eight hexadecimal digits per word. For example, C[0][0] is -1020
(`fffffc04`). These are fixed reference data loaded into the FPGA configuration,
not results calculated by another multiplier during the hardware test.

GEMM's A/B/C memories and FIFOs are implemented inside the FPGA. This demo does
not connect to the board's external SRAM or SDRAM. It tests one known matrix
pair; the broader arithmetic regression remains `make test-gemm`.

## Build and verification

From the repository root, run `make test-de2-115` for the board-wrapper
simulation. It checks the expected data against a mathematical reference,
all result reads, button behavior, automatic/manual reset, fault reporting, and
timeout recovery. `make test-gemm` runs the full core regression.

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

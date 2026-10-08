# RTL Learning Projects

Small SystemVerilog projects comparing 8×8 GEMM with a 2×2 systolic array
and a conventional four-MAC implementation.

## GEMM architecture

The systolic GEMM core reuses one 2×2 systolic array across 16 output tiles. The top-level
controller selects each tile; the systolic tile controller loads four FIFOs,
runs the array, and writes its four results to C SRAM.

![2×2 systolic GEMM with A FIFOs on the left and B FIFOs above](docs/systolic-array.svg)

Load A and B while idle, then assert `start` for a clock edge. The calculation
takes 544 clocks after accepting `start`. `busy` stays high throughout; `done`
stays high after completion until the next accepted start or reset. Read C while
idle; its synchronous read data updates after the rising edge. Run `make test-gemm`
to check full 8×8 arithmetic and host control behavior.

The core handles one A/B matrix pair at a time. After completion, read C, load
the next pair, and assert `start` again; no reset is required between jobs.
There is one set of operand memories, so loading the next pair cannot overlap
the current computation. Host writes while `busy` are ignored.

## Conventional four-MAC baseline

[`conventional_gemm.sv`](rtl/gemm/conventional_matmul/conventional_gemm.sv)
uses the same host interface, top-level tile sequencer, SRAM wrapper, four
eight-word FIFOs, and signed INT8-to-INT32 MAC module. The difference is how
operands reach the four MACs: direct fanout sends each A/B value to two MACs,
and all four outputs accumulate the same `k` in parallel.

![Conventional four-MAC GEMM with direct operand fanout](docs/naive-matmul.svg)

Start reading at
[`conventional_tile_controller.sv`](rtl/gemm/conventional_matmul/conventional_tile_controller.sv).
Its phases are `IDLE → LOAD_FIFO → COMPUTE → STORE → FINISH`:

- `LOAD_FIFO`: 17 clocks to fill the FIFOs from synchronous SRAM; clear all four
  accumulators on the first loading edge.
- `COMPUTE`: one clock to prime the registered FIFO outputs, then eight clocks
  of accumulation. All four FIFOs pop together; all four MACs finish together.
- `STORE`: four clocks to write C00, C01, C10, C11 through C SRAM's single port.
- `FINISH`: pulse tile completion for the shared top-level controller.

The tile controller asserts `done` 30 clocks after accepting its tile request.
Including the top-level launch and completion handshake, each tile takes 32
clocks: 16 tiles × 32 = **512 clocks per full matrix**, versus **544 clocks**
for the systolic core. These counts run from accepted `start` to `done` and
exclude host loading and result readback. Both cores handle consecutive jobs
without reset, one A/B pair at a time.

Run the conventional tile test, shared host-protocol regression, and comparison:

```sh
make test-conventional-tile-controller
make test-conventional-gemm
make test-gemm-comparison
```

The tile test checks 32 consecutive tiles, intermediate accumulation, writeback,
and reset. Both `make test-gemm` and `make test-conventional-gemm` use the same
testbench: 44 completed jobs, 2,817 output checks, and 11 reset/restart cases.
The comparison feeds both cores the FPGA demo's identical 10 directed + 100
seeded random pairs, independently recomputes the reference results, and checks
all 7,040 outputs per core without resetting between pairs.

This establishes functional agreement and cycle counts for these implementations.
FPGA clock frequency, resource usage, and power still require synthesis,
implementation, and power analysis with matching settings and workloads.
The existing DE2-115 project currently instantiates the systolic core.

## FPGA demo

The [DE2-115 Quartus project](fpga/de2_115/README.md) adds a button-operated
hardware test with PASS/FAIL LEDs. Each press runs 10 directed and 100 seeded
random matrix pairs in sequence, checking all 7,040 output words before PASS.
Run `make test-de2-115` to simulate the wrapper,
then follow the linked guide to compile and program it from Quartus on the CAE
lab PC. FPGA timing and board operation still require verification there.

## Implementation order

| Status | File | Done / remaining work |
| --- | --- | --- |
| DONE | [mac.sv](rtl/gemm/mac.sv) | Signed multiply-accumulate |
| DONE | [sram.sv](rtl/gemm/memory/sram.sv) | Parameterized synchronous memory |
| DONE | [memory_wrapper.sv](rtl/gemm/memory/memory_wrapper.sv) | A/B/C SRAMs; read/write port naming; idle/compute access gating |
| DONE | [fifo.sv](rtl/gemm/fifo.sv) | Parameterized width/depth; pointers wrap at DEPTH-1 |
| DONE | [pe.sv](rtl/gemm/systolic_array/pe.sv) | One MAC; registered A/B forwarding and validity; standalone PE verified |
| DONE | [systolic_array.sv](rtl/gemm/systolic_array/systolic_array.sv) | Connect four PEs; verify one output tile |
| DONE | [systolic_tile_controller.sv](rtl/gemm/systolic_array/systolic_tile_controller.sv) | Load four FIFOs; stagger pops and validity; write four results |
| DONE | [top_level_controller.sv](rtl/gemm/top_level_controller.sv) | Sequence 16 tiles; wait for tile completion; maintain busy and sticky done |
| DONE | [systolic_gemm.sv](rtl/gemm/systolic_array/systolic_gemm.sv) | Connect both controllers, four FIFOs, SRAMs, and the array; full 8×8 GEMM verified |
| DONE | [conventional_tile_controller.sv](rtl/gemm/conventional_matmul/conventional_tile_controller.sv) | Load FIFOs, pop in lockstep, enable eight MAC steps, store four results; simulated |
| DONE | [conventional_gemm.sv](rtl/gemm/conventional_matmul/conventional_gemm.sv) | Direct fanout to four MACs; same arithmetic/protocol tests and FPGA fixture comparison pass |
| LATER | [gemv.sv](rtl/gemv/gemv.sv) | Existing GEMV works; SRAM conversion |

## Repository layout

<pre>.
├── <a href="rtl/">rtl/</a>
│   ├── <a href="rtl/gemm/">gemm/</a>
│   │   ├── <a href="rtl/gemm/mac.sv">mac.sv</a>
│   │   ├── <a href="rtl/gemm/fifo.sv">fifo.sv</a>
│   │   ├── <a href="rtl/gemm/top_level_controller.sv">top_level_controller.sv</a>
│   │   ├── <a href="rtl/gemm/memory/">memory/</a>
│   │   │   ├── <a href="rtl/gemm/memory/sram.sv">sram.sv</a>
│   │   │   └── <a href="rtl/gemm/memory/memory_wrapper.sv">memory_wrapper.sv</a>
│   │   ├── <a href="rtl/gemm/systolic_array/">systolic_array/</a>
│   │   │   ├── <a href="rtl/gemm/systolic_array/pe.sv">pe.sv</a>
│   │   │   ├── <a href="rtl/gemm/systolic_array/systolic_array.sv">systolic_array.sv</a>
│   │   │   ├── <a href="rtl/gemm/systolic_array/systolic_tile_controller.sv">systolic_tile_controller.sv</a>
│   │   │   └── <a href="rtl/gemm/systolic_array/systolic_gemm.sv">systolic_gemm.sv</a>
│   │   └── <a href="rtl/gemm/conventional_matmul/">conventional_matmul/</a>
│   │       ├── <a href="rtl/gemm/conventional_matmul/conventional_tile_controller.sv">conventional_tile_controller.sv</a>
│   │       └── <a href="rtl/gemm/conventional_matmul/conventional_gemm.sv">conventional_gemm.sv</a>
│   └── <a href="rtl/gemv/">gemv/</a>
│       └── <a href="rtl/gemv/gemv.sv">gemv.sv</a>
├── <a href="tb/">tb/</a>          # SystemVerilog testbenches
├── <a href="tests/">tests/</a>       # Python reference model, vectors, and tests
├── <a href="docs/">docs/</a>        # Design notes
├── <a href="scripts/">scripts/</a>     # Tool and environment checks
├── <a href="Makefile">Makefile</a>     # Build and test commands
└── <a href="README.md">README.md</a></pre>

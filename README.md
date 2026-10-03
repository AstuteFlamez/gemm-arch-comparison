# RTL Learning Projects

Small SystemVerilog projects building toward an 8×8 GEMM using a 2×2 systolic array.

## GEMM architecture

The GEMM core reuses one 2×2 systolic array across 16 output tiles. The top-level
controller selects each tile; the memory controller loads four FIFOs, runs the
array, and writes its four results to C SRAM.

![2×2 systolic GEMM with A FIFOs on the left and B FIFOs above](docs/systolic-array.svg)

Load A and B while idle, then assert `start` for a clock edge. The calculation
takes 544 clocks after accepting `start`. `busy` stays high throughout; `done`
stays high after completion until the next accepted start or reset. Read C while
idle; its synchronous read data updates after the rising edge. Run `make test-gemm`
to check full 8×8 arithmetic and host control behavior.

## FPGA demo

The [DE2-115 Quartus project](fpga/de2_115/README.md) adds a button-operated
hardware test with PASS/FAIL LEDs. Run `make test-de2-115` to simulate the wrapper,
then follow the linked guide to compile and program it from Quartus on the CAE
lab PC. FPGA timing and board operation still require verification there.

## Implementation order

| Status | File | Done / remaining work |
| --- | --- | --- |
| DONE | [mac.sv](rtl/mac.sv) | Signed multiply-accumulate |
| DONE | [sram.sv](rtl/sram.sv) | Parameterized synchronous memory |
| DONE | [memory_wrapper.sv](rtl/memory_wrapper.sv) | A/B/C SRAMs; read/write port naming; idle/compute access gating |
| DONE | [fifo.sv](rtl/fifo.sv) | Parameterized width/depth; pointers wrap at DEPTH-1 |
| DONE | [pe.sv](rtl/pe.sv) | One MAC; registered A/B forwarding and validity; standalone PE verified |
| DONE | [systolic_array.sv](rtl/systolic_array.sv) | Connect four PEs; verify one output tile |
| DONE | [memory_controller.sv](rtl/memory_controller.sv) | Load four FIFOs; stagger pops and validity; write four results |
| DONE | [top_level_controller.sv](rtl/top_level_controller.sv) | Sequence 16 tiles; wait for tile completion; maintain busy and sticky done |
| DONE | [gemm.sv](rtl/gemm.sv) | Connect both controllers, four FIFOs, SRAMs, and the array; full 8×8 GEMM verified |
| LATER | [gemv.sv](rtl/gemv.sv) | Existing GEMV works; SRAM conversion |

## Repository layout

<pre>.
├── <a href="rtl/">rtl/</a>
│   ├── <a href="rtl/mac.sv">mac.sv</a>
│   ├── <a href="rtl/sram.sv">sram.sv</a>
│   ├── <a href="rtl/fifo.sv">fifo.sv</a>
│   ├── <a href="rtl/pe.sv">pe.sv</a>
│   ├── <a href="rtl/systolic_array.sv">systolic_array.sv</a>
│   ├── <a href="rtl/memory_wrapper.sv">memory_wrapper.sv</a>
│   ├── <a href="rtl/memory_controller.sv">memory_controller.sv</a>
│   ├── <a href="rtl/top_level_controller.sv">top_level_controller.sv</a>
│   ├── <a href="rtl/gemm.sv">gemm.sv</a>
│   └── <a href="rtl/gemv.sv">gemv.sv</a>
├── <a href="tb/">tb/</a>          # SystemVerilog testbenches
├── <a href="tests/">tests/</a>       # Python reference model, vectors, and tests
├── <a href="docs/">docs/</a>        # Design notes
├── <a href="scripts/">scripts/</a>     # Tool and environment checks
├── <a href="Makefile">Makefile</a>     # Build and test commands
└── <a href="README.md">README.md</a></pre>

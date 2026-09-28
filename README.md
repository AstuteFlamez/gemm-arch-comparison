# RTL Learning Projects

Small SystemVerilog projects building toward an 8×8 GEMM using a 2×2 systolic array.

## GEMM architecture

Planned architecture; the current GEMM still uses one MAC.

![Planned 2×2 systolic GEMM with A FIFOs on the left and B FIFOs above](docs/systolic-array.svg)

## Implementation order

| Status | File | Done / remaining work |
| --- | --- | --- |
| DONE | [mac.sv](rtl/mac.sv) | Signed multiply-accumulate |
| DONE | [sram.sv](rtl/sram.sv) | Parameterized synchronous memory |
| DONE | [memory_wrapper.sv](rtl/memory_wrapper.sv) | A/B/C SRAMs; read/write port naming; idle/compute access gating |
| DONE | [fifo.sv](rtl/fifo.sv) | Parameterized width/depth; pointers wrap at DEPTH-1 |
| DONE | [pe.sv](rtl/pe.sv) | One MAC; registered A/B forwarding and validity; standalone PE verified |
| IN-PROGRESS | [systolic_array.sv](rtl/systolic_array.sv) | Connect four PEs; verify one output tile |
| NEXT | [memory_controller.sv](rtl/memory_controller.sv) | Load four FIFOs; stagger pops and validity; write four results |
| NEXT | [top_level_controller.sv](rtl/top_level_controller.sv) | Replace scalar sequencing with tile phases |
| NEXT | [gemm.sv](rtl/gemm.sv) | Connect four FIFOs directly to the array; verify full 8×8 GEMM |
| LATER | [gemv.sv](rtl/gemv.sv) | Existing GEMV works; SRAM conversion |

## Processing element (PE)

[pe.sv](rtl/pe.sv) wraps one MAC with signed 8-bit A/B inputs and outputs,
separate 1-bit valid signals, and a signed 32-bit accumulator. On each rising
edge, the MAC accumulates the current input product only when both inputs are
valid. A and B and their valid bits are registered independently for forwarding
right and down, so neighboring PEs can consume them on the next edge.

Synchronous `reset` or `clear` clears the accumulator, forwarded data, and valid
bits, overriding accumulation. Use a separate clear cycle before feeding a new
tile. The controller must align A and B from the same dot-product position;
valid bits indicate when to use operands, not which position they belong to.

Run `make test-pe` to compile and simulate [tb_pe.sv](tb/tb_pe.sv) with Icarus.
The test passes initial reset and 17 directed cycle checks covering signed
arithmetic, sums beyond 16 bits, valid zero operands, invalid cycles holding
the sum, independent forwarding, registered timing, and reset/clear behavior.
Build logs and `pe.vcd` are written to `build/pe/`.

In progress: connect four PEs in [systolic_array.sv](rtl/systolic_array.sv) and verify
one output tile. The current GEMM still uses its original single MAC.

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

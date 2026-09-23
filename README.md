# RTL Learning Projects

I use these mini-projects to practice RTL design and verification. I write the RTL
myself. For verification, I work with ChatGPT to think through edge cases
and write tests together.

I've also used these projects to learn Synopsys tools, including VCS, Verdi,
and Design Compiler.

## Documentation

Details about each RTL mini-project and the tools I've used:

- [MAC exercise](docs/mac.md)
- [GEMV exercise](docs/gemv.md)
- [GEMM exercise](docs/gemm.md)
- [SRAM exercise](docs/sram.md)

## Current milestone

`gemm` now connects three modules: `gemm_controller`, `gemm_memory`, and `mac`.
The controller owns the FSM, counters, compute addresses, operation requests,
start acceptance, busy, and done. The memory wrapper owns A/B (64 × 8 each) and
C (64 × 32) SRAMs, host/compute routing, reset gating, and signed read conversions.
One MAC performs the arithmetic. The public interface is unchanged, and each
calculation still takes 1,152 cycles after accepting `start`.

After `done`, keep `start` low and select `c_rd_addr` before an idle rising edge.
The selected result appears on `c_rd_data` after that edge's updates. The output
holds during computation and reset.

Run the standalone memory checks and GEMM regression from the project root:

```sh
make test-sram
make test-gemm
```

Icarus passes 464 and 122 SRAM checks, plus 38 GEMM jobs and 2,433 output
comparisons. Both GEMM build targets include the controller and memory wrapper.
VCS has not been run for this integration.

## Repository layout

```text
.
├── rtl/       # MAC, GEMV, GEMM, SRAM, GEMM controller and memory wrapper
├── tb/        # SystemVerilog testbenches
├── tests/     # Python reference model, vector generator, and tests
├── scripts/   # Environment checks and Synopsys library inspection
├── docs/      # Mini-project documentation
└── Makefile   # Build and test commands
```

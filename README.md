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

GEMM now stores A and B in separate instances of a reusable synchronous SRAM
module. Both memories register their read outputs, which feed the signed MAC
inputs without another register stage. The calculation still takes 1,152 cycles
after accepting `start`.

C remains an internal array with asynchronous result reads. Moving C storage
into a memory module is the next planned step.

Run the standalone memory checks and GEMM regression from the project root:

```sh
make test-sram
make test-gemm
```

## Repository layout

```text
.
├── rtl/       # SystemVerilog RTL: MAC, GEMV, GEMM, and SRAM
├── tb/        # SystemVerilog testbenches
├── tests/     # Python reference model, vector generator, and tests
├── scripts/   # Environment checks and Synopsys library inspection
├── docs/      # Mini-project documentation
└── Makefile   # Build and test commands
```

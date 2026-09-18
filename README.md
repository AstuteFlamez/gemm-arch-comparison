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

## Repository layout

```text
.
├── rtl/       # SystemVerilog RTL: MAC, GEMV, and more to come
├── tb/        # SystemVerilog testbenches
├── tests/     # Python reference model, vector generator, and tests
├── scripts/   # Environment checks and Synopsys library inspection
├── docs/      # Mini-project documentation
└── Makefile   # Build and test commands
```

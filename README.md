# GEMM Architecture Comparison

Welcome to my GEMM architecture comparison experiment!

I built this project to compare a **2×2 systolic array** with a **conventional
four-MAC matrix multiplier** and understand their performance, power, and area
(PPA). Both use the same MAC, FIFO, memory modules, and top-level controller.
The difference is how they deliver operands: neighbor forwarding versus direct
broadcast. Both reuse data.

I tested **8×8, 16×16, and 32×32 matrices**, using signed INT8 inputs and INT32
results. The hardware stays at four MACs as the matrix size increases.

## Findings

All **1,980 matrix multiplications passed**, and both cores met the common
**100 MHz pre-layout timing target** using Synopsys and SAED32.

At 32×32, conventional took **266.24 µs**, versus **271.36 µs** for systolic:
about **1.9% less compute time**. Area and estimated power were nearly tied.
My takeaway is that the memory system and workload matter as much as the choice
of compute architecture. These results describe our two four-MAC implementations.

## Explore

- [Architecture and diagrams](docs/ARCHITECTURE.md)
- [Experiment, results, and graphs](docs/EXPERIMENT.md)
- [Setup and Synopsys instructions](docs/SETUP_GUIDE.md)
- [How I used AI](docs/AI_USAGE.md)

## Repository layout

```text
rtl/      Both GEMM cores and shared hardware
tb/       SystemVerilog testbenches
tests/    Python generators and support tests
scripts/  Simulation, synthesis, and plotting tools
docs/     Documentation, diagrams, and results
fpga/     Optional DE2-115 demo (only 8x8)
build/    Generated local outputs (ignored by Git)
```

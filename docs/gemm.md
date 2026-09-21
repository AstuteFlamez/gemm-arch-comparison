# GEMM: Matrix-Matrix Multiplication

GEMM multiplies matrices: `C = A * B`. Each output uses [MAC operations](mac.md)
to compute a row/column dot product.

## Example

```text
C[row][column] = sum of A[row][k] * B[k][column], for k = 0 through 7
```

## My implementation

The RTL is in [rtl/gemm.sv](../rtl/gemm.sv).

- A and B use separate 64 × 8 [SRAM instances](sram.md).
- One MAC processes signed INT8 operands and accumulates signed INT32 results.
- C uses a 64 × 32 SRAM, written in STORE and read in IDLE.

Addressing during computation:

```text
A address = row * 8 + k
B address = k * 8 + column
C address = row * 8 + column
```

The states are `IDLE`, `CLEAR`, `READ`, `MAC`, and `STORE`. In READ, A/B SRAMs
register operands for the following MAC edge; `$signed` adds no register.
STORE writes `mac_acc` into C. Each output takes 18 cycles: CLEAR, eight
READ/MAC pairs, then STORE. A job takes 1,152 cycles after accepting `start`.

Load A/B in IDLE; writes override start. Busy requests are ignored. Reset clears
control/accumulator state but preserves memory. `done` holds until reset or the
next accepted start.

While idle and out of reset, C samples `c_rd_addr` at each rising edge and
updates `c_rd_data` afterward. The output holds while busy or in reset. `done`
means results are stored; keep `start` low and wait for idle edges to read them.

## Verification

The [testbench](../tb/tb_gemm.sv) checks directed and seeded random matrices,
signed extremes, input reuse, busy requests, reset, result-read timing, held
start, and reset suppressing a C write. All 38 jobs and 2,433 comparisons pass.

Run `make test-gemm` locally, or `make test-gemm-vcs` on a configured VCS machine.

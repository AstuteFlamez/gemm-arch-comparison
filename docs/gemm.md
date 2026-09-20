# GEMM: Matrix-Matrix Multiplication

GEMM computes `C = A * B`. Each output is the dot product of one row of A
and one column of B, calculated with repeated [MAC operations](mac.md).

## Example

For an 8 × 8 multiplication:

```text
C[row][column] = sum of A[row][k] * B[k][column], for k = 0 through 7
```

A row of `[1, 2, 3, 4, 5, 6, 7, 8]` multiplied by a column of ones gives 36.

## My implementation

The RTL is in [rtl/gemm.sv](../rtl/gemm.sv).

- A and B use separate 64 × 8 [SRAM instances](sram.md).
- One MAC processes signed INT8 operands and accumulates signed INT32 results.
- C remains an internal 64 × 32 array with asynchronous external reads.

The caller loads A and B in `IDLE`. During computation, the controller selects:

```text
A address = row * 8 + k
B address = k * 8 + column
C address = row * 8 + column
```

The states are `IDLE`, `CLEAR`, `READ`, `MAC`, and `STORE`. READ captures both
SRAM outputs; the following MAC edge consumes them through `$signed`
connections, without another register stage. Each output takes CLEAR, eight
READ/MAC pairs, and STORE: 18 cycles, or 1,152 cycles per complete job.

Load both matrices before starting. Writes take priority over start in IDLE;
writes and extra starts are ignored while busy. Reset clears control state and
the accumulator but preserves memory. `done` stays high until reset or the
next accepted start. Converting C storage is the next planned step.

## Verification

The [testbench](../tb/tb_gemm.sv) checks directed and seeded random matrices,
signed extremes, input reuse, busy requests, write/start collisions, reset,
and exact completion timing. All 38 jobs and 2,432 output comparisons pass.

Run `make test-gemm` locally, or `make test-gemm-vcs` on a configured VCS machine.

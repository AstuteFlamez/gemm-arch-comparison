# SRAM: Reusable Synchronous Memory

SRAM stores words selected by address. Static storage retains bits while
powered without refresh; this module uses rising clock edges for reads and writes.

## Example

Write decimal 13 to address 5, then read it:

```text
Before edge 1: we=1, addr=5, wdata=13
After edge 1 updates: mem[5]=13; rdata holds
Before edge 2: we=0, re=1, addr=5
After edge 2 updates: rdata=13
At edge 3: a clocked consumer can use 13
```

## My implementation

The RTL is in [rtl/sram.sv](../rtl/sram.sv).

- `DEPTH` defaults to 64 words; `DATA_WIDTH` defaults to eight bits per word.
- `$clog2(DEPTH)` gives six address bits for locations 0–63.
- One clock and one shared address serve reads and writes.
- `we` and `wdata` control writes; `re` requests reads into registered `rdata`.

At each rising edge, `we` writes the selected word. Otherwise, `re` updates
`rdata`. When both enables are high, the write wins and `rdata` holds. When
neither is high, everything holds.

The read result appears after the edge's register updates. Another clocked
block at that same edge sees the previous output. Address changes between
edges do not change `rdata`.

There is no reset or initialization: unwritten words and initial `rdata` are
unknown in simulation. GEMM reset disables memory operations, preserving data.
Bits are unsigned in storage; GEMM uses `$signed` for INT8 operands and INT32 results.

Use `DATA_WIDTH >= 1`, `DEPTH >= 2`, and addresses below `DEPTH`. Physical memory
mapping depends on the synthesis target and tools.

## Verification

The [testbench](../tb/tb_sram.sv) checks all addresses, overwrites, disabled
operations, read timing, between-edge pulses, write priority, unknown initial
data, and stored bit patterns.

Run `make test-sram`: 64 × 8 and 7 × 16 configurations pass 464 and 122 checks.

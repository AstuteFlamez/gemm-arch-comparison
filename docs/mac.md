# MAC: Multiply-Accumulate

A MAC multiplies two inputs and adds the product to a running sum:

```text
acc = acc + (a * b)
```

Repeating this across pairs of vector elements computes a dot product. MACs
are building blocks for matrix-vector multiplication (GEMV) and matrix-matrix
multiplication (GEMM): each output is a dot product.

## Example

For the vectors `[2, -3, 4]` and `[5, 6, -2]`, start with `acc = 0` and process
one pair per enabled clock edge:

```text
First pair:   acc =   0 +  2 *  5  =  10
Second pair:  acc =  10 + -3 *  6  =  -8
Third pair:   acc =  -8 +  4 * -2  = -16
```

The final accumulator value, `-16`, is the dot product.

## My implementation

The RTL is in [rtl/mac.sv](../rtl/mac.sv).

- `a` and `b` are signed 8-bit inputs.
- Their product is signed 16-bit and is sign-extended to 32 bits before addition.
- `acc` is a signed 32-bit register that updates on the rising clock edge.

The control priority is `reset`, then `clear`, then `enable`. Reset and clear
both set `acc` to zero and are synchronous: they take effect on a rising clock
edge. Otherwise, when enable is high, the MAC adds the current product to `acc`.
When enable is low, it holds the previous value.

## Verification

The [testbench (../tb/tb_mac.sv)](../tb/tb_mac.sv) checks zero inputs, positive and negative
products, repeated accumulation, and signed 8-bit endpoint combinations. It
also checks disabled hold, reset and clear overriding enable, held reset and
clear, their synchronous behavior, and a sum larger than a signed 16-bit value
can hold.

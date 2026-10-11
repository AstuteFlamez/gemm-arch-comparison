`timescale 1ns/1ps
`default_nettype none

// A moves right, B moves down, and each PE keeps one accumulated result.
// Fixed 2x2 array on clk with synchronous active-high rst/clr.
// Inputs must be skewed by row/column; each enabled edge advances the whole array.
// rst/clr discard the current tile; disabling enable holds operands and results.
module systolic_array (
    input  logic clk,
    input  logic rst,
    input  logic clr,
    input  logic enable,

    // Feed the two rows of A from the left
    input  logic signed [7:0] A0,
    input  logic signed [7:0] A1,

    // Feed the two columns of B from above
    input  logic signed [7:0] B0,
    input  logic signed [7:0] B1,

    // Four results for one output tile
    output logic signed [31:0] C00,
    output logic signed [31:0] C01,
    output logic signed [31:0] C10,
    output logic signed [31:0] C11
);

    logic signed [7:0] a0_forward;
    logic signed [7:0] a1_forward;
    logic signed [7:0] b0_forward;
    logic signed [7:0] b1_forward;

    // PE layout: 00 -> 01
    //            |     |
    //            v     v
    //            10 -> 11
    // Each forwarding connection adds one enabled clock of operand delay.

    pe u_pe00 (
        .clk(clk),
        .rst(rst),
        .clr(clr),
        .enable(enable),

        .a_in(A0),
        .b_in(B0),
        .a_out(a0_forward),
        .b_out(b0_forward),
        .acc(C00)
    );

    pe u_pe01 (
        .clk(clk),
        .rst(rst),
        .clr(clr),
        .enable(enable),

        .a_in(a0_forward),
        .b_in(B1),
        .a_out(), // No neighbor to the right
        .b_out(b1_forward),
        .acc(C01)
    );

    pe u_pe10 (
        .clk(clk),
        .rst(rst),
        .clr(clr),
        .enable(enable),

        .a_in(A1),
        .b_in(b0_forward),
        .a_out(a1_forward),
        .b_out(), // No neighbor below
        .acc(C10)
    );

    pe u_pe11 (
        .clk(clk),
        .rst(rst),
        .clr(clr),
        .enable(enable),

        .a_in(a1_forward),
        .b_in(b1_forward),
        .a_out(), // No neighbor to the right
        .b_out(), // No neighbor below
        .acc(C11)
    );

endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// A moves right, B moves down, and each PE keeps one accumulated result.
module systolic_array (
    input logic clk, reset, enable,

    // Feed the two rows of A from the left
    input logic signed [7:0] A0, A1,

    // Feed the two columns of B from above
    input logic signed [7:0] B0, B1,

    // Four results for one output tile
    output logic signed [31:0] C00, C01, C10, C11
);

    logic signed [7:0] A0_out, A1_out;
    logic signed [7:0] B0_out, B1_out;

    /*
    PE positions:
    00  01
    10  11
    */

    pe pe00 (
        .clk(clk),
        .reset(reset),
        .enable(enable),

        .a_in(A0),
        .b_in(B0),
        .a_out(A0_out),
        .b_out(B0_out),
        .acc(C00)
    );

    pe pe01 (
        .clk(clk),
        .reset(reset),
        .enable(enable),

        .a_in(A0_out),
        .b_in(B1),
        .a_out(), // No neighbor to the right
        .b_out(B1_out),
        .acc(C01)
    );

    pe pe10 (
        .clk(clk),
        .reset(reset),
        .enable(enable),

        .a_in(A1),
        .b_in(B0_out),
        .a_out(A1_out),
        .b_out(), // No neighbor below
        .acc(C10)
    );

    pe pe11 (
        .clk(clk),
        .reset(reset),
        .enable(enable),

        .a_in(A1_out),
        .b_in(B1_out),
        .a_out(), // No neighbor to the right
        .b_out(), // No neighbor below
        .acc(C11)
    );

endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// Signed 8-bit operands; one product accumulates on each enabled rising edge.
// Reset and clear are synchronous and active-high: rst > clr > enable.
// rst initializes the block; clr starts a new dot product. The 32-bit sum wraps.
module mac (
    input  logic clk,
    input  logic rst,
    input  logic clr,
    input  logic enable,

    input  logic signed [7:0] a,
    input  logic signed [7:0] b,

    output logic signed [31:0] acc
);

    localparam int PRODUCT_WIDTH = 16;
    localparam int ACC_WIDTH     = 32;

    logic signed [PRODUCT_WIDTH - 1:0] product;
    logic signed [ACC_WIDTH - 1:0] product_extended;

    // Preserve the full signed 8-bit by 8-bit product before accumulation.
    assign product = a * b;

    // Sign-extend the 16-bit product to match the 32-bit accumulator.
    assign product_extended = {{(ACC_WIDTH - PRODUCT_WIDTH){product[PRODUCT_WIDTH - 1]}}, product};

    // Clear works even when disabled; otherwise a disabled MAC holds its sum.
    always_ff @(posedge clk) begin
        if (rst) begin
            acc <= '0;
        end else if (clr) begin
            acc <= '0;
        end else if (enable) begin
            acc <= acc + product_extended;
        end
    end

endmodule

`default_nettype wire

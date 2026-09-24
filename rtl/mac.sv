`timescale 1ns/1ps
`default_nettype none

module mac (
    input  logic clk,
    input  logic reset,
    input  logic clear,
    input  logic enable,
    input  logic signed [7:0] a,
    input  logic signed [7:0] b,
    output logic signed [31:0] acc
);

    logic signed [15:0] product;
    logic signed [31:0] product_extended;

    assign product = a * b; // 8 bits * 8 bits = NEED 16 bits
    assign product_extended = { {16{product[15]}}, product }; // 16 sign-extended bits, 16 original product bits

    always_ff @(posedge clk) begin
        if (reset || clear) begin
            acc <= 32'sd0;
        end else if (enable) begin
            acc <= acc + product_extended;
        end
    end

endmodule

`default_nettype wire
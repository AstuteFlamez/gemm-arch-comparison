`timescale 1ns/1ps
`default_nettype none

module mac (
    input  logic clk,
    input  logic reset,
    input  logic enable,

    input  logic signed [7:0] a,
    input  logic signed [7:0] b,

    output logic signed [31:0] acc
);

    logic signed [15:0] product;
    logic signed [31:0] product_extended;

    // 8bit + 8 bit = 9bit

    // 16-bit = 8-bit * 8-bit
    assign product = a * b;
    // DECIMAL 3 * 3 = 9
    // BINARY 011 * 011;  (- 2^7) * (- 2^7) =

    // Sign extend to 16-bit
    assign product_extended = {{16{product[15]}}, product};

    always_ff @(posedge clk) begin
        if (reset) begin
            acc <= 32'sd0;
        end else if (enable) begin
            acc <= acc + product_extended;
        end
    end

endmodule

`default_nettype wire

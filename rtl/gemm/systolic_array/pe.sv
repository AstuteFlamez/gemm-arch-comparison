`timescale 1ns/1ps
`default_nettype none

module pe (
    input  logic clk,
    input  logic reset,
    input  logic enable,

    // Receive operands from the left and above
    input  logic signed [7:0] a_in,
    input  logic signed [7:0] b_in,

    // Forward operands to the right and below
    output logic signed [7:0] a_out,
    output logic signed [7:0] b_out,

    // accumulator from MAC
    output logic signed [31:0] acc
);

    mac mac_inst (
        .clk(clk),
        .reset(reset),
        .enable(enable),

        .a(a_in),
        .b(b_in),
        .acc(acc)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            a_out <= 0;
            b_out <= 0;
        end else if (enable) begin
            a_out <= a_in;
            b_out <= b_in;
        end
    end

endmodule

`default_nettype wire

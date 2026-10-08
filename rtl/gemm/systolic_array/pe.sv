`timescale 1ns/1ps
`default_nettype none

// One signed MAC plus one enabled clock of A/B forwarding.
// Synchronous active-high rst/clr clear the accumulator and forwarded operands.
// Priority is rst > clr > enable; clr discards all state from the previous tile.
module pe (
    input  logic clk,
    input  logic rst,
    input  logic clr,
    input  logic enable,

    // Receive operands from the left and above
    input  logic signed [7:0] a_in,
    input  logic signed [7:0] b_in,

    // Forward operands to the right and below
    output logic signed [7:0] a_out,
    output logic signed [7:0] b_out,

    // Accumulated result for this PE's output element
    output logic signed [31:0] acc
);

    mac u_mac (
        .clk(clk),
        .rst(rst),
        .clr(clr),
        .enable(enable),

        .a(a_in),
        .b(b_in),
        .acc(acc)
    );

    // Forward operands on the same enabled edge that consumes them locally.
    // Pausing enable holds both the forwarded operands and the accumulator.
    always_ff @(posedge clk) begin
        if (rst) begin
            a_out <= '0;
            b_out <= '0;
        end else if (clr) begin
            a_out <= '0;
            b_out <= '0;
        end else if (enable) begin
            a_out <= a_in;
            b_out <= b_in;
        end
    end

endmodule

`default_nettype wire

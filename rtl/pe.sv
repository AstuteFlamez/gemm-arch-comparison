`timescale 1ns/1ps
`default_nettype none

module pe (
    // Control Signals
    input  logic               clk,
    input  logic               reset,
    input  logic               clear,

    input  logic signed [7:0]  a_in,
    input  logic signed [7:0]  b_in,
    output logic signed [7:0]  a_out,
    output logic signed [7:0]  b_out,

    // Prevent the PE from multiplying stale data
    // when no new pair of operands is ready
    input  logic               a_valid_in,
    input  logic               b_valid_in,
    output logic               a_valid_out,
    output logic               b_valid_out,

    output logic signed [31:0] acc
);

    mac mac_inst (
        .clk    (clk),
        .reset  (reset),
        .clear  (clear),
        .enable (a_valid_in && b_valid_in),
        .a      (a_in),
        .b      (b_in),
        .acc    (acc)
    );

    always_ff @(posedge clk) begin
        if (reset || clear) begin
            a_out       <= 0;
            b_out       <= 0;
            a_valid_out <= 0;
            b_valid_out <= 0;
        end else begin
            a_out       <= a_in;
            b_out       <= b_in;
            a_valid_out <= a_valid_in;
            b_valid_out <= b_valid_in;
        end
    end

endmodule

`default_nettype wire

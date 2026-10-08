`timescale 1ns/1ps
`default_nettype none

// Single-port synchronous memory with write priority and no reset.
// DATA_WIDTH >= 1 and DEPTH >= 2; addr is an element index, not a byte address.
// Disabled reads hold rd_data; unwritten memory contents are unspecified.
module sram #(
    parameter int DATA_WIDTH = 8, // Bits per element
    parameter int DEPTH = 64      // Number of elements
) (
    input  logic clk,

    input  logic re,
    input  logic we,

    // Shared address and data
    input  logic [$clog2(DEPTH) - 1:0] addr,
    input  logic [DATA_WIDTH - 1:0] wr_data,
    output logic [DATA_WIDTH - 1:0] rd_data
);

    // DEPTH entries, each DATA_WIDTH bits wide
    logic unsigned [DATA_WIDTH - 1:0] storage_q [0:DEPTH - 1];

    // Writes take priority over reads. A write or disabled read leaves the
    // previous rd_data value intact; this memory has no reset operation.
    always_ff @(posedge clk) begin
        if (we) begin
            storage_q[addr] <= wr_data;
        end else if (re) begin
            rd_data <= storage_q[addr];
        end
    end

endmodule

`default_nettype wire

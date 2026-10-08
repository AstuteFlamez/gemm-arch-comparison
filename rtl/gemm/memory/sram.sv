`timescale 1ns/1ps
`default_nettype none

module sram #(
    parameter int DATA_WIDTH = 8, // Bits per element
    parameter int DEPTH = 64      // # of elements
) (
    input  logic clk,

    input  logic re,
    input  logic we,

    // Shared address and data
    input  logic [$clog2(DEPTH)-1:0] addr,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic [DATA_WIDTH-1:0] rdata
);

    // DEPTH entries, each DATA_WIDTH bits wide
    logic unsigned [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (we) begin
            mem[addr] <= wdata; // Write at the rising edge
        end else if (re) begin
            rdata <= mem[addr]; // Read data updates after the rising edge
        end
    end

endmodule

`default_nettype wire

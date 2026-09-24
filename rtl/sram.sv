`timescale 1ns/1ps
`default_nettype none

module sram 
    #(
        parameter int DATA_WIDTH = 8, // bits per element; DEFAULT=8
        parameter int DEPTH = 64      // number of elements; DEFAULT = 64
    )
    (
    input  logic clk,
    input  logic re,
    input  logic we,
    input  logic [$clog2(DEPTH)-1: 0] addr, // selects one of DEPTH elements
    input  logic [DATA_WIDTH-1: 0] wdata,   // one DATA_WIDTH-bit value to write
    output logic [DATA_WIDTH-1: 0] rdata    // one DATA_WIDTH-bit value to read
);

    logic unsigned [DATA_WIDTH-1:0] mem [0:DEPTH-1]; // STORAGE: DEPTH elements each DATA_WIDTH wide

    always_ff @(posedge clk) begin
        if (we) begin
            mem[addr] <= wdata; // write at rising clock edge, write has priority
        end else if (re) begin
            rdata <= mem[addr]; // read at rising clock edge when write enable is LOW
        end
    end

endmodule

`default_nettype wire
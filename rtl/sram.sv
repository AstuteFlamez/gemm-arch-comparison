`timescale 1ns/1ps
`default_nettype none

module sram 
    #(
        parameter int DATA_WIDTH = 8,
        parameter int DEPTH = 64
    )
    (
    input  logic clk,
    input  logic re,
    input  logic we,
    input  logic [$clog2(DEPTH)-1: 0] addr,
    input  logic [DATA_WIDTH-1: 0] wdata,
    output logic [DATA_WIDTH-1: 0] rdata
);

    logic unsigned [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (we) begin
            mem[addr] <= wdata;
        end else if (re) begin
            rdata <= mem[addr];
        end
    end

endmodule

`default_nettype wire
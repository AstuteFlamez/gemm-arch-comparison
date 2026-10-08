`timescale 1ns/1ps
`default_nettype none

module fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH = 8
) (
    input  logic clk, reset,

    // Request a push or pop
    input  logic push,
    input  logic pop,

    // Pop updates data_out; otherwise it holds the previous value
    input  logic [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out,

    // Occupancy flags
    output logic full,
    output logic empty
);

    localparam int PTR_WIDTH   = $clog2(DEPTH);
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);

    // Storage, next write/read positions, and number of occupied entries
    logic [DATA_WIDTH-1:0] storage [0:DEPTH-1];
    logic [PTR_WIDTH-1:0] wr_ptr;
    logic [PTR_WIDTH-1:0] re_ptr;
    logic [COUNT_WIDTH-1:0] occupancy_count;
    logic push_accept, pop_accept;

    assign full  = (occupancy_count == DEPTH);
    assign empty = (occupancy_count == 0);

    // Ignore pushes when full and pops when empty
    assign push_accept = push && !full;
    assign pop_accept  = pop && !empty;

    always_ff @(posedge clk) begin
        if (reset) begin
            wr_ptr          <= 0;
            re_ptr          <= 0;
            occupancy_count <= 0;
            data_out        <= 0;
        end else begin
            if (push_accept) begin
                storage[wr_ptr] <= data_in;
                wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1; // Wrap write pointer
            end

            if (pop_accept) begin
                data_out <= storage[re_ptr];
                re_ptr <= (re_ptr == DEPTH-1) ? '0 : re_ptr + 1; // Wrap read pointer
            end

            case ({push_accept, pop_accept})
                2'b10: occupancy_count <= occupancy_count + 1;
                2'b01: occupancy_count <= occupancy_count - 1;
            endcase
        end
    end

endmodule

`default_nettype wire

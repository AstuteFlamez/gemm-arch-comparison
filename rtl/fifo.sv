`timescale 1ns/1ps
`default_nettype none

module fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH = 8
)
(
    input  logic clk, reset, 
    input  logic push,            // request to add data_in
    input  logic pop,             // request to remove oldest entry
    input  logic [DATA_WIDTH-1:0] data_in,   // DATA_WIDTH-bit data to enqueue
    output logic [DATA_WIDTH-1:0] data_out, // updates with removed entry after pop, otherwise holds
    output logic full,           // high when all entries are occupied
    output logic empty           // high when 0 entries are occupied
);


    localparam int PTR_WIDTH = $clog2(DEPTH);
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);

    logic [DATA_WIDTH-1:0] storage [0:DEPTH-1]; // DEPTH DATA_WIDTH-bit entries
    logic [PTR_WIDTH-1:0] wr_ptr;               // selects where next accepted push writes
    logic [PTR_WIDTH-1:0] re_ptr;               // selects where next accepted pop reads
    logic [COUNT_WIDTH-1:0] occupancy_count;    // must represent COUNT_WIDTH-bits
    logic push_accept, pop_accept;

    assign full = (occupancy_count == DEPTH);
    assign empty = (occupancy_count == 0);
    assign push_accept = push && !full;
    assign pop_accept = pop && !empty;

    always_ff @(posedge clk) begin
        if (reset) begin
            wr_ptr <= 0;
            re_ptr <= 0;
            occupancy_count <= 0;
            data_out <= 0;
        end else begin
            if (push_accept) begin
                storage[wr_ptr] <= data_in;
                wr_ptr <= (wr_ptr == DEPTH-1) ? '0 : wr_ptr + 1; // wrap write pointer
            end
            if (pop_accept) begin
                data_out <= storage[re_ptr];
                re_ptr <= (re_ptr == DEPTH-1) ? '0 : re_ptr + 1; // wrap read pointer
            end
            case ({push_accept, pop_accept})
                2'b10: occupancy_count <= occupancy_count + 1;
                2'b01: occupancy_count <= occupancy_count - 1;
            endcase
        end
    end

endmodule

`default_nettype wire

/*
TODO: parametrize width and depth. Wrap pointers at DEPTH-1
*/
`timescale 1ns/1ps
`default_nettype none

module fifo (
    input logic clk, reset, 
    input logic push,            // request to add data_in
    input logic pop,             // request to remove oldest entry
    input logic [7:0] data_in,   // 8-bit data to enqueue
    output logic [7:0] data_out, // updates with removed entry after pop, otherwise holds
    output logic full,           // high when all 4 entries are occupied
    output logic empty           // high when 0 entries are occupied
);

    logic [7:0] storage [0:3];   // 4 8-bit entries
    logic [1:0] wr_ptr;   // selects where next accepted push writes
    logic [1:0] re_ptr;    // selects where next accepted pop reads
    logic [2:0] occupancy_count; // must represent 0-4 (3-bit)
    logic push_accept, pop_accept;

    assign full = (occupancy_count == 4);
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
                wr_ptr <= wr_ptr + 1;
            end
            if (pop_accept) begin
                data_out <= storage[re_ptr];
                re_ptr <= re_ptr + 1;
            end
            case ({push_accept, pop_accept})
                2'b10: occupancy_count <= occupancy_count + 1;
                2'b01: occupancy_count <= occupancy_count - 1;
            endcase
        end
    end

endmodule

`default_nettype wire

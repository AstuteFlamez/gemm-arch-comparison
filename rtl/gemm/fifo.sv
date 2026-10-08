`timescale 1ns/1ps
`default_nettype none

// Single-clock FIFO: synchronous active-high reset discards buffered data.
// DATA_WIDTH >= 1 and DEPTH >= 2; the pointer width uses $clog2(DEPTH).
// Full pushes and empty pops are ignored. Accepted pops update data_out after the edge.
module fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH = 8
) (
    input  logic clk,
    input  logic rst,

    // Request a push or pop
    input  logic push,
    input  logic pop,

    // Pop updates data_out; otherwise it holds the previous value
    input  logic [DATA_WIDTH - 1:0] data_in,
    output logic [DATA_WIDTH - 1:0] data_out,

    // Occupancy flags
    output logic full,
    output logic empty
);

    localparam int LAST_ENTRY  = DEPTH - 1;
    localparam int PTR_WIDTH   = $clog2(DEPTH);
    localparam int COUNT_WIDTH = $clog2(DEPTH + 1);

    // Storage, next write/read positions, and number of occupied entries
    logic [DATA_WIDTH - 1:0] storage_q [0:DEPTH - 1];
    logic [PTR_WIDTH - 1:0] wr_ptr_q;
    logic [PTR_WIDTH - 1:0] rd_ptr_q;
    logic [COUNT_WIDTH - 1:0] occupancy_q;
    logic push_accept;
    logic pop_accept;

    assign full  = (occupancy_q == DEPTH);
    assign empty = (occupancy_q == '0);

    // Accept requests using the occupancy before this clock edge. A full FIFO
    // rejects a push even if a pop is requested on the same edge.
    assign push_accept = push && !full;
    assign pop_accept  = pop && !empty;

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_ptr_q    <= '0;
            rd_ptr_q    <= '0;
            occupancy_q <= '0;
            data_out    <= '0;
        end else begin
            if (push_accept) begin
                storage_q[wr_ptr_q] <= data_in;
                // Wrap explicitly so non-power-of-two depths also work.
                wr_ptr_q <= (wr_ptr_q == LAST_ENTRY) ? '0 : wr_ptr_q + 1'b1;
            end

            if (pop_accept) begin
                data_out <= storage_q[rd_ptr_q];
                rd_ptr_q <= (rd_ptr_q == LAST_ENTRY) ? '0 : rd_ptr_q + 1'b1;
            end

            // Occupancy holds when both requests, or neither request, succeed.
            case ({push_accept, pop_accept})
                2'b10: begin
                    occupancy_q <= occupancy_q + 1'b1;
                end
                2'b01: begin
                    occupancy_q <= occupancy_q - 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire

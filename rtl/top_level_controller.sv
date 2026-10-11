`timescale 1ns/1ps
`default_nettype none

// One MatrixDim x MatrixDim job at a time, sequenced as 2x2 tiles on clk.
// Supported compile-time matrix dimensions: 8, 16, and 32.
// Synchronous active-high reset aborts the job. Starts while busy are ignored.
// Each tile_start lasts one cycle; tile_done completes the outstanding tile.
module top_level_controller #(
    parameter int MatrixDim = 8
) (
    input  logic clk,
    input  logic rst,

    // Accept a full GEMM request while idle. Done stays high after the
    // final tile until reset or the next accepted start.
    input  logic start,
    output logic busy,
    output logic done,

    // Request one tile from either tile controller and wait for its completion
    input  logic tile_done,
    output logic tile_start,
    output logic [$clog2(MatrixDim) - 1:0] tile_row,
    output logic [$clog2(MatrixDim) - 1:0] tile_col
);

    localparam int TILE_DIM         = 2;
    localparam int TILES_PER_DIM    = MatrixDim / TILE_DIM;
    localparam int TILE_AXIS_WIDTH  = $clog2(TILES_PER_DIM);
    localparam int TILE_INDEX_WIDTH = $clog2(TILES_PER_DIM * TILES_PER_DIM);
    localparam int LAST_TILE_INDEX  = TILES_PER_DIM * TILES_PER_DIM - 1;

    typedef enum logic [1:0] {
        IDLE,
        START_TILE,
        WAIT_TILE
    } state_e;
    state_e state_q;

    logic [TILE_INDEX_WIDTH - 1:0] tile_index_q; // Row-major output tile index

    // synthesis translate_off
    initial begin
        if (MatrixDim != 8 && MatrixDim != 16 && MatrixDim != 32) begin
            $fatal(1, "top_level_controller: MatrixDim must be 8, 16, or 32");
        end
    end
    // synthesis translate_on

    // Each tile covers two rows and two columns, so base coordinates are even.
    assign tile_row = {tile_index_q[TILE_INDEX_WIDTH - 1:TILE_AXIS_WIDTH], 1'b0};
    assign tile_col = {tile_index_q[TILE_AXIS_WIDTH - 1:0], 1'b0};

    assign busy       = (state_q != IDLE);
    assign tile_start = !rst && (state_q == START_TILE);

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q      <= IDLE;
            tile_index_q <= '0;
            done         <= '0;
        end else begin
            case (state_q)
                IDLE: begin
                    if (start) begin
                        tile_index_q <= '0;
                        done         <= '0;
                        state_q      <= START_TILE;
                    end
                end

                START_TILE: begin
                    state_q <= WAIT_TILE;
                end

                WAIT_TILE: begin
                    if (tile_done) begin
                        if (tile_index_q == LAST_TILE_INDEX) begin
                            done    <= 1'b1;
                            state_q <= IDLE;
                        end else begin
                            // Advance across each tile row, then move down two rows.
                            tile_index_q <= tile_index_q + 1'b1;
                            state_q      <= START_TILE;
                        end
                    end
                end

                default: begin
                    state_q <= IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire

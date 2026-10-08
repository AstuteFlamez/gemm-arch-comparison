`timescale 1ns/1ps
`default_nettype none

module top_level_controller (
    input logic clk, reset,

    // Start one full 8×8 GEMM.
    input  logic start,
    output logic busy,
    output logic done,

    // Request one tile from memory_controller and wait for its completion
    input  logic tile_done,
    output logic tile_start,
    output logic [2:0] tile_row, tile_col
);

    typedef enum logic [1:0] {
        IDLE,
        START_TILE,
        WAIT_TILE
    } state_t;
    state_t state;

    logic [3:0] tile_index; // tiles 0–15: four across, advance to next row

    assign tile_row = {tile_index[3:2], 1'b0};
    assign tile_col = {tile_index[1:0], 1'b0};

    assign busy = (state != IDLE);
    assign tile_start = !reset && (state == START_TILE);

    always_ff @(posedge clk) begin
        if (reset) begin
            state      <= IDLE;
            tile_index <= 0;
            done       <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        tile_index <= 0;
                        done       <= 0;
                        state      <= START_TILE;
                    end
                end

                START_TILE: begin
                    state <= WAIT_TILE;
                end

                WAIT_TILE: begin
                    if (tile_done) begin
                        if (tile_index == 15) begin
                            done  <= 1;
                            state <= IDLE;
                        end else begin
                            // Advance (0,0) -> (0,2) -> ... -> (6,6)
                            tile_index <= tile_index + 1;
                            state      <= START_TILE;
                        end
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire

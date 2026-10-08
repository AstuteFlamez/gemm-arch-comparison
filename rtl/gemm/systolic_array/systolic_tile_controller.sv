`timescale 1ns/1ps
`default_nettype none

// Fixed 2x2 tile schedule on clk with synchronous active-high reset.
// Start is accepted only in IDLE; tile_row/tile_col must be even bases in 0..6.
// SRAM reads and FIFO pops are registered; done pulses after all four C writes.
// Global reset must also clear the attached FIFOs and datapath when aborting a tile.
module systolic_tile_controller (
    input  logic clk,
    input  logic rst,

    // Request one 2×2 output tile
    input  logic start,
    input  logic [2:0] tile_row,
    input  logic [2:0] tile_col,
    output logic done, // 1-cycle pulse after STORE

    // Read A/B SRAMs
    output logic ab_re,
    output logic [5:0] a_rd_addr,
    output logic [5:0] b_rd_addr,

    // Bit 0 controls A0/B0; bit 1 controls A1/B1; 11 enables both pairs
    output logic [1:0] fifo_push,
    output logic [1:0] fifo_pop,
    output logic [1:0] fifo_valid,

    // Control the array
    output logic array_clr,
    output logic array_enable,

    // Write one of the four results to C SRAM
    output logic c_we,
    output logic [5:0] c_wr_addr,
    output logic [1:0] c_sel
);

    localparam int MATRIX_DIM      = 8;
    localparam int TILE_DIM        = 2;
    localparam int TILE_OUTPUTS    = TILE_DIM * TILE_DIM;
    localparam int LOAD_LAST_CYCLE = TILE_DIM * MATRIX_DIM;
    // Two forwarding edges are needed to reach the bottom-right PE.
    localparam int COMPUTE_LAST_CYCLE = MATRIX_DIM + 2;
    localparam int STORE_LAST_CYCLE   = TILE_OUTPUTS - 1;

    typedef enum logic [2:0] {
        IDLE,
        LOAD_FIFO,
        COMPUTE_ARRAY,
        STORE,
        FINISH
    } state_e;
    state_e state_q;

    logic [4:0] phase_cycle_q; // LOAD_FIFO 0–16, COMPUTE_ARRAY 0–10, STORE 0–3
    logic [2:0] tile_row_q;
    logic [2:0] tile_col_q;

    // Capture the tile coordinates once; later input changes do not affect this tile.
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q       <= IDLE;
            phase_cycle_q <= '0;
            tile_row_q    <= '0;
            tile_col_q    <= '0;
        end else begin
            case (state_q)
                IDLE: begin
                    if (start) begin
                        tile_row_q    <= tile_row;
                        tile_col_q    <= tile_col;
                        phase_cycle_q <= '0;
                        state_q       <= LOAD_FIFO;
                    end
                end

                LOAD_FIFO: begin
                    if (phase_cycle_q == LOAD_LAST_CYCLE) begin
                        phase_cycle_q <= '0;
                        state_q       <= COMPUTE_ARRAY;
                    end else begin
                        phase_cycle_q <= phase_cycle_q + 1'b1;
                    end
                end

                COMPUTE_ARRAY: begin
                    if (phase_cycle_q == COMPUTE_LAST_CYCLE) begin
                        phase_cycle_q <= '0;
                        state_q       <= STORE;
                    end else begin
                        phase_cycle_q <= phase_cycle_q + 1'b1;
                    end
                end

                STORE: begin
                    if (phase_cycle_q == STORE_LAST_CYCLE) begin
                        state_q <= FINISH;
                    end else begin
                        phase_cycle_q <= phase_cycle_q + 1'b1;
                    end
                end

                FINISH: begin
                    // Spend one clock cycle with done high, then return to IDLE.
                    state_q <= IDLE;
                end

                default: begin
                    state_q <= IDLE;
                end
            endcase
        end
    end

    always_comb begin
        // During LOAD_FIFO, bit 3 selects the pair; bits 2:0 select element 0–7.
        // Legal tile bases keep the address calculations within the 6-bit ports.
        a_rd_addr = (tile_row_q + phase_cycle_q[3]) * MATRIX_DIM + phase_cycle_q[2:0];
        b_rd_addr = phase_cycle_q[2:0] * MATRIX_DIM + tile_col_q + phase_cycle_q[3];

        // Disable all operations unless the current phase explicitly enables them.
        ab_re        = '0;
        fifo_push    = '0;
        fifo_pop     = '0;
        fifo_valid   = '0;
        array_clr    = '0;
        array_enable = '0;
        c_we         = '0;
        c_wr_addr    = '0;
        c_sel        = '0;
        done         = '0;

        if (!rst) begin
            case (state_q)
                LOAD_FIFO: begin
                    /*
                    Cycle 0: Read the first A0/B0 values from SRAM. No push yet.
                    Also clear the array.

                    Cycle 1: Push those first values into A0/B0's FIFOs while
                    reading their second values.

                    Cycles 2–7: Continue reading the next A0/B0 values and
                    pushing the previous ones.

                    Cycle 8: Push A0/B0's last values while reading A1/B1's
                    first values.

                    Cycles 9–15: Continue loading A1/B1 by reading the next
                    values and pushing the previous ones.

                    Cycle 16: Push A1/B1's last values. No new read. All four
                    FIFOs are full, so enter COMPUTE_ARRAY cycle 0.

                    The array stays disabled throughout loading.
                    */
                    array_clr = (phase_cycle_q == '0);
                    ab_re       = (phase_cycle_q < LOAD_LAST_CYCLE);

                    if (phase_cycle_q >= 5'd1 && phase_cycle_q <= MATRIX_DIM) begin
                        fifo_push[0] = 1'b1;
                    end
                    if (phase_cycle_q >= MATRIX_DIM + 1 && phase_cycle_q <= LOAD_LAST_CYCLE) begin
                        fifo_push[1] = 1'b1;
                    end
                end

                COMPUTE_ARRAY: begin
                    /*
                    Cycle 0: Pop the first A0/B0 values. Keep the array disabled
                    while the FIFO outputs update.

                    Cycle 1: Feed those first A0/B0 values into the array while
                    popping their next values and A1/B1's first values.
                    The A1/B1 array inputs are still zero.

                    Cycles 2–7: Feed both pairs into the array while popping
                    their next values. A1/B1 stay one element behind A0/B0 so
                    matching values meet as A moves right and B moves down.

                    Cycle 8: Feed A0/B0's last values and A1/B1's second-to-last
                    values. Stop popping A0/B0; pop A1/B1's last values.
                    C00 finishes its calculation.

                    Cycle 9: Feed A1/B1's last values. A0/B0 inputs are zero.
                    No more pops. C01 and C10 finish their calculations.

                    Cycle 10: Feed zeros into all four array inputs, but keep
                    the array enabled so C11 can finish using the last values
                    from its neighbors. Then enter STORE cycle 0.
                    */
                    fifo_pop[0] = (phase_cycle_q < MATRIX_DIM);
                    fifo_pop[1] = (phase_cycle_q >= 5'd1 && phase_cycle_q <= MATRIX_DIM);

                    fifo_valid[0] = (phase_cycle_q >= 5'd1 && phase_cycle_q <= MATRIX_DIM);
                    fifo_valid[1] = (phase_cycle_q >= 5'd2 && phase_cycle_q <= MATRIX_DIM + 1);

                    array_enable = (phase_cycle_q >= 5'd1);
                end

                STORE: begin
                    /*
                    Keep the array disabled so its four results hold steady.

                    Here r = tile_row_q and c = tile_col_q.

                    Cycle 0: Write C00 to C[r][c].
                    Cycle 1: Write C01 to C[r][c + 1].
                    Cycle 2: Write C10 to C[r + 1][c].
                    Cycle 3: Write C11 to C[r + 1][c + 1].
                    All four results are stored, so enter FINISH.
                    */
                    c_we      = 1'b1;
                    c_sel     = phase_cycle_q[1:0];
                    c_wr_addr = (tile_row_q + phase_cycle_q[1]) * MATRIX_DIM
                        + tile_col_q + phase_cycle_q[0];
                end

                FINISH: begin
                    // Single cycle: raise done to announce the tile is finished.
                    done = 1'b1;
                end

                default: begin
                    // Keep the defaults above
                end
            endcase
        end
    end

endmodule

`default_nettype wire

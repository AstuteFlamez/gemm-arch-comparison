module systolic_tile_controller (
    input logic clk, reset,

    // Request one 2×2 output tile
    input  logic start,
    input  logic [2:0] tile_row, tile_col,
    output logic done, // 1-cycle pulse after STORE

    // Read A/B SRAMs
    output logic ab_re,
    output logic [5:0] a_rd_addr, b_rd_addr,

    // Bit 0 controls A0/B0; bit 1 controls A1/B1; 11 enables both pairs
    output logic [1:0] fifo_push,
    output logic [1:0] fifo_pop,
    output logic [1:0] fifo_valid,

    // Control the array
    output logic array_clear,
    output logic array_enable,

    // Write one of the four results to C SRAM
    output logic c_we,
    output logic [5:0] c_wr_addr,
    output logic [1:0] c_sel
);

    typedef enum logic [2:0] {
        IDLE,
        LOAD_FIFO,
        COMPUTE_SYSTOLIC_ARRAY,
        STORE,
        FINISH
    } state_t;
    state_t state;

    logic [4:0] cycle;      // LOAD_FIFO 0–16, COMPUTE_SYSTOLIC_ARRAY 0–10, STORE 0–3
    logic [2:0] row_base, col_base;        

    always_ff @(posedge clk) begin
        if (reset) begin
            state    <= IDLE;
            cycle    <= 0;
            row_base <= 0;
            col_base <= 0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        row_base <= tile_row;
                        col_base <= tile_col;
                        cycle    <= 0;
                        state    <= LOAD_FIFO;
                    end
                end

                LOAD_FIFO: begin
                    if (cycle == 16) begin
                        cycle <= 0;
                        state <= COMPUTE_SYSTOLIC_ARRAY;
                    end else begin
                        cycle <= cycle + 1;
                    end
                end

                COMPUTE_SYSTOLIC_ARRAY: begin
                    if (cycle == 10) begin
                        cycle <= 0;
                        state <= STORE;
                    end else begin
                        cycle <= cycle + 1;
                    end
                end

                STORE: begin
                    if (cycle == 3)
                        state <= FINISH;
                    else
                        cycle <= cycle + 1;
                end

                FINISH: begin
                    // Spend one clock cycle with done high, then return to IDLE.
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    always_comb begin
        // During LOAD_FIFO, bit 3 selects the pair; bits 2:0 select element 0–7
        a_rd_addr = (row_base + cycle[3]) * 8 + cycle[2:0];
        b_rd_addr = cycle[2:0] * 8 + col_base + cycle[3];

        // Default:
        {ab_re, fifo_push, fifo_pop, fifo_valid, array_clear,
         array_enable, c_we, c_wr_addr, c_sel, done} = 0;

        if (!reset) begin
            case (state)
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
                    FIFOs are full, so enter COMPUTE_SYSTOLIC_ARRAY cycle 0.

                    The array stays disabled throughout loading.
                    */
                    array_clear = (cycle == 0);
                    ab_re = (cycle < 16);

                    if (cycle >= 1 && cycle <= 8)
                        fifo_push[0] = 1;
                    if (cycle >= 9 && cycle <= 16)
                        fifo_push[1] = 1;
                end

                COMPUTE_SYSTOLIC_ARRAY: begin
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
                    fifo_pop[0] = (cycle < 8);
                    fifo_pop[1] = (cycle >= 1 && cycle <= 8);

                    fifo_valid[0] = (cycle >= 1 && cycle <= 8);
                    fifo_valid[1] = (cycle >= 2 && cycle <= 9);

                    array_enable = (cycle >= 1);
                end

                STORE: begin
                    /*
                    Keep the array disabled so its four results hold steady.

                    Cycle 0: Write C00 to C[row_base][col_base].
                    Cycle 1: Write C01 to C[row_base][col_base + 1].
                    Cycle 2: Write C10 to C[row_base + 1][col_base].
                    Cycle 3: Write C11 to C[row_base + 1][col_base + 1].
                    All four results are stored, so enter FINISH.
                    */
                    c_we = 1;
                    c_sel = cycle[1:0];
                    c_wr_addr = (row_base + cycle[1]) * 8 + col_base + cycle[0];
                end

                FINISH: begin
                    // Single cycle: raise done to announce the tile is finished.
                    done = 1;
                end

                default: begin
                    // Keep the defaults above
                end
            endcase
        end
    end

endmodule

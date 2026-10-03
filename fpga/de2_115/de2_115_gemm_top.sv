`timescale 1ns/1ps
`default_nettype none

/*

    THIS FILE WAS WRITTEN BY AI!!! -Bilal

*/

// Board wrapper for the personal GEMM project. KEY0 resets; KEY1 runs one test.
module de2_115_gemm_top (
    input  logic CLOCK_50,
    input  logic [1:0] KEY,
    output logic LED_READY,
    output logic LED_BUSY,
    output logic LED_PASS,
    output logic LED_FAIL
);
    // Quartus implements this initial value at configuration time. KEY0 can
    // also assert reset immediately; release passes through two clock edges.
    (* preserve *) logic [1:0] reset_pipe = 2'b11;
    logic reset;
    assign reset = reset_pipe[1];
    always_ff @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0])
            reset_pipe <= 2'b11;
        else
            reset_pipe <= {reset_pipe[0], 1'b0};
    end

    // DE2-115 buttons are debounced on the board, but remain asynchronous to
    // CLOCK_50. Synchronize KEY1, then make one pulse when it goes low.
    (* preserve *) logic start_meta, start_sync;
    logic start_previous, start_pressed;
    always_ff @(posedge CLOCK_50) begin
        if (reset) begin
            start_meta <= 1;
            start_sync <= 1;
            start_previous <= 1;
        end else begin
            start_meta <= KEY[1];
            start_sync <= start_meta;
            start_previous <= start_sync;
        end
    end
    assign start_pressed = start_previous && !start_sync;

    typedef enum logic [3:0] {
        IDLE, RESET_CORE, LOAD, START_CORE, WAIT_CORE,
        READ_C, CHECK_C, PASS, FAIL
    } state_t;
    state_t state;
    logic [5:0] word_index;
    logic [11:0] wait_cycles;
    logic core_reset, core_start, core_busy, core_done, load_we;
    logic signed [7:0] a_value, b_value;
    logic signed [31:0] c_value;

    // Row-major inputs: A contains -32..31 and B contains 31..-32.
    // The expected file contains 64 independently calculated signed C words.
    logic signed [31:0] expected [0:63];
    initial $readmemh("expected.hex", expected);
    assign a_value = $signed({2'b00, word_index}) - 8'sd32;
    assign b_value = 8'sd31 - $signed({2'b00, word_index});
    assign load_we = !reset && (state == LOAD);
    assign core_start = !reset && (state == START_CORE);
    assign core_reset = reset || (state == RESET_CORE) || (state == FAIL);

    gemm core (
        .clk(CLOCK_50), .reset(core_reset),
        .a_we(load_we), .a_wr_addr(word_index), .a_wdata(a_value),
        .b_we(load_we), .b_wr_addr(word_index), .b_wdata(b_value),
        .start(core_start), .busy(core_busy), .done(core_done),
        .c_rd_addr(word_index), .c_rd_data(c_value)
    );

    assign LED_READY = !reset && (state == IDLE || state == PASS || state == FAIL);
    assign LED_BUSY = !reset && !LED_READY;
    assign LED_PASS = !reset && (state == PASS);
    assign LED_FAIL = !reset && (state == FAIL);

    always_ff @(posedge CLOCK_50) begin
        if (reset) begin
            state <= IDLE;
            word_index <= 0;
            wait_cycles <= 0;
        end else begin
            case (state)
                IDLE, PASS, FAIL: begin
                    // Result LEDs hold until reset or another button press.
                    if (start_pressed)
                        state <= RESET_CORE;
                end

                RESET_CORE: begin
                    // One edge resets the GEMM controllers, FIFOs, and array.
                    word_index <= 0;
                    wait_cycles <= 0;
                    state <= LOAD;
                end

                LOAD: begin
                    // Cycles 0-63: write one A word and one B word per edge.
                    if (word_index == 63) begin
                        word_index <= 0;
                        state <= START_CORE;
                    end else
                        word_index <= word_index + 1;
                end

                START_CORE: begin
                    // One edge accepts start. The GEMM now owns its memories.
                    state <= WAIT_CORE;
                end

                WAIT_CORE: begin
                    // Normally 544 GEMM work clocks, then observe done.
                    // A stalled core gets a red FAIL instead of waiting forever.
                    if (core_done && !core_busy)
                        state <= READ_C;
                    else if (wait_cycles == 4095)
                        state <= FAIL;
                    else
                        wait_cycles <= wait_cycles + 1;
                end

                READ_C: begin
                    // This edge requests C[word_index]; SRAM updates afterward.
                    state <= CHECK_C;
                end

                CHECK_C: begin
                    // This edge sees the result of the preceding read edge.
                    if (c_value == expected[word_index]) begin
                        if (word_index == 63)
                            state <= PASS;
                        else begin
                            word_index <= word_index + 1;
                            state <= READ_C;
                        end
                    end else
                        state <= FAIL;
                end

                default: state <= FAIL;
            endcase
        end
    end
endmodule

`default_nettype wire

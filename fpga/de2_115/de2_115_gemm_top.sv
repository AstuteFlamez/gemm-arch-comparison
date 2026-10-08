`timescale 1ns/1ps
`default_nettype none

/*

    THIS FILE WAS WRITTEN BY AI!!! -Bilal

*/

// KEY0 resets; KEY1 runs the complete directed + seeded-random matrix suite.
module de2_115_gemm_top (
    input  logic CLOCK_50,
    input  logic [1:0] KEY,
    output logic LED_READY,
    output logic LED_BUSY,
    output logic LED_PASS,
    output logic LED_FAIL
);
    `include "gemm_vectors.svh"
    localparam integer CASE_WIDTH = (CASE_COUNT > 1) ? $clog2(CASE_COUNT) : 1;
    localparam integer VECTOR_WORDS = CASE_COUNT * 64;

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
        IDLE, RESET_CORE, READ_INPUT, LOAD, START_CORE, WAIT_CORE,
        READ_C, CHECK_C, PASS, FAIL
    } state_t;
    state_t state;
    logic [CASE_WIDTH-1:0] case_index;
    logic [5:0] word_index;
    logic [CASE_WIDTH+5:0] vector_address;
    logic [11:0] wait_cycles;
    logic core_reset, core_start, core_busy, core_done, load_we;
    logic signed [7:0] a_value, b_value;
    logic signed [31:0] c_value, expected_value;

    // Case-major ROMs: 64 row-major words per matrix. Python supplies the
    // operands and independent answers; the FPGA performs every multiplication.
    logic signed [7:0] inputs_a [0:VECTOR_WORDS-1];
    logic signed [7:0] inputs_b [0:VECTOR_WORDS-1];
    logic signed [31:0] expected [0:VECTOR_WORDS-1];
    initial begin
        $readmemh("inputs_a.hex", inputs_a);
        $readmemh("inputs_b.hex", inputs_b);
        $readmemh("expected.hex", expected);
    end
    assign vector_address = {case_index, word_index};

    // Registered ROM reads allow Quartus to infer embedded memory. Keep these
    // registers reset-free; the FSM always requests data before consuming it.
    always_ff @(posedge CLOCK_50) begin
        if (state == READ_INPUT) begin
            a_value <= inputs_a[vector_address];
            b_value <= inputs_b[vector_address];
        end
        if (state == READ_C)
            expected_value <= expected[vector_address];
    end
    assign load_we = !reset && (state == LOAD);
    assign core_start = !reset && (state == START_CORE);
    assign core_reset = reset || (state == RESET_CORE) || (state == FAIL);

    systolic_gemm core (
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
            case_index <= 0;
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
                    // Reset once per suite. Consecutive pairs reuse the core
                    // without resetting it, exercising its normal restart path.
                    case_index <= 0;
                    word_index <= 0;
                    wait_cycles <= 0;
                    state <= READ_INPUT;
                end

                READ_INPUT: state <= LOAD;

                LOAD: begin
                    // Consume the preceding ROM read: one A and B word together.
                    // Reading then writing takes two clocks per address.
                    if (word_index == 63) begin
                        word_index <= 0;
                        state <= START_CORE;
                    end else begin
                        word_index <= word_index + 1;
                        state <= READ_INPUT;
                    end
                end

                START_CORE: begin
                    // One edge accepts start. The GEMM now owns its memories.
                    wait_cycles <= 0;
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
                    // Request both C and its expected value; both update after
                    // this edge and are available for the next comparison.
                    state <= CHECK_C;
                end

                CHECK_C: begin
                    // This edge sees the result of the preceding read edge.
                    if (c_value == expected_value) begin
                        if (word_index == 63) begin
                            if (case_index == CASE_COUNT - 1)
                                state <= PASS;
                            else begin
                                case_index <= case_index + 1;
                                word_index <= 0;
                                state <= READ_INPUT;
                            end
                        end else begin
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

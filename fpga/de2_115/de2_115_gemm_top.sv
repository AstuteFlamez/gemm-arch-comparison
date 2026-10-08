`timescale 1ns/1ps
`default_nettype none

/*
    THIS FILE WAS WRITTEN BY AI!!! -Bilal
*/

// KEY0 resets; KEY1 runs the complete directed + seeded-random matrix suite.
// clk is the only compute clock. KEY0 asserts reset asynchronously;
// reset release and KEY1 input cross through two-stage synchronizers.
// Each KEY1 press while ready runs the ROM suite; presses while busy are ignored.
// Reset cancels the suite. A mismatch or timeout latches FAIL until reset or restart.
module de2_115_gemm_top (
    input  logic clk,
    input  logic [1:0] KEY,
    output logic LED_READY,
    output logic LED_BUSY,
    output logic LED_PASS,
    output logic LED_FAIL
);
    `include "gemm_vectors.svh"

    localparam int WORDS_PER_MATRIX             = 64;
    localparam logic [5:0] LAST_WORD_INDEX      = 6'd63;
    localparam logic [11:0] CORE_TIMEOUT_CYCLES = 12'd4095;
    localparam integer CASE_WIDTH               = (CASE_COUNT > 1) ? $clog2(CASE_COUNT) : 1;
    localparam integer VECTOR_WORDS             = CASE_COUNT * WORDS_PER_MATRIX;

    typedef enum logic [3:0] {
        IDLE,
        RESET_CORE,
        READ_INPUT,
        LOAD,
        START_CORE,
        WAIT_CORE,
        READ_C,
        CHECK_C,
        PASS,
        FAIL
    } state_e;
    state_e state_q;

    // Reset and button synchronization.
    (* preserve *) logic [1:0] rst_pipe_q = '1;
    logic rst;
    (* preserve *) logic start_meta_q;
    (* preserve *) logic start_sync_q;
    logic start_previous_q;
    logic start_pressed;

    // Current matrix pair, element, and completion timeout.
    logic [CASE_WIDTH - 1:0] case_index_q;
    logic [5:0] word_index_q;
    logic [CASE_WIDTH + 5:0] vector_address;
    logic [11:0] wait_cycles_q;

    // GEMM controls and registered operand/reference values.
    logic core_rst;
    logic core_start;
    logic core_busy;
    logic core_done;
    logic load_we;
    logic signed [7:0] a_value_q;
    logic signed [7:0] b_value_q;
    logic signed [31:0] c_value;
    logic signed [31:0] expected_value_q;

    // Case-major ROMs: 64 row-major words per matrix. Python supplies the
    // operands and independent answers; the FPGA performs every multiplication.
    logic signed [7:0] inputs_a [0:VECTOR_WORDS - 1];
    logic signed [7:0] inputs_b [0:VECTOR_WORDS - 1];
    logic signed [31:0] expected [0:VECTOR_WORDS - 1];

    // Quartus implements rst_pipe_q's initial value at configuration time.
    // KEY0 asserts reset immediately; release passes through two clock edges.
    assign rst = rst_pipe_q[1];

    always_ff @(posedge clk or negedge KEY[0]) begin
        if (!KEY[0]) begin
            rst_pipe_q <= '1;
        end else begin
            rst_pipe_q <= {rst_pipe_q[0], 1'b0};
        end
    end

    // DE2-115 buttons are debounced on the board, but remain asynchronous to
    // clk. Synchronize KEY1, then make one pulse when it goes low.
    always_ff @(posedge clk) begin
        if (rst) begin
            start_meta_q     <= 1'b1;
            start_sync_q     <= 1'b1;
            start_previous_q <= 1'b1;
        end else begin
            start_meta_q     <= KEY[1];
            start_sync_q     <= start_meta_q;
            start_previous_q <= start_sync_q;
        end
    end

    assign start_pressed = start_previous_q && !start_sync_q;

    initial begin
        $readmemh("inputs_a.hex", inputs_a);
        $readmemh("inputs_b.hex", inputs_b);
        $readmemh("expected.hex", expected);
    end

    assign vector_address = {case_index_q, word_index_q};

    // Registered ROM reads allow Quartus to infer embedded memory. Keep these
    // registers reset-free; the FSM always requests data before consuming it.
    always_ff @(posedge clk) begin
        if (state_q == READ_INPUT) begin
            a_value_q <= inputs_a[vector_address];
            b_value_q <= inputs_b[vector_address];
        end
        if (state_q == READ_C) begin
            expected_value_q <= expected[vector_address];
        end
    end

    // Load and start follow their FSM phases; failures also hold the core in reset.
    assign load_we    = !rst && (state_q == LOAD);
    assign core_start = !rst && (state_q == START_CORE);
    assign core_rst   = rst || (state_q == RESET_CORE) || (state_q == FAIL);

    systolic_gemm u_gemm (
        .clk(clk),
        .rst(core_rst),

        .a_we(load_we),
        .a_wr_addr(word_index_q),
        .a_wdata(a_value_q),

        .b_we(load_we),
        .b_wr_addr(word_index_q),
        .b_wdata(b_value_q),

        .start(core_start),
        .busy(core_busy),
        .done(core_done),

        .c_rd_addr(word_index_q),
        .c_rd_data(c_value)
    );

    // PASS/FAIL remain visible until a new suite starts or reset is asserted.
    assign LED_READY = !rst && (state_q == IDLE || state_q == PASS || state_q == FAIL);
    assign LED_BUSY  = !rst && !LED_READY;
    assign LED_PASS  = !rst && (state_q == PASS);
    assign LED_FAIL  = !rst && (state_q == FAIL);

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q       <= IDLE;
            case_index_q  <= '0;
            word_index_q  <= '0;
            wait_cycles_q <= '0;
        end else begin
            case (state_q)
                IDLE, PASS, FAIL: begin
                    // Result LEDs hold until reset or another button press.
                    if (start_pressed) begin
                        state_q <= RESET_CORE;
                    end
                end

                RESET_CORE: begin
                    // Reset once per suite. Consecutive pairs reuse the core
                    // without resetting it, exercising its normal restart path.
                    case_index_q  <= '0;
                    word_index_q  <= '0;
                    wait_cycles_q <= '0;
                    state_q       <= READ_INPUT;
                end

                READ_INPUT: begin
                    state_q <= LOAD;
                end

                LOAD: begin
                    // Consume the preceding ROM read: one A and B word together.
                    // Reading then writing takes two clocks per address.
                    if (word_index_q == LAST_WORD_INDEX) begin
                        word_index_q <= '0;
                        state_q      <= START_CORE;
                    end else begin
                        word_index_q <= word_index_q + 1'b1;
                        state_q      <= READ_INPUT;
                    end
                end

                START_CORE: begin
                    // One edge accepts start. The GEMM now owns its memories.
                    wait_cycles_q <= '0;
                    state_q       <= WAIT_CORE;
                end

                WAIT_CORE: begin
                    // Normally 544 GEMM work clocks, then observe done.
                    // A stalled core gets a red FAIL instead of waiting forever.
                    if (core_done && !core_busy) begin
                        state_q <= READ_C;
                    end else if (wait_cycles_q == CORE_TIMEOUT_CYCLES) begin
                        state_q <= FAIL;
                    end else begin
                        wait_cycles_q <= wait_cycles_q + 1'b1;
                    end
                end

                READ_C: begin
                    // Request both C and its expected value; both update after
                    // this edge and are available for the next comparison.
                    state_q <= CHECK_C;
                end

                CHECK_C: begin
                    // This edge sees the result of the preceding read edge.
                    if (c_value == expected_value_q) begin
                        if (word_index_q == LAST_WORD_INDEX) begin
                            if (case_index_q == CASE_COUNT - 1) begin
                                state_q <= PASS;
                            end else begin
                                case_index_q <= case_index_q + 1'b1;
                                word_index_q <= '0;
                                state_q      <= READ_INPUT;
                            end
                        end else begin
                            word_index_q <= word_index_q + 1'b1;
                            state_q      <= READ_C;
                        end
                    end else begin
                        state_q <= FAIL;
                    end
                end

                default: begin
                    state_q <= FAIL;
                end
            endcase
        end
    end

endmodule

`default_nettype wire

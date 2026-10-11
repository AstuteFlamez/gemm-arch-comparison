`timescale 1ns/1ps
`default_nettype none

// One core per run: neither architecture waits for the other during power capture.
// The first ten directed jobs warm up unreset SRAM; measure the random jobs only.
module tb_gemm_ppa #(
    parameter int MatrixDim = 32,
    parameter realtime ClockPeriodNs = 10.0
);
    `include "gemm_vectors.svh"
    localparam int MATRIX_WORDS = MatrixDim * MatrixDim;
    localparam int ADDR_WIDTH = $clog2(MATRIX_WORDS);
    localparam int WORD_COUNT = CASE_COUNT * MATRIX_WORDS;
    localparam int WARMUP_CASES = 10;
    localparam int TIMEOUT_CYCLES = 2 * (MatrixDim / 2)**2 * (3 * MatrixDim + 10);

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic start = 1'b0;
    logic a_we = 1'b0;
    logic b_we = 1'b0;
    logic [ADDR_WIDTH - 1:0] a_wr_addr = '0;
    logic [ADDR_WIDTH - 1:0] b_wr_addr = '0;
    logic [ADDR_WIDTH - 1:0] c_rd_addr = '0;
    logic signed [7:0] a_wdata = '0;
    logic signed [7:0] b_wdata = '0;
    logic busy;
    logic done;
    logic signed [31:0] c_rd_data;
    logic signed [7:0] inputs_a [0:WORD_COUNT - 1];
    logic signed [7:0] inputs_b [0:WORD_COUNT - 1];
    logic signed [31:0] expected_c [0:WORD_COUNT - 1];
    integer reference_c [0:MATRIX_WORDS - 1];

    always #(ClockPeriodNs / 2.0) clk = ~clk;

`ifdef PPA_CONVENTIONAL
    conventional_gemm #(.MatrixDim(MatrixDim)) dut (
`else
    systolic_gemm #(.MatrixDim(MatrixDim)) dut (
`endif
        .clk(clk), .rst(rst), .start(start),
        .a_we(a_we), .a_wr_addr(a_wr_addr), .a_wdata(a_wdata),
        .b_we(b_we), .b_wr_addr(b_wr_addr), .b_wdata(b_wdata),
        .busy(busy), .done(done), .c_rd_addr(c_rd_addr), .c_rd_data(c_rd_data)
    );

    initial begin : benchmark
        integer csv_file;
        integer window_file;
        integer pass_file;
        integer base;
        integer elapsed;
        integer left_value;
        integer right_value;
        realtime window_start;
        realtime transaction_start;
        realtime compute_start;
        realtime compute_end;

        if (VECTOR_MATRIX_DIM != MatrixDim || VECTOR_WORDS_PER_CASE != MATRIX_WORDS ||
            CASE_COUNT <= WARMUP_CASES || ClockPeriodNs < 0.01) begin
            $fatal(1, "Invalid PPA dimensions, clock, or workload (need random cases)");
        end
        $readmemh("inputs_a.hex", inputs_a);
        $readmemh("inputs_b.hex", inputs_b);
        $readmemh("expected.hex", expected_c);
        csv_file = $fopen("cycles.csv", "w");
        if (!csv_file) $fatal(1, "Cannot open cycles.csv");
        $fdisplay(csv_file, "case_index,measured,compute_cycles,compute_ns,transaction_ns,outputs_checked");
`ifdef PPA_SAIF
        $set_gate_level_monitoring("rtl_on", "mda", "sv");
        $set_toggle_region(dut);
`endif
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        for (integer test_case = 0; test_case < CASE_COUNT; test_case++) begin
            base = test_case * MATRIX_WORDS;
            // An independent outer-product oracle also rejects broken fixture files.
            for (integer word_index = 0; word_index < MATRIX_WORDS; word_index++) begin
                reference_c[word_index] = 0;
            end
            for (integer k = 0; k < MatrixDim; k++) begin
                for (integer row_index = 0; row_index < MatrixDim; row_index++) begin
                    for (integer column_index = 0; column_index < MatrixDim; column_index++) begin
                        left_value = inputs_a[base + row_index * MatrixDim + k];
                        right_value = inputs_b[base + k * MatrixDim + column_index];
                        reference_c[row_index * MatrixDim + column_index] += left_value * right_value;
                    end
                end
            end
            for (integer word_index = 0; word_index < MATRIX_WORDS; word_index++) begin
                if ((^reference_c[word_index]) === 1'bx ||
                    reference_c[word_index] !== expected_c[base + word_index]) begin
                    $fatal(1, "Invalid fixture: case %0d C[%0d]", test_case, word_index);
                end
            end

            // Boundaries share the same falling edge, so consecutive transactions
            // tile the capture window exactly, including load, compute and readback.
            transaction_start = $realtime;
            if (test_case == WARMUP_CASES) begin
                window_start = $realtime;
`ifdef PPA_SAIF
                $toggle_start();
`endif
            end
            for (integer word_index = 0; word_index < MATRIX_WORDS; word_index++) begin
                a_we = 1'b1;
                b_we = 1'b1;
                a_wr_addr = ADDR_WIDTH'(word_index);
                b_wr_addr = ADDR_WIDTH'(word_index);
                a_wdata = inputs_a[base + word_index];
                b_wdata = inputs_b[base + word_index];
                @(negedge clk);
            end
            a_we = 1'b0;
            b_we = 1'b0;
            start = 1'b1;
            @(posedge clk);
            #1ps;
            compute_start = $realtime;
            if ({busy, done} !== 2'b10) $fatal(1, "Start was not accepted");
            elapsed = 0;
            while (done !== 1'b1) begin
                @(negedge clk);
                start = 1'b0;
                @(posedge clk);
                #1ps;
                elapsed++;
                if ({busy, done} !== 2'b10 && {busy, done} !== 2'b01) begin
                    $fatal(1, "Invalid busy/done handshake");
                end
                if (elapsed > TIMEOUT_CYCLES) $fatal(1, "Completion timed out");
            end
            compute_end = $realtime;
            for (integer word_index = 0; word_index < MATRIX_WORDS; word_index++) begin
                @(negedge clk);
                c_rd_addr = ADDR_WIDTH'(word_index);
                @(posedge clk);
                #1ps;
                if (c_rd_data !== reference_c[word_index]) begin
                    $fatal(1, "Mismatch: case %0d C[%0d]: expected %0d got %0d",
                           test_case, word_index, reference_c[word_index], c_rd_data);
                end
            end
            @(negedge clk);
            $fdisplay(csv_file, "%0d,%0d,%0d,%.3f,%.3f,%0d", test_case,
                      test_case >= WARMUP_CASES, elapsed, compute_end - compute_start,
                      $realtime - transaction_start, MATRIX_WORDS);
        end
`ifdef PPA_SAIF
        $toggle_stop();
        // Native VCS takes a scope here, unlike the legacy PLI string argument.
        $toggle_report("activity.saif", 1.0e-9, dut);
`endif
        $fclose(csv_file);
        window_file = $fopen("window.csv", "w");
        if (!window_file) $fatal(1, "Cannot open window.csv");
        $fdisplay(window_file, "measured_pairs,duration_ns,clock_period_ns");
        $fdisplay(window_file, "%0d,%.3f,%.3f", CASE_COUNT - WARMUP_CASES,
                  $realtime - window_start, ClockPeriodNs);
        $fclose(window_file);
        pass_file = $fopen("benchmark.pass", "w");
        if (!pass_file) $fatal(1, "Cannot open benchmark.pass");
        $fdisplay(pass_file, "PASS: every output checked on %0d pairs", CASE_COUNT);
        $fclose(pass_file);
        $display("PASS: %0d warmup + %0d measured pairs, %0d outputs each",
                 WARMUP_CASES, CASE_COUNT - WARMUP_CASES, MATRIX_WORDS);
        $finish;
    end

    initial begin : watchdog
        repeat (CASE_COUNT * (2 * MATRIX_WORDS + TIMEOUT_CYCLES + 8) + 8) @(posedge clk);
        $fatal(1, "PPA test timed out");
    end
endmodule

`default_nettype wire

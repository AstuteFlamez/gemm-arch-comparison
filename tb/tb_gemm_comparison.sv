`timescale 1ns/1ps
`default_nettype none

module tb_gemm_comparison #(
    parameter int MatrixDim = 8
);
    `include "gemm_vectors.svh"
    localparam int MATRIX_WORDS = MatrixDim * MatrixDim;
    localparam int ADDR_WIDTH = $clog2(MATRIX_WORDS);
    localparam int WORD_COUNT = CASE_COUNT * MATRIX_WORDS;
    localparam int TILE_COUNT = (MatrixDim / 2) * (MatrixDim / 2);
    // Current serialized schedules, including top-level tile handshakes.
    localparam int SYSTOLIC_CYCLES = TILE_COUNT * (3 * MatrixDim + 10);
    localparam int CONVENTIONAL_CYCLES = TILE_COUNT * (3 * MatrixDim + 8);
    localparam int JOB_TIMEOUT_CYCLES = 2 * SYSTOLIC_CYCLES;

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
    logic systolic_busy;
    logic systolic_done;
    logic conventional_busy;
    logic conventional_done;
    logic signed [31:0] systolic_c;
    logic signed [31:0] conventional_c;
    logic signed [7:0] inputs_a [0:WORD_COUNT - 1];
    logic signed [7:0] inputs_b [0:WORD_COUNT - 1];
    logic signed [31:0] fixture_expected [0:WORD_COUNT - 1];
    integer reference_c [0:MATRIX_WORDS - 1];
    integer checked_outputs = 0;

    always #5 clk = ~clk;

    systolic_gemm #(
        .MatrixDim(MatrixDim)
    ) systolic (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a_we(a_we),
        .a_wr_addr(a_wr_addr),
        .a_wdata(a_wdata),
        .b_we(b_we),
        .b_wr_addr(b_wr_addr),
        .b_wdata(b_wdata),
        .busy(systolic_busy),
        .done(systolic_done),
        .c_rd_addr(c_rd_addr),
        .c_rd_data(systolic_c)
    );

    conventional_gemm #(
        .MatrixDim(MatrixDim)
    ) conventional (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a_we(a_we),
        .a_wr_addr(a_wr_addr),
        .a_wdata(a_wdata),
        .b_we(b_we),
        .b_wr_addr(b_wr_addr),
        .b_wdata(b_wdata),
        .busy(conventional_busy),
        .done(conventional_done),
        .c_rd_addr(c_rd_addr),
        .c_rd_data(conventional_c)
    );

    initial begin : compare_cores
        integer base;
        integer left_value;
        integer right_value;
        integer elapsed;
        integer systolic_cycles;
        integer conventional_cycles;
        integer report_file;

        if (VECTOR_MATRIX_DIM != MatrixDim || VECTOR_WORDS_PER_CASE != MATRIX_WORDS ||
            CASE_COUNT <= 0) begin
            $fatal(1, "Fixture dimensions/count do not match this %0dx%0d simulation",
                   MatrixDim, MatrixDim);
        end
        $readmemh("inputs_a.hex", inputs_a);
        $readmemh("inputs_b.hex", inputs_b);
        $readmemh("expected.hex", fixture_expected);
        report_file = $fopen("cycles.csv", "w");
        if (report_file == 0) begin
            $fatal(1, "Cannot open cycles.csv");
        end
        $fdisplay(report_file,
                  "matrix_dim,case_index,systolic_cycles,conventional_cycles,outputs_per_core");
        $display("Comparing %0dx%0d GEMM on %0d identical matrix pairs",
                 MatrixDim, MatrixDim, CASE_COUNT);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Reset only once: every subsequent pair must work with reused storage.
        for (integer test_case = 0; test_case < CASE_COUNT; test_case++) begin
            base = test_case * MATRIX_WORDS;
            // Recompute C from the inputs using outer products. This oracle does
            // not use either core's outputs, timing, or tile order.
            for (integer word_index = 0; word_index < MATRIX_WORDS; word_index++) begin
                reference_c[word_index] = 0;
            end
            for (integer k = 0; k < MatrixDim; k++) begin
                for (integer r = 0; r < MatrixDim; r++) begin
                    for (integer c = 0; c < MatrixDim; c++) begin
                        left_value = inputs_a[base + r * MatrixDim + k];
                        right_value = inputs_b[base + k * MatrixDim + c];
                        reference_c[r * MatrixDim + c] += left_value * right_value;
                    end
                end
            end
            for (integer word_index = 0; word_index < MATRIX_WORDS; word_index++) begin
                if ((^reference_c[word_index]) === 1'bx ||
                    reference_c[word_index] !== fixture_expected[base + word_index]) begin
                    $fatal(1, "case %0d: invalid fixture at C[%0d]", test_case, word_index);
                end
            end

            for (integer word_index = 0; word_index < MATRIX_WORDS; word_index++) begin
                @(negedge clk);
                a_we = 1'b1;
                b_we = 1'b1;
                a_wr_addr = ADDR_WIDTH'(word_index);
                b_wr_addr = ADDR_WIDTH'(word_index);
                a_wdata = inputs_a[base + word_index];
                b_wdata = inputs_b[base + word_index];
            end
            @(negedge clk);
            a_we = 1'b0;
            b_we = 1'b0;
            start = 1'b1;
            @(posedge clk);
            #1;
            if ({systolic_busy, conventional_busy, systolic_done, conventional_done} !== 4'b1100) begin
                $fatal(1, "case %0d: both cores must accept start", test_case);
            end

            elapsed = 0;
            systolic_cycles = 0;
            conventional_cycles = 0;
            while (systolic_cycles == 0 || conventional_cycles == 0) begin
                @(negedge clk);
                start = 1'b0;
                @(posedge clk);
                #1;
                elapsed++;
                if (systolic_done === 1'b1 && systolic_cycles == 0) begin
                    systolic_cycles = elapsed;
                end
                if (conventional_done === 1'b1 && conventional_cycles == 0) begin
                    conventional_cycles = elapsed;
                end
                if (systolic_busy !== (systolic_cycles == 0) ||
                    conventional_busy !== (conventional_cycles == 0) ||
                    systolic_done !== (systolic_cycles != 0) ||
                    conventional_done !== (conventional_cycles != 0)) begin
                    $fatal(1, "case %0d: invalid busy/done handshake", test_case);
                end
                if (elapsed > JOB_TIMEOUT_CYCLES) begin
                    $fatal(1, "case %0d: completion timed out", test_case);
                end
            end
            if (systolic_cycles != SYSTOLIC_CYCLES || conventional_cycles != CONVENTIONAL_CYCLES) begin
                $fatal(1, "case %0d: unexpected systolic/conventional latency %0d/%0d",
                       test_case, systolic_cycles, conventional_cycles);
            end

            // Both C ports use the same synchronous read address and edge.
            for (integer word_index = 0; word_index < MATRIX_WORDS; word_index++) begin
                @(negedge clk);
                c_rd_addr = ADDR_WIDTH'(word_index);
                @(posedge clk);
                #1;
                if (systolic_c !== reference_c[word_index] ||
                    conventional_c !== reference_c[word_index]) begin
                    $fatal(1, "case %0d C[%0d]: expected %0d, systolic %0d, conventional %0d",
                           test_case, word_index, reference_c[word_index], systolic_c, conventional_c);
                end
                checked_outputs++;
            end
            // Record measured counts only after every output of this pair passed.
            $fdisplay(report_file, "%0d,%0d,%0d,%0d,%0d", MatrixDim, test_case,
                      systolic_cycles, conventional_cycles, MATRIX_WORDS);
        end
        $fclose(report_file);
        $display("PASS: both cores match independent reference on %0d consecutive matrix pairs",
                 CASE_COUNT);
        $display("PASS: %0d outputs checked per core; no reset between jobs", checked_outputs);
        $display("Accepted-start to done: systolic %0d clocks; conventional %0d clocks",
                 systolic_cycles, conventional_cycles);
        $display("Per-pair measured counts saved in cycles.csv; case names/seed in vectors_manifest.json.");
        $display("Counts exclude host loading/readback; frequency, area, and power are not measured here.");
        $finish;
    end

    initial begin
        repeat (CASE_COUNT * (2 * MATRIX_WORDS + JOB_TIMEOUT_CYCLES + 8) + 8) @(posedge clk);
        $fatal(1, "GEMM comparison timed out");
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module tb_gemm_comparison;
    `include "gemm_vectors.svh"
    localparam integer WORD_COUNT = CASE_COUNT * 64;

    logic clk = 0, rst = 1, start = 0, a_we = 0, b_we = 0;
    logic [5:0] a_wr_addr = 0, b_wr_addr = 0, c_rd_addr = 0;
    logic signed [7:0] a_wdata = 0, b_wdata = 0;
    logic systolic_busy, systolic_done, conventional_busy, conventional_done;
    logic signed [31:0] systolic_c, conventional_c;
    logic signed [7:0] inputs_a [0:WORD_COUNT-1];
    logic signed [7:0] inputs_b [0:WORD_COUNT-1];
    logic signed [31:0] fixture_expected [0:WORD_COUNT-1];
    integer reference_c [0:63];
    integer checked_outputs = 0;

    always #5 clk = ~clk;

    systolic_gemm systolic (
        .clk(clk), .rst(rst), .start(start),
        .a_we(a_we), .a_wr_addr(a_wr_addr), .a_wdata(a_wdata),
        .b_we(b_we), .b_wr_addr(b_wr_addr), .b_wdata(b_wdata),
        .busy(systolic_busy), .done(systolic_done),
        .c_rd_addr(c_rd_addr), .c_rd_data(systolic_c)
    );
    conventional_gemm conventional (
        .clk(clk), .rst(rst), .start(start),
        .a_we(a_we), .a_wr_addr(a_wr_addr), .a_wdata(a_wdata),
        .b_we(b_we), .b_wr_addr(b_wr_addr), .b_wdata(b_wdata),
        .busy(conventional_busy), .done(conventional_done),
        .c_rd_addr(c_rd_addr), .c_rd_data(conventional_c)
    );

    initial begin : compare_cores
        integer base, left_value, right_value;
        integer elapsed, systolic_cycles, conventional_cycles;
        $readmemh("inputs_a.hex", inputs_a);
        $readmemh("inputs_b.hex", inputs_b);
        $readmemh("expected.hex", fixture_expected);
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 0;

        // Reset only once: every subsequent pair must work with reused storage.
        for (integer test_case = 0; test_case < CASE_COUNT; test_case++) begin
            base = test_case * 64;
            // Recompute C independently from the inputs, not from either core.
            for (integer r = 0; r < 8; r++) begin
                for (integer c = 0; c < 8; c++) begin
                    reference_c[r*8+c] = 0;
                    for (integer k = 0; k < 8; k++) begin
                        left_value = inputs_a[base+r*8+k];
                        right_value = inputs_b[base+k*8+c];
                        reference_c[r*8+c] += left_value * right_value;
                    end
                    if ((^reference_c[r*8+c]) === 1'bx ||
                        reference_c[r*8+c] !== fixture_expected[base+r*8+c])
                        $fatal(1, "case %0d: invalid fixture at C[%0d,%0d]", test_case, r, c);
                end
            end

            for (integer word_index = 0; word_index < 64; word_index++) begin
                @(negedge clk);
                a_we = 1;
                b_we = 1;
                a_wr_addr = word_index;
                b_wr_addr = word_index;
                a_wdata = inputs_a[base+word_index];
                b_wdata = inputs_b[base+word_index];
            end
            @(negedge clk);
            a_we = 0;
            b_we = 0;
            start = 1;
            @(posedge clk); #1;
            if ({systolic_busy, conventional_busy, systolic_done, conventional_done} !== 4'b1100)
                $fatal(1, "case %0d: both cores must accept start", test_case);

            elapsed = 0;
            systolic_cycles = 0;
            conventional_cycles = 0;
            while (systolic_cycles == 0 || conventional_cycles == 0) begin
                @(negedge clk);
                start = 0;
                @(posedge clk); #1;
                elapsed++;
                if (systolic_done === 1'b1 && systolic_cycles == 0)
                    systolic_cycles = elapsed;
                if (conventional_done === 1'b1 && conventional_cycles == 0)
                    conventional_cycles = elapsed;
                if (systolic_busy !== (systolic_cycles == 0) ||
                    conventional_busy !== (conventional_cycles == 0) ||
                    systolic_done !== (systolic_cycles != 0) ||
                    conventional_done !== (conventional_cycles != 0))
                    $fatal(1, "case %0d: invalid busy/done handshake", test_case);
                if (elapsed > 1024)
                    $fatal(1, "case %0d: completion timed out", test_case);
            end
            if (systolic_cycles != 544 || conventional_cycles != 512)
                $fatal(1, "case %0d: unexpected systolic/conventional latency %0d/%0d",
                       test_case, systolic_cycles, conventional_cycles);

            // Both C ports use the same synchronous read address and edge.
            for (integer word_index = 0; word_index < 64; word_index++) begin
                @(negedge clk);
                c_rd_addr = word_index;
                @(posedge clk); #1;
                if (systolic_c !== reference_c[word_index] ||
                    conventional_c !== reference_c[word_index])
                    $fatal(1, "case %0d C[%0d]: expected %0d, systolic %0d, conventional %0d",
                           test_case, word_index, reference_c[word_index], systolic_c, conventional_c);
                checked_outputs++;
            end
        end
        $display("PASS: both cores match independent reference on %0d consecutive matrix pairs", CASE_COUNT);
        $display("PASS: %0d outputs checked per core; no reset between jobs", checked_outputs);
        $display("Accepted-start to done: systolic 544 clocks; conventional 512 clocks");
        $display("Counts exclude host loading/readback; FPGA frequency, area, and power are not measured here.");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "GEMM comparison timed out");
    end
endmodule

`default_nettype wire

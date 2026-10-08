`timescale 1ns/1ps
`default_nettype none

module tb_systolic_array;
    logic clk = 0;
    logic rst = 1;
    logic clr = 0;
    logic enable = 0;
    logic signed [7:0] A0 = 0, A1 = 0, B0 = 0, B1 = 0;
    logic signed [31:0] C00, C01, C10, C11;
    logic signed [7:0] a [0:1][0:7];
    logic signed [7:0] b [0:7][0:1];
    integer checks = 0;
    integer tiles = 0;
    integer seed = 20260917;
    integer random_init;

    systolic_array dut (
        .clk(clk),
        .rst(rst),
        .clr(clr),
        .enable(enable),
        .A0(A0), .A1(A1), .B0(B0), .B1(B1),
        .C00(C00), .C01(C01), .C10(C10), .C11(C11)
    );

    always #5 clk = ~clk;

    // Drive on falling edges; observe after the rising-edge register updates.
    task automatic step(
        input logic next_rst, next_enable,
        input logic signed [7:0] next_a0, next_a1, next_b0, next_b1,
        input integer expected00, expected01, expected10, expected11,
        input string case_name,
        input logic next_clr = 1'b0
    );
        logic [127:0] previous_results;
        @(negedge clk);
        previous_results = {C00, C01, C10, C11};
        rst = next_rst;
        clr = next_clr;
        enable = next_enable;
        A0 = next_a0;
        A1 = next_a1;
        B0 = next_b0;
        B1 = next_b1;
        #1;
        if ({C00, C01, C10, C11} !== previous_results)
            $fatal(1, "%s: results changed before rising edge", case_name);
        @(posedge clk);
        #1;
        if (C00 !== expected00 || C01 !== expected01 ||
            C10 !== expected10 || C11 !== expected11)
            $fatal(1, "%s: expected [[%0d,%0d],[%0d,%0d]], got [[%0d,%0d],[%0d,%0d]]",
                case_name, expected00, expected01, expected10, expected11,
                C00, C01, C10, C11);
        checks = checks + 1;
    endtask

    // Mathematical reference: product k reaches PE(row,col) on enabled
    // step k+row+col. COMPUTE partial dot products directly from the matrices,
    // independently of the DUT's forwarding registers.
    function automatic integer expected_sum(
        input integer row, col, terms, last_step
    );
        integer av, bv;
        expected_sum = 0;
        for (integer k = 0; k < terms; k = k + 1) begin
            if (k + row + col <= last_step) begin
                av = a[row][k];
                bv = b[k][col];
                expected_sum = expected_sum + av * bv;
            end
        end
    endfunction

    task automatic run_tile(
        input integer terms,
        input logic pause_each_step,
        input string case_name
    );
        logic signed [7:0] next_a0, next_a1, next_b0, next_b1;
        integer e00, e01, e10, e11;
        step(1, 0, 0, 0, 0, 0, 0, 0, 0, 0, {case_name, ": reset"});
        e00 = 0; e01 = 0; e10 = 0; e11 = 0;

        // K products plus two propagation steps to the bottom-right PE.
        for (integer t = 0; t < terms + 2; t = t + 1) begin
            if (pause_each_step) begin
                // Deliberately change boundary inputs while paused. Neither
                // accumulation nor internal forwarding may advance.
                step(0, 0, 99, -77, 55, -33, e00, e01, e10, e11,
                    $sformatf("%s: pause before step %0d", case_name, t));
                step(0, 0, -12, 34, -56, 78, e00, e01, e10, e11,
                    $sformatf("%s: held pause before step %0d", case_name, t));
            end

            // Row 1 and column 1 begin one enabled step later.
            // Unused boundary slots must contain zeros, including drain.
            next_a0 = 0; next_a1 = 0;
            next_b0 = 0; next_b1 = 0;
            if (t < terms) begin
                next_a0 = a[0][t];
                next_b0 = b[t][0];
            end
            if (t >= 1 && t <= terms) begin
                next_a1 = a[1][t-1];
                next_b1 = b[t-1][1];
            end
            e00 = expected_sum(0, 0, terms, t);
            e01 = expected_sum(0, 1, terms, t);
            e10 = expected_sum(1, 0, terms, t);
            e11 = expected_sum(1, 1, terms, t);
            step(0, 1, next_a0, next_a1, next_b0, next_b1,
                e00, e01, e10, e11, $sformatf("%s: step %0d", case_name, t));
        end

        // Extra enabled zero cycles must not corrupt completed results.
        repeat (3)
            step(0, 1, 0, 0, 0, 0, e00, e01, e10, e11,
                {case_name, ": zero padding after completion"});
        step(0, 0, 127, -128, -128, 127, e00, e01, e10, e11,
            {case_name, ": disabled after completion"});
        tiles = tiles + 1;
    endtask

    initial begin
        if ($value$plusargs("SEED=%d", seed)) begin end
        random_init = $urandom(seed);
        @(posedge clk);
        #1;
        if ({C00, C01, C10, C11} !== 128'd0)
            $fatal(1, "initial reset failed");

        // The walkthrough example, with explicit cycle-by-cycle expectations:
        // [1 2] * [5 6] = [19 22]
        // [3 4]   [7 8]   [43 50]
        step(0, 1, 1, 0, 5, 0,  5,  0,  0,  0, "example: edge 1");
        step(0, 1, 2, 3, 7, 6, 19,  6, 15,  0, "example: edge 2");
        step(0, 1, 0, 4, 0, 8, 19, 22, 43, 18, "example: edge 3");
        step(0, 1, 0, 0, 0, 0, 19, 22, 43, 50, "example: edge 4");
        $display("PASS: example C = [[%0d,%0d],[%0d,%0d]] after four enabled edges",
            C00, C01, C10, C11);
        tiles = tiles + 1;

        a[0][0] = -128; a[1][0] = 127;
        b[0][0] = -128; b[0][1] = 127;
        run_tile(1, 1, "single product with signed extremes and pauses");

        for (integer k = 0; k < 8; k = k + 1) begin
            a[0][k] = -128; a[1][k] = 127;
            b[k][0] = -128; b[k][1] = 127;
        end
        run_tile(8, 0, "eight products, sums exceed signed 16 bits");
        run_tile(8, 1, "same tile with pauses at every position");

        for (integer k = 0; k < 8; k = k + 1) begin
            a[0][k] = 0; a[1][k] = 0;
        end
        run_tile(8, 0, "zero matrix times nonzero matrix");

        for (integer trial = 0; trial < 20; trial = trial + 1) begin
            for (integer k = 0; k < 8; k = k + 1) begin
                for (integer i = 0; i < 2; i = i + 1) begin
                    a[i][k] = $urandom_range(0, 255) - 128;
                    b[k][i] = $urandom_range(0, 255) - 128;
                end
            end
            run_tile(1 + trial % 8, trial % 2,
                $sformatf("random signed tile %0d", trial));
        end

        // Abort a tile with operands still in flight. Reset must clear both
        // accumulators and forwarding registers, even when enable is low.
        step(1, 0, 0, 0, 0, 0, 0, 0, 0, 0, "prepare interrupted tile");
        step(0, 1, 2, 0, 3, 0, 6, 0, 0, 0, "start interrupted tile");
        step(1, 0, 9, 9, 9, 9, 0, 0, 0, 0, "reset while disabled");
        repeat (3)
            step(0, 1, 0, 0, 0, 0, 0, 0, 0, 0, "no stale data after reset");
        step(0, 1, 2, 0, 3, 0, 6, 0, 0, 0, "restart interrupted tile");
        step(1, 1, 9, 9, 9, 9, 0, 0, 0, 0, "reset overrides enable");
        step(1, 1, 9, 9, 9, 9, 0, 0, 0, 0, "held reset");
        repeat (3)
            step(0, 1, 0, 0, 0, 0, 0, 0, 0, 0, "no stale data after held reset");
        run_tile(8, 0, "restart after interrupted tile");

        // Clear with operands in flight must flush forwarding as well as sums.
        step(0, 0, 9, 9, 9, 9, 0, 0, 0, 0, "clear completed tile while disabled", 1);
        step(0, 1, 2, 0, 3, 0, 6, 0, 0, 0, "start tile before clear");
        step(0, 0, 9, 9, 9, 9, 0, 0, 0, 0, "clear in-flight tile while disabled", 1);
        repeat (3) begin
            step(0, 1, 0, 0, 0, 0, 0, 0, 0, 0, "no stale data after clear");
        end
        step(0, 1, 2, 0, 3, 0, 6, 0, 0, 0, "restart after clear");
        step(0, 1, 9, 9, 9, 9, 0, 0, 0, 0, "clear overrides enable", 1);
        step(0, 1, 9, 9, 9, 9, 0, 0, 0, 0, "held clear", 1);
        step(1, 1, 9, 9, 9, 9, 0, 0, 0, 0, "reset and clear together", 1);
        repeat (3) begin
            step(0, 1, 0, 0, 0, 0, 0, 0, 0, 0, "no stale data after held clear");
        end

        $display("PASS: systolic array completed %0d tiles and %0d cycle checks",
            tiles, checks);
        $finish;
    end

    initial begin
        $dumpfile("systolic_array.vcd");
        $dumpvars(0, tb_systolic_array);
        #100000;
        $fatal(1, "systolic array testbench timed out");
    end
endmodule

`default_nettype wire

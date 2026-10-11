`timescale 1ns/1ps
`default_nettype none

module tb_gemm #(
    parameter int MatrixDim = 8,
    parameter bit USE_CONVENTIONAL = 1'b0
);
    localparam int MATRIX_WORDS = MatrixDim * MatrixDim;
    localparam int ADDR_WIDTH = $clog2(MATRIX_WORDS);
    // Each tile includes loading, FIFO priming, compute, stores, and handshakes.
    localparam integer TILE_CYCLES = 3 * MatrixDim + (USE_CONVENTIONAL ? 8 : 10);
    localparam integer WORK_CYCLES = (MatrixDim / 2) * (MatrixDim / 2) * TILE_CYCLES;
    localparam integer BEFORE_FIRST_STORE = 3 * MatrixDim + (USE_CONVENTIONAL ? 3 : 5);

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic a_we = 1'b0;
    logic b_we = 1'b0;
    logic [ADDR_WIDTH - 1:0] a_wr_addr = '0;
    logic [ADDR_WIDTH - 1:0] b_wr_addr = '0;
    logic signed [7:0] a_wdata = 8'sd0;
    logic signed [7:0] b_wdata = 8'sd0;
    logic start = 1'b0;
    logic busy;
    logic done;
    logic [ADDR_WIDTH - 1:0] c_rd_addr = '0;
    logic signed [31:0] c_rd_data;

    logic signed [7:0] matrix_a [0:MATRIX_WORDS - 1];
    logic signed [7:0] matrix_b [0:MATRIX_WORDS - 1];
    integer expected [0:MATRIX_WORDS - 1];
    logic [31:0] random_state = 32'h20260919;
    integer completed_jobs = 0;
    integer checked_outputs = 0;
    integer rst_offsets [0:10];

    generate
        if (USE_CONVENTIONAL) begin : conventional
            conventional_gemm #(
                .MatrixDim(MatrixDim)
            ) dut (
                .clk(clk), .rst(rst),
                .a_we(a_we), .a_wr_addr(a_wr_addr), .a_wdata(a_wdata),
                .b_we(b_we), .b_wr_addr(b_wr_addr), .b_wdata(b_wdata),
                .start(start), .busy(busy), .done(done),
                .c_rd_addr(c_rd_addr), .c_rd_data(c_rd_data)
            );
        end else begin : systolic
            systolic_gemm #(
                .MatrixDim(MatrixDim)
            ) dut (
                .clk(clk), .rst(rst),
                .a_we(a_we), .a_wr_addr(a_wr_addr), .a_wdata(a_wdata),
                .b_we(b_we), .b_wr_addr(b_wr_addr), .b_wdata(b_wdata),
                .start(start), .busy(busy), .done(done),
                .c_rd_addr(c_rd_addr), .c_rd_data(c_rd_data)
            );
        end
    endgenerate

    always #5 clk = ~clk;

    task automatic tick;
        @(posedge clk);
        #1;
    endtask

    task automatic idle_requests;
        a_we = 1'b0;
        b_we = 1'b0;
        start = 1'b0;
    endtask

    task automatic check_status(
        input logic wanted_busy,
        input logic wanted_done,
        input string label_text
    );
        if (busy !== wanted_busy || done !== wanted_done)
            $fatal(1, "%s: expected busy/done %b/%b, got %b/%b",
                   label_text, wanted_busy, wanted_done, busy, done);
    endtask

    task automatic check_read_data(
        input logic signed [31:0] wanted_data,
        input string label_text
    );
        if (c_rd_data !== wanted_data)
            $fatal(1, "%s: expected C read data %h, got %h",
                   label_text, wanted_data, c_rd_data);
    endtask

    task automatic rst_core;
        logic signed [31:0] held_read_data;
        @(negedge clk);
        held_read_data = c_rd_data;
        idle_requests();
        rst = 1'b1;
        // A different address must not trigger a read while reset is high.
        c_rd_addr = c_rd_addr + 1'b1;
        #1;
        check_read_data(held_read_data, "reset asserted: C output holds");
        repeat (2) begin
            tick();
            check_status(1'b0, 1'b0, "reset");
            check_read_data(held_read_data, "reset edge: C output holds");
        end
        @(negedge clk);
        rst = 1'b0;
    endtask

    // A mathematical reference using outer products, independent of RTL timing.
    // Widen both signed operands before multiplication to avoid truncation.
    task automatic calculate_expected;
        integer left_value;
        integer right_value;
        for (integer i = 0; i < MATRIX_WORDS; i = i + 1)
            expected[i] = 0;
        for (integer k = 0; k < MatrixDim; k = k + 1) begin
            for (integer r = 0; r < MatrixDim; r = r + 1) begin
                for (integer c = 0; c < MatrixDim; c = c + 1) begin
                    left_value = matrix_a[r * MatrixDim + k];
                    right_value = matrix_b[k * MatrixDim + c];
                    expected[r * MatrixDim + c] += left_value * right_value;
                end
            end
        end
    endtask

    task automatic load_operands;
        logic previous_done;
        previous_done = done;
        for (integer i = 0; i < MATRIX_WORDS; i = i + 1) begin
            @(negedge clk);
            start = 1'b0;
            a_we = 1'b1;
            b_we = 1'b1;
            a_wr_addr = i[ADDR_WIDTH - 1:0];
            b_wr_addr = i[ADDR_WIDTH - 1:0];
            a_wdata = matrix_a[i];
            b_wdata = matrix_b[i];
            tick();
            check_status(1'b0, previous_done, "loading operands");
        end
        @(negedge clk);
        idle_requests();
    endtask

    task automatic begin_job(input string label_text);
        @(negedge clk);
        idle_requests();
        start = 1'b1;
        c_rd_addr = '0;
        tick();
        check_status(1'b1, 1'b0, {label_text, ": accepted start"});
    endtask

    task automatic finish_job(
        input string label_text,
        input bit busy_noise,
        input bit hold_start
    );
        logic signed [31:0] held_read_data;
        held_read_data = c_rd_data;
        for (integer cycle = 1; cycle <= WORK_CYCLES; cycle = cycle + 1) begin
            @(negedge clk);
            // Writes and extra starts must be ignored until full-job completion.
            start = busy_noise || hold_start;
            a_we = busy_noise;
            b_we = busy_noise;
            a_wr_addr = '0;
            b_wr_addr = '0;
            a_wdata = 8'sd127;
            b_wdata = -8'sd128;
            // Host address changes must not disturb reads or STORE addresses.
            c_rd_addr = cycle[ADDR_WIDTH - 1:0];
            #1;
            check_read_data(held_read_data, "busy address change: C output holds");
            tick();
            // This includes the completion edge: done means all results are
            // stored, but the first result read needs a subsequent idle edge.
            check_read_data(held_read_data, "busy/completion edge: C output holds");
            check_status(cycle < WORK_CYCLES, cycle == WORK_CYCLES,
                         $sformatf("%s: cycle %0d", label_text, cycle));
        end
        completed_jobs = completed_jobs + 1;
    endtask

    task automatic check_output(input integer index, input string label_text);
        if (c_rd_data !== expected[index])
            $fatal(1, "%s: C[%0d] expected %0d, got %0d",
                   label_text, index, expected[index], c_rd_data);
        checked_outputs = checked_outputs + 1;
    endtask

    task automatic read_result(
        input integer index,
        input string label_text,
        input bit wanted_done = 1'b1
    );
        logic signed [31:0] previous_read;
        @(negedge clk);
        previous_read = c_rd_data;
        idle_requests();
        c_rd_addr = index[ADDR_WIDTH - 1:0];
        #1;
        check_read_data(previous_read, {label_text, ": before read edge"});
        @(posedge clk);
        // A clocked consumer at this edge still sees the previous output.
        check_read_data(previous_read, {label_text, ": at read edge"});
        #1;
        // Wait for nonblocking updates, without adding another clock cycle.
        check_status(1'b0, wanted_done, {label_text, ": after read edge"});
        check_output(index, label_text);
    endtask

    task automatic check_results(input string label_text);
        // Consecutive idle edges must return consecutive selected words.
        for (integer i = 0; i < MATRIX_WORDS; i = i + 1)
            read_result(i, label_text);
        $display("PASS: %s", label_text);
    endtask

    task automatic run_job(input string label_text, input bit busy_noise);
        calculate_expected();
        begin_job(label_text);
        finish_job(label_text, busy_noise, 1'b0);
        check_results(label_text);
    endtask

    // Explicit INT8 wrap keeps the asymmetric patterns valid at every dimension.
    task automatic set_patterned_inputs;
        for (integer r = 0; r < MatrixDim; r = r + 1) begin
            for (integer c = 0; c < MatrixDim; c = c + 1) begin
                matrix_a[r * MatrixDim + c] = 8'(r * 17 + c * 3 - 70);
                matrix_b[r * MatrixDim + c] = 8'(r * 7 - c * 11 + 19);
            end
        end
    endtask

    function automatic logic signed [7:0] next_random_byte;
        random_state = random_state * 32'd1664525 + 32'd1013904223;
        next_random_byte = $signed(random_state[31:24]);
    endfunction

    initial begin : tests
        logic signed [31:0] previous_read;
        if ($value$plusargs("SEED=%d", random_state)) begin
            $display("Using random seed %0d", random_state);
        end
        $display("Testing %0dx%0d %s GEMM", MatrixDim, MatrixDim,
                 USE_CONVENTIONAL ? "conventional" : "systolic");
        rst_core();

        set_patterned_inputs();
        for (integer i = 0; i < MATRIX_WORDS; i = i + 1)
            matrix_a[i] = 8'sd0;
        load_operands();
        run_job("zero matrix", 1'b0);

        set_patterned_inputs();
        for (integer i = 0; i < MATRIX_WORDS; i = i + 1)
            matrix_a[i] = (i / MatrixDim == i % MatrixDim) ? 8'sd1 : 8'sd0;
        load_operands();
        run_job("left identity", 1'b0);

        set_patterned_inputs();
        for (integer i = 0; i < MATRIX_WORDS; i = i + 1)
            matrix_b[i] = (i / MatrixDim == i % MatrixDim) ? 8'sd1 : 8'sd0;
        load_operands();
        run_job("right identity", 1'b0);

        for (integer i = 0; i < MATRIX_WORDS; i = i + 1) begin
            matrix_a[i] = 8'sd1;
            matrix_b[i] = 8'sd1;
        end
        load_operands();
        run_job("all ones", 1'b0);

        for (integer i = 0; i < MATRIX_WORDS; i = i + 1) begin
            matrix_a[i] = -8'sd128;
            matrix_b[i] = -8'sd128;
        end
        load_operands();
        run_job("maximum positive sum", 1'b0);

        for (integer i = 0; i < MATRIX_WORDS; i = i + 1)
            matrix_b[i] = 8'sd127;
        load_operands();
        run_job("maximum negative sum", 1'b0);

        set_patterned_inputs();
        load_operands();
        run_job("busy writes and starts ignored", 1'b1);
        run_job("reuse inputs", 1'b0);

        for (integer test_index = 0; test_index < 20; test_index = test_index + 1) begin
            for (integer i = 0; i < MATRIX_WORDS; i = i + 1) begin
                matrix_a[i] = next_random_byte();
                matrix_b[i] = next_random_byte();
            end
            load_operands();
            run_job($sformatf("seeded random %0d", test_index), 1'b0);
        end

        // Start accepts A-only, B-only, and simultaneous final writes on the
        // same idle edge. The calculation must use those newly written values.
        for (integer mode = 1; mode <= 3; mode = mode + 1) begin
            set_patterned_inputs();
            load_operands();
            @(negedge clk);
            start = 1'b1;
            a_we = (mode != 2);
            b_we = (mode != 1);
            a_wr_addr = '0;
            b_wr_addr = '0;
            a_wdata = 8'sd77;
            b_wdata = -8'sd33;
            tick();
            check_status(1'b1, 1'b0, "start accepted alongside final writes");
            if (a_we) matrix_a[0] = a_wdata;
            if (b_we) matrix_b[0] = b_wdata;
            calculate_expected();
            finish_job($sformatf("start with final writes %0d", mode), 1'b0, 1'b0);
            check_results($sformatf("start with final writes %0d", mode));
        end

        // Preserve the preceding job's expected C values. New all-one inputs
        // would produce MatrixDim, but reset on the first STORE edge must suppress
        // that write and leave every old C word intact, including C[0].
        if (expected[0] == MatrixDim)
            $fatal(1, "Reset-preservation test needs old C[0] different from MatrixDim");
        for (integer i = 0; i < MATRIX_WORDS; i = i + 1) begin
            matrix_a[i] = 8'sd1;
            matrix_b[i] = 8'sd1;
        end
        load_operands();
        begin_job("reset before first C write");
        repeat (BEFORE_FIRST_STORE) begin // Launch + load + compute edges.
            @(negedge clk);
            idle_requests();
            tick();
            check_status(1'b1, 1'b0, "before suppressed C write");
        end
        rst_core();
        for (integer i = 0; i < MATRIX_WORDS; i = i + 1)
            read_result(i, "C contents survive reset", 1'b0);
        $display("PASS: reset suppresses STORE and preserves C contents/output");

        // Abort before launch, during FIFO loading and computation,
        // before/partway through STORE, at tile handoff, and near job completion.
        rst_offsets[0] = 0;
        rst_offsets[1] = 1;
        rst_offsets[2] = MatrixDim + 1;
        rst_offsets[3] = 2 * MatrixDim + 2;
        rst_offsets[4] = BEFORE_FIRST_STORE - 2;
        rst_offsets[5] = BEFORE_FIRST_STORE;
        rst_offsets[6] = BEFORE_FIRST_STORE + 1;
        rst_offsets[7] = TILE_CYCLES - 1;
        rst_offsets[8] = TILE_CYCLES;
        rst_offsets[9] = WORK_CYCLES - 2;
        rst_offsets[10] = WORK_CYCLES - 1;
        set_patterned_inputs();
        load_operands();
        for (integer test_index = 0; test_index < 11; test_index = test_index + 1) begin
            begin_job("job to abort");
            repeat (rst_offsets[test_index]) begin
                @(negedge clk);
                idle_requests();
                tick();
                check_status(1'b1, 1'b0, "before reset during work");
            end
            rst_core();
            run_job($sformatf("restart after reset at offset %0d",
                             rst_offsets[test_index]), 1'b0);
        end

        // Holding start requests another job on the first idle edge after done.
        calculate_expected();
        begin_job("held start first job");
        finish_job("held start first job", 1'b0, 1'b1);
        // Only one synchronous read fits on the idle edge that accepts the
        // held start. Read the final word from the completed job.
        // The full matrix is checked after the second job with start low.
        @(negedge clk);
        previous_read = c_rd_data;
        c_rd_addr = ADDR_WIDTH'(MATRIX_WORDS - 1);
        #1;
        check_read_data(previous_read, "held start: before read/restart edge");
        @(posedge clk);
        check_read_data(previous_read, "held start: at read/restart edge");
        #1;
        check_output(MATRIX_WORDS - 1, "held start first job: final word");
        check_status(1'b1, 1'b0, "held start restarts after completion");
        finish_job("held start second job", 1'b0, 1'b0);
        check_results("held start second job");

        $display("PASS: GEMM completed %0d jobs and checked %0d outputs",
                 completed_jobs, checked_outputs);
        $display("PASS: %0d clocks per full matrix; 11 reset/restart cases", WORK_CYCLES);
        $finish;
    end

    initial begin
        repeat (100 * (WORK_CYCLES + 2 * MATRIX_WORDS + 10)) @(posedge clk);
        $fatal(1, "GEMM testbench timed out");
    end
endmodule

`default_nettype wire

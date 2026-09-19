`timescale 1ns/1ps
`default_nettype none

module tb_gemm;
    // 64 outputs, each taking CLEAR + 8*(READ + MAC) + STORE.
    localparam integer WORK_CYCLES = 1152;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic a_we = 1'b0;
    logic b_we = 1'b0;
    logic [5:0] a_addr = 6'd0;
    logic [5:0] b_addr = 6'd0;
    logic signed [7:0] a_wdata = 8'sd0;
    logic signed [7:0] b_wdata = 8'sd0;
    logic start = 1'b0;
    logic busy;
    logic done;
    logic [5:0] c_rd_addr = 6'd0;
    logic signed [31:0] c_rd_data;

    logic signed [7:0] matrix_a [0:63];
    logic signed [7:0] matrix_b [0:63];
    integer expected [0:63];
    logic [31:0] random_state = 32'h20260919;
    integer completed_jobs = 0;
    integer checked_outputs = 0;
    integer reset_offsets [0:4];

    gemm dut (
        .clk(clk), .reset(reset),
        .a_we(a_we), .a_addr(a_addr), .a_wdata(a_wdata),
        .b_we(b_we), .b_addr(b_addr), .b_wdata(b_wdata),
        .start(start), .busy(busy), .done(done),
        .c_rd_addr(c_rd_addr), .c_rd_data(c_rd_data)
    );

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

    task automatic reset_core;
        @(negedge clk);
        idle_requests();
        reset = 1'b1;
        repeat (2) begin
            tick();
            check_status(1'b0, 1'b0, "reset");
        end
        @(negedge clk);
        reset = 1'b0;
    endtask

    // A mathematical reference using outer products, independent of RTL timing.
    // Widen both signed operands before multiplication to avoid truncation.
    task automatic calculate_expected;
        integer left_value;
        integer right_value;
        for (integer i = 0; i < 64; i = i + 1)
            expected[i] = 0;
        for (integer k = 0; k < 8; k = k + 1) begin
            for (integer r = 0; r < 8; r = r + 1) begin
                for (integer c = 0; c < 8; c = c + 1) begin
                    left_value = matrix_a[r * 8 + k];
                    right_value = matrix_b[k * 8 + c];
                    expected[r * 8 + c] += left_value * right_value;
                end
            end
        end
    endtask

    task automatic load_operands;
        logic previous_done;
        previous_done = done;
        for (integer i = 0; i < 64; i = i + 1) begin
            @(negedge clk);
            start = 1'b0;
            a_we = 1'b1;
            b_we = 1'b1;
            a_addr = i[5:0];
            b_addr = i[5:0];
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
        tick();
        check_status(1'b1, 1'b0, {label_text, ": accepted start"});
    endtask

    task automatic finish_job(
        input string label_text,
        input bit busy_noise,
        input bit hold_start
    );
        for (integer cycle = 1; cycle <= WORK_CYCLES; cycle = cycle + 1) begin
            @(negedge clk);
            // Writes and extra starts must be ignored through the last STORE.
            start = busy_noise || hold_start;
            a_we = busy_noise;
            b_we = busy_noise;
            a_addr = 6'd0;
            b_addr = 6'd0;
            a_wdata = 8'sd127;
            b_wdata = -8'sd128;
            tick();
            check_status(cycle < WORK_CYCLES, cycle == WORK_CYCLES,
                         $sformatf("%s: cycle %0d", label_text, cycle));
        end
        completed_jobs = completed_jobs + 1;
    endtask

    task automatic check_output(input integer index, input string label_text);
        check_status(1'b0, 1'b1, {label_text, ": sticky done"});
        if (c_rd_data !== expected[index])
            $fatal(1, "%s: C[%0d] expected %0d, got %0d",
                   label_text, index, expected[index], c_rd_data);
        checked_outputs = checked_outputs + 1;
    endtask

    task automatic check_results(input string label_text);
        for (integer i = 0; i < 64; i = i + 1) begin
            @(negedge clk);
            idle_requests();
            c_rd_addr = i[5:0];
            #1;
            check_output(i, label_text);
        end
        $display("PASS: %s", label_text);
    endtask

    task automatic run_job(input string label_text, input bit busy_noise);
        calculate_expected();
        begin_job(label_text);
        finish_job(label_text, busy_noise, 1'b0);
        check_results(label_text);
    endtask

    task automatic set_patterned_inputs;
        for (integer r = 0; r < 8; r = r + 1) begin
            for (integer c = 0; c < 8; c = c + 1) begin
                matrix_a[r * 8 + c] = r * 17 + c * 3 - 70;
                matrix_b[r * 8 + c] = r * 7 - c * 11 + 19;
            end
        end
    endtask

    function automatic logic signed [7:0] next_random_byte;
        random_state = random_state * 32'd1664525 + 32'd1013904223;
        next_random_byte = $signed(random_state[31:24]);
    endfunction

    initial begin
        reset_core();

        set_patterned_inputs();
        for (integer i = 0; i < 64; i = i + 1)
            matrix_a[i] = 8'sd0;
        load_operands();
        run_job("zero matrix", 1'b0);

        set_patterned_inputs();
        for (integer i = 0; i < 64; i = i + 1)
            matrix_a[i] = (i / 8 == i % 8) ? 8'sd1 : 8'sd0;
        load_operands();
        run_job("left identity", 1'b0);

        set_patterned_inputs();
        for (integer i = 0; i < 64; i = i + 1)
            matrix_b[i] = (i / 8 == i % 8) ? 8'sd1 : 8'sd0;
        load_operands();
        run_job("right identity", 1'b0);

        for (integer i = 0; i < 64; i = i + 1) begin
            matrix_a[i] = 8'sd1;
            matrix_b[i] = 8'sd1;
        end
        load_operands();
        run_job("all ones", 1'b0);

        for (integer i = 0; i < 64; i = i + 1) begin
            matrix_a[i] = -8'sd128;
            matrix_b[i] = -8'sd128;
        end
        load_operands();
        run_job("maximum positive sum", 1'b0);

        for (integer i = 0; i < 64; i = i + 1)
            matrix_b[i] = 8'sd127;
        load_operands();
        run_job("maximum negative sum", 1'b0);

        set_patterned_inputs();
        load_operands();
        run_job("busy writes and starts ignored", 1'b1);
        run_job("reuse inputs", 1'b0);

        for (integer test_index = 0; test_index < 20; test_index = test_index + 1) begin
            for (integer i = 0; i < 64; i = i + 1) begin
                matrix_a[i] = next_random_byte();
                matrix_b[i] = next_random_byte();
            end
            load_operands();
            run_job($sformatf("seeded random %0d", test_index), 1'b0);
        end

        // A writes, B writes, and simultaneous writes each take priority over start.
        for (integer mode = 1; mode <= 3; mode = mode + 1) begin
            set_patterned_inputs();
            load_operands();
            @(negedge clk);
            start = 1'b1;
            a_we = (mode != 2);
            b_we = (mode != 1);
            a_addr = 6'd0;
            b_addr = 6'd0;
            a_wdata = 8'sd77;
            b_wdata = -8'sd33;
            tick();
            check_status(1'b0, 1'b1, "writes take priority over start");
            if (a_we) matrix_a[0] = a_wdata;
            if (b_we) matrix_b[0] = b_wdata;
            @(negedge clk);
            idle_requests();
            tick();
            check_status(1'b0, 1'b1, "rejected start is not queued");
            run_job($sformatf("write/start collision %0d", mode), 1'b0);
        end

        // Abort in CLEAR, READ, MAC, the first STORE, and the final STORE.
        reset_offsets[0] = 0;
        reset_offsets[1] = 1;
        reset_offsets[2] = 2;
        reset_offsets[3] = 17;
        reset_offsets[4] = WORK_CYCLES - 1;
        set_patterned_inputs();
        load_operands();
        for (integer test_index = 0; test_index < 5; test_index = test_index + 1) begin
            begin_job("job to abort");
            repeat (reset_offsets[test_index]) begin
                @(negedge clk);
                idle_requests();
                tick();
                check_status(1'b1, 1'b0, "before reset during work");
            end
            reset_core();
            run_job($sformatf("restart after reset at offset %0d",
                             reset_offsets[test_index]), 1'b0);
        end

        // Holding start requests another job on the first idle edge after done.
        calculate_expected();
        begin_job("held start first job");
        finish_job("held start first job", 1'b0, 1'b1);
        // All 64 asynchronous reads fit before the next rising edge (6.4 ns).
        for (integer i = 0; i < 64; i = i + 1) begin
            c_rd_addr = i[5:0];
            #0.1;
            check_output(i, "held start first job");
        end
        tick();
        check_status(1'b1, 1'b0, "held start restarts after completion");
        finish_job("held start second job", 1'b0, 1'b0);
        check_results("held start second job");

        $display("PASS: GEMM completed %0d jobs and checked %0d outputs",
                 completed_jobs, checked_outputs);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "GEMM testbench timed out");
    end
endmodule

`default_nettype wire

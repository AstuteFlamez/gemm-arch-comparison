`timescale 1ns/1ps
`default_nettype none

// extra arithmetic and control tests
// run with make test-gemv-full
module tb_gemv_regression;
    localparam integer WORK_CYCLES = 80;

    logic clk;
    logic reset;
    logic a_we;
    logic [5:0] a_addr;
    logic signed [7:0] a_wdata;
    logic x_we;
    logic [2:0] x_addr;
    logic signed [7:0] x_wdata;
    logic start;
    logic busy;
    logic done;
    logic [2:0] y_rd_addr;
    logic signed [31:0] y_rd_data;

    // matrix and vector inputs, and expected output values
    logic signed [7:0] matrix_data [0:63];
    logic signed [7:0] vector_data [0:7];
    logic signed [31:0] expected [0:7];
    time accepted_at;
    integer completed_jobs = 0;
    integer checked_outputs = 0;
    integer fixture_count = 0;

    gemv dut (
        .clk(clk), .reset(reset),
        .a_we(a_we), .a_addr(a_addr), .a_wdata(a_wdata),
        .x_we(x_we), .x_addr(x_addr), .x_wdata(x_wdata),
        .start(start), .busy(busy), .done(done),
        .y_rd_addr(y_rd_addr), .y_rd_data(y_rd_data)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // wait 5 time units, then invert clock
    end

    task automatic tick;
        @(posedge clk);
        #1; // wait for the register updates before checking
    endtask

    task automatic idle_requests;
        a_we = 1'b0;
        x_we = 1'b0;
        start = 1'b0;
    endtask

    task automatic check_status(
        input logic wanted_busy,
        input logic wanted_done,
        input string label_text
    );
        // check busy and done, including unknown values
        if (busy !== wanted_busy || done !== wanted_done)
            $fatal(1, "%s at %0t: busy/done expected %b/%b, got %b/%b",
                   label_text, $time, wanted_busy, wanted_done, busy, done);
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

    // row 0 sums to 36, row 1 to 72, etc. with x set to all ones
    task automatic set_ramp_case;
        for (integer r = 0; r < 8; r = r + 1) begin
            vector_data[r] = 8'sd1;
            expected[r] = 36 * (r + 1);
            for (integer c = 0; c < 8; c = c + 1)
                matrix_data[8*r+c] = (r + 1) * (c + 1);
        end
    endtask

    // identity matrix should give y = x
    task automatic set_identity_case;
        for (integer r = 0; r < 8; r = r + 1) begin
            vector_data[r] = r + 1;
            expected[r] = r + 1;
            for (integer c = 0; c < 8; c = c + 1)
                matrix_data[8*r+c] = (r == c) ? 8'sd1 : 8'sd0;
        end
    endtask

    task automatic load_operands;
        logic previous_done;
        logic signed [31:0] previous_results [0:7];
        previous_done = done;
        check_status(1'b0, previous_done, "before loading");

        // save the old results to check that loading new inputs doesn't change them
        if (previous_done === 1'b1) begin
            for (integer r = 0; r < 8; r = r + 1) begin
                y_rd_addr = r[2:0];
                #0.1;
                previous_results[r] = y_rd_data;
            end
        end

        for (integer i = 0; i < 64; i = i + 1) begin
            @(negedge clk);
            start = 1'b0;
            a_we = 1'b1;
            a_addr = i[5:0];
            a_wdata = matrix_data[i];
            // write A and x on the same edge for the first 8 values
            x_we = (i < 8);
            x_addr = i[2:0];
            x_wdata = (i < 8) ? vector_data[i] : 8'sd0;
            tick();
            check_status(1'b0, previous_done, "loading operands");
        end
        @(negedge clk);
        idle_requests();
        if (previous_done === 1'b1) begin
            for (integer r = 0; r < 8; r = r + 1) begin
                y_rd_addr = r[2:0];
                #0.1;
                if (y_rd_data !== previous_results[r])
                    $fatal(1, "loading changed completed result y[%0d]", r);
            end
        end
    endtask

    task automatic begin_job(input string label_text);
        @(negedge clk);
        idle_requests();
        start = 1'b1;
        tick();
        // start accepted here, the next 80 cycles do the calculation
        check_status(1'b1, 1'b0, {label_text, ": accepted start"});
        accepted_at = $time;
    endtask

    task automatic finish_job(
        input string label_text,
        input bit busy_noise,
        input bit hold_start
    );
        for (integer cycle = 1; cycle <= WORK_CYCLES; cycle = cycle + 1) begin
            @(negedge clk);
            // try writes and extra starts while busy, including the last STORE edge
            start = hold_start || busy_noise;
            a_we = busy_noise;
            x_we = busy_noise;
            a_addr = 6'd0;
            x_addr = 3'd0;
            a_wdata = -8'sd99;
            x_wdata = -8'sd88;
            tick();
            check_status(cycle < WORK_CYCLES, cycle == WORK_CYCLES,
                         $sformatf("%s: work edge E%0d", label_text, cycle));
        end
        if (($time - accepted_at) != 800)
            $fatal(1, "%s: expected 800 ns from E0 to E80, got %0t",
                   label_text, $time - accepted_at);
        completed_jobs = completed_jobs + 1;
    endtask

    task automatic check_results(input string label_text);
        for (integer r = 0; r < 8; r = r + 1) begin
            @(negedge clk);
            idle_requests();
            y_rd_addr = r[2:0];
            #1; // allow the result read to settle
            check_status(1'b0, 1'b1, {label_text, ": sticky done"});
            if (y_rd_data !== expected[r])
                $fatal(1, "%s: y[%0d] expected %0d, got %0d",
                       label_text, r, expected[r], y_rd_data);
            checked_outputs = checked_outputs + 1;
        end
    endtask

    task automatic run_job(input string label_text, input bit busy_noise);
        begin_job(label_text);
        finish_job(label_text, busy_noise, 1'b0);
        check_results(label_text);
    endtask

    task automatic test_write_start_collisions;
        // test start with an A write, an x write, then both writes
        for (integer mode = 1; mode <= 3; mode = mode + 1) begin
            set_identity_case();
            load_operands();
            @(negedge clk);
            start = 1'b1;
            a_we = (mode != 2);
            x_we = (mode != 1);
            a_addr = 6'd0;
            x_addr = 3'd0;
            a_wdata = 8'sd2;
            x_wdata = 8'sd3;
            tick();
            check_status(1'b0, 1'b1, "write must take priority over start");
            @(negedge clk);
            idle_requests();
            tick();
            check_status(1'b0, 1'b1, "rejected start must not be queued");
            // first result is 2*1, 1*3, or 2*3 depending on which values were written
            case (mode)
                1: expected[0] = 32'sd2;
                2: expected[0] = 32'sd3;
                3: expected[0] = 32'sd6;
            endcase
            run_job($sformatf("write/start collision mode %0d", mode), 1'b0);
        end
    endtask

    task automatic test_held_start;
        set_identity_case();
        load_operands();
        begin_job("held start first job");
        finish_job("held start first job", 1'b0, 1'b1);

        // read all results before the next rising edge (0.8 ns total)
        // start is still high, so the next edge should start another calculation
        for (integer r = 0; r < 8; r = r + 1) begin
            y_rd_addr = r[2:0];
            #0.1;
            check_status(1'b0, 1'b1, "held start completion window");
            if (y_rd_data !== expected[r])
                $fatal(1, "held start first job: bad result at row %0d", r);
            checked_outputs = checked_outputs + 1;
        end
        tick();
        check_status(1'b1, 1'b0, "held start must restart on E81");
        accepted_at = $time;
        finish_job("held start second job", 1'b0, 1'b0);
        check_results("held start second job");
    endtask

    task automatic test_abort(
        input string state_name,
        input integer work_edges_before_reset
    );
        set_identity_case();
        load_operands();
        begin_job({"abort in ", state_name});
        for (integer i = 0; i < work_edges_before_reset; i = i + 1) begin
            @(negedge clk);
            idle_requests();
            tick();
            check_status(1'b1, 1'b0, "before abort");
        end
        @(negedge clk);
        reset = 1'b1;
        start = 1'b1;
        a_we = 1'b1;
        x_we = 1'b1;
        #1;
        check_status(1'b1, 1'b0, "reset must wait for rising edge");
        tick();
        check_status(1'b0, 1'b0, {"reset during ", state_name});
        @(negedge clk);
        reset = 1'b0;
        idle_requests();
        repeat (3) begin
            tick();
            check_status(1'b0, 1'b0, "aborted job must not complete/restart");
        end
        // reload A and x after reset
        load_operands();
        run_job({"recovery after ", state_name}, 1'b0);
    endtask

    task automatic run_fixtures;
        string vector_path;
        string extra_token;
        integer fd;
        integer scanned;
        if (!$value$plusargs("VECTORS=%s", vector_path))
            vector_path = "build/vectors/vectors.txt";
        fd = $fopen(vector_path, "r");
        if (fd == 0)
            $fatal(1, "cannot open %s; run make vectors and pass +VECTORS=path", vector_path);
        scanned = $fscanf(fd, "%d", fixture_count);
        if (scanned != 1 || fixture_count <= 0)
            $fatal(1, "invalid or empty vector file header");

        // first value is the number of test cases
        // each case has 64 A values, 8 x values, and 8 expected results in hex
        for (integer test_id = 0; test_id < fixture_count; test_id = test_id + 1) begin
            for (integer i = 0; i < 64; i = i + 1) begin
                scanned = $fscanf(fd, "%h", matrix_data[i]);
                if (scanned != 1 || (^matrix_data[i] === 1'bx))
                    $fatal(1, "fixture %0d: invalid A word %0d", test_id, i);
            end
            for (integer i = 0; i < 8; i = i + 1) begin
                scanned = $fscanf(fd, "%h", vector_data[i]);
                if (scanned != 1 || (^vector_data[i] === 1'bx))
                    $fatal(1, "fixture %0d: invalid x word %0d", test_id, i);
            end
            for (integer i = 0; i < 8; i = i + 1) begin
                scanned = $fscanf(fd, "%h", expected[i]);
                if (scanned != 1 || (^expected[i] === 1'bx))
                    $fatal(1, "fixture %0d: invalid result word %0d", test_id, i);
            end
            load_operands();
            run_job($sformatf("Python fixture %0d", test_id), 1'b0);
        end
        scanned = $fscanf(fd, "%s", extra_token);
        if (scanned == 1)
            $fatal(1, "extra data after the declared vector count");
        $fclose(fd);
    endtask

    initial begin
        reset = 1'b1;
        idle_requests();
        a_addr = 6'd0;
        x_addr = 3'd0;
        a_wdata = 8'sd0;
        x_wdata = 8'sd0;
        y_rd_addr = 3'd0;

        reset_core();
        set_ramp_case();
        load_operands();
        run_job("ramp rows: first result is 36", 1'b0);
        run_job("reuse operands without reloading", 1'b0);
        run_job("ignore busy writes and starts", 1'b1);
        run_job("busy noise did not corrupt stored operands", 1'b0);
        test_write_start_collisions();
        test_held_start();
        test_abort("ROW_CLEAR", 0);
        test_abort("MAC", 1);
        test_abort("STORE", 9);
        test_abort("final STORE", 79);
        run_fixtures();

        $display("PASS: GEMV testbench completed: %0d jobs, %0d outputs, %0d Python fixtures, 4 reset aborts",
                 completed_jobs, checked_outputs, fixture_count);
        $finish;
    end

    // dump waveforms to a VCD file
    initial begin
        if (!$test$plusargs("NO_WAVES")) begin
            $dumpfile("gemv-regression.vcd");
            $dumpvars(0, tb_gemv_regression);
        end
    end

    // stop if the test gets stuck (10 ms timeout)
    initial begin
        #10000000;
        $fatal(1, "GEMV testbench exceeded the 10 ms simulation timeout");
    end
endmodule

`default_nettype wire

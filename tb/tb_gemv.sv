`timescale 1ns/1ps
`default_nettype none

module tb_gemv;

    logic clk;
    logic rst;
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

    logic signed [7:0] A [0:63];
    logic signed [7:0] x [0:7];
    logic signed [31:0] expected [0:7];
    integer tests_passed = 0;

    gemv dut (
        .clk(clk),
        .rst(rst),
        .a_we(a_we),
        .a_addr(a_addr),
        .a_wdata(a_wdata),
        .x_we(x_we),
        .x_addr(x_addr),
        .x_wdata(x_wdata),
        .start(start),
        .busy(busy),
        .done(done),
        .y_rd_addr(y_rd_addr),
        .y_rd_data(y_rd_data)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // wait 5 time units, then invert clock
    end

    // load the matrix, then the vector, one value per clock
    task automatic load_inputs;
        for (integer i = 0; i < 64; i = i + 1) begin
            @(negedge clk);
            a_we = 1'b1;
            a_addr = i;
            a_wdata = A[i];
        end
        @(negedge clk);
        a_we = 1'b0;

        for (integer i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            x_we = 1'b1;
            x_addr = i;
            x_wdata = x[i];
        end
        @(negedge clk);
        x_we = 1'b0;
    endtask

    // start the calculation, wait 80 cycles, then check all 8 results
    task automatic run_test(input string case_name);
        @(negedge clk);
        start = 1'b1;
        @(posedge clk);
        #1;
        if (busy !== 1'b1 || done !== 1'b0) begin
            $fatal(1, "%s: start was not accepted", case_name);
        end
        @(negedge clk);
        start = 1'b0;

        for (integer cycle = 1; cycle <= 80; cycle = cycle + 1) begin
            @(posedge clk);
            #1;
            if (cycle < 80) begin
                if (busy !== 1'b1 || done !== 1'b0) begin
                    $fatal(1, "%s: stopped early at cycle %0d", case_name, cycle);
                end
            end else begin
                if (busy !== 1'b0 || done !== 1'b1) begin
                    $fatal(1, "%s: did not finish at cycle 80", case_name);
                end
            end
        end

        for (integer i = 0; i < 8; i = i + 1) begin
            @(negedge clk);
            y_rd_addr = i;
            #1;
            if (busy !== 1'b0 || done !== 1'b1) begin
                $fatal(1, "%s: done did not stay high", case_name);
            end
            if (y_rd_data !== expected[i]) begin
                $fatal(1, "%s: y[%0d] expected %0d, received %0d",
                       case_name, i, expected[i], y_rd_data);
            end
        end

        tests_passed = tests_passed + 1;
        $display("PASS: %s", case_name);
    endtask

    initial begin
        rst = 1'b1;
        a_we = 1'b0;
        x_we = 1'b0;
        start = 1'b0;
        a_addr = 6'd0;
        x_addr = 3'd0;
        a_wdata = 8'sd0;
        x_wdata = 8'sd0;
        y_rd_addr = 3'd0;

        repeat (2) @(posedge clk);
        #1;
        if (busy !== 1'b0 || done !== 1'b0) begin
            $fatal(1, "reset failed");
        end
        @(negedge clk);
        rst = 1'b0;

        // row 0 is [1,2,3,4,5,6,7,8], row 1 is twice that, etc.
        for (integer row = 0; row < 8; row = row + 1) begin
            for (integer col = 0; col < 8; col = col + 1) begin
                A[row * 8 + col] = (row + 1) * (col + 1);
            end
            x[row] = 8'sd1;
            expected[row] = 36 * (row + 1);
        end
        load_inputs();
        run_test("row sums");

        // identity matrix should return x, including its negative values
        for (integer row = 0; row < 8; row = row + 1) begin
            for (integer col = 0; col < 8; col = col + 1) begin
                if (row == col) begin
                    A[row * 8 + col] = 8'sd1;
                end else begin
                    A[row * 8 + col] = 8'sd0;
                end
            end
            x[row] = row - 4;
            expected[row] = row - 4;
        end
        load_inputs();
        run_test("identity matrix");

        // largest positive sum: 8 * (-128) * (-128) = 131072
        for (integer i = 0; i < 64; i = i + 1) begin
            A[i] = -8'sd128;
        end
        for (integer i = 0; i < 8; i = i + 1) begin
            x[i] = -8'sd128;
            expected[i] = 32'sd131072;
        end
        load_inputs();
        run_test("maximum positive sum");

        // A is still all -128, change x to 127 for the most negative sum
        for (integer i = 0; i < 8; i = i + 1) begin
            x[i] = 8'sd127;
            expected[i] = -32'sd130048;
        end
        load_inputs();
        run_test("maximum negative sum");

        // run again without reloading to check that each row starts from zero
        run_test("reuse inputs");

        $display("PASS: GEMV testbench completed (%0d tests)", tests_passed);
        $finish;
    end

    // dump waveforms to a VCD file
    initial begin
        $dumpfile("gemv.vcd");
        $dumpvars(0, tb_gemv);
    end

    initial begin
        #100000;
        $fatal(1, "GEMV testbench timed out");
    end

endmodule

`default_nettype wire

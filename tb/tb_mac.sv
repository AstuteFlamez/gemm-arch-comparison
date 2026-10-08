`timescale 1ns/1ps
`default_nettype none

module tb_mac;

    logic clk;
    logic rst;
    logic clr;
    logic enable;
    logic signed [7:0] a;
    logic signed [7:0] b;
    logic signed [31:0] acc;

    mac dut (
        .clk(clk),
        .rst(rst),
        .clr(clr),
        .enable(enable),
        .a(a),
        .b(b),
        .acc(acc)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk; // wait 5 time units, then invert clock
    end



    //  task to apply inputs and check the output
    task automatic apply_and_check(
        input logic signed [7:0] next_a,
        input logic signed [7:0] next_b,
        input logic next_enable,
        input logic next_clr,
        input logic next_rst,
        input logic signed [31:0] expected,
        input string case_name
    );
        logic signed [31:0] previous_acc;

        @(negedge clk);
        previous_acc = acc;
        a = next_a;
        b = next_b;
        enable = next_enable;
        clr = next_clr;
        rst = next_rst;

        #1;
        if (acc !== previous_acc) begin
            $fatal(1, "%s: accumulator changed before rising edge", case_name);
        end

        @(posedge clk);
        #1;

        if (acc !== expected) begin
            $fatal(1, "%s failed: expected %0d, received %0d", case_name, expected, acc);
        end
    endtask



    initial begin
        rst = 1'b1;
        clr = 1'b0;
        enable = 1'b0;
        a = 8'sd0;
        b = 8'sd0;

        @(posedge clk);

        @(negedge clk);
        rst = 1'b0;
        enable = 1'b1;
        a = 8'sd3;
        b = 8'sd4;

        @(posedge clk);
        #1;

        if (acc !== 32'sd12) begin
            $fatal(1, "MAC failed: expected 12, received %0d", acc);
        end

        //              a,        b,        enable, clear, reset, expected,   case_name
        apply_and_check(8'sd0,    8'sd9,    1'b1,   1'b0,  1'b0,  32'sd12,    "zero a");
        apply_and_check(8'sd9,    8'sd0,    1'b1,   1'b0,  1'b0,  32'sd12,    "zero b");
        apply_and_check(8'sd2,   -8'sd3,    1'b1,   1'b0,  1'b0,  32'sd6,     "positive negative");
        apply_and_check(-8'sd2,  -8'sd3,    1'b1,   1'b0,  1'b0,  32'sd12,    "negative negative");
        apply_and_check(8'sd5,    8'sd2,    1'b1,   1'b0,  1'b0,  32'sd22,    "repeated accumulation");
        apply_and_check(-8'sd1,   8'sd2,    1'b1,   1'b0,  1'b0,  32'sd20,    "second accumulation");

        apply_and_check(8'sd127,  8'sd127,  1'b1,   1'b0,  1'b0,  32'sd16149, "endpoint 127 times 127");
        apply_and_check(8'sd127, -8'sd128,  1'b1,   1'b0,  1'b0,  -32'sd107,  "endpoint 127 times negative 128");
        apply_and_check(-8'sd128, 8'sd127,  1'b1,   1'b0,  1'b0,  -32'sd16363,"endpoint negative 128 times 127");
        apply_and_check(-8'sd128,-8'sd128,  1'b1,   1'b0,  1'b0,  32'sd21,    "endpoint negative 128 times negative 128");
        apply_and_check(8'sd127,  8'sd127,  1'b1,   1'b0,  1'b0,  32'sd16150, "endpoint repeat 127 times 127");
        apply_and_check(8'sd127, -8'sd128,  1'b1,   1'b0,  1'b0,  -32'sd106,  "endpoint repeat 127 times negative 128");
        apply_and_check(-8'sd128, 8'sd127,  1'b1,   1'b0,  1'b0,  -32'sd16362,"endpoint repeat negative 128 times 127");
        apply_and_check(-8'sd128,-8'sd128,  1'b1,   1'b0,  1'b0,  32'sd22,    "endpoint repeat negative 128 times negative 128");

        apply_and_check(8'sd7,    8'sd3,    1'b0,   1'b0,  1'b0,  32'sd22,    "disabled hold");
        apply_and_check(8'sd6,    8'sd6,    1'b1,   1'b0,  1'b0,  32'sd58,    "rebuild nonzero sum");
        apply_and_check(8'sd0,    8'sd0,    1'b0,   1'b1,  1'b0,  32'sd0,     "clear with enable low");
        apply_and_check(8'sd4,    8'sd5,    1'b1,   1'b0,  1'b0,  32'sd20,    "create sum before clear");
        apply_and_check(8'sd4,    8'sd5,    1'b1,   1'b1,  1'b0,  32'sd0,     "clear with enable high");
        apply_and_check(8'sd6,    8'sd6,    1'b1,   1'b0,  1'b0,  32'sd36,    "create sum before reset");
        apply_and_check(8'sd9,    8'sd9,    1'b1,   1'b0,  1'b1,  32'sd0,     "reset with enable high");

        @(posedge clk);
        #1;
        if (acc !== 32'sd0) begin
            $fatal(1, "held reset failed: expected 0, received %0d", acc);
        end

        @(posedge clk);
        #1;
        if (acc !== 32'sd0) begin
            $fatal(1, "held reset failed: expected 0, received %0d", acc);
        end

        //              a,        b,        enable, clear, reset, expected,   case_name
        apply_and_check(8'sd2,    8'sd3,    1'b1,   1'b0,  1'b0,  32'sd6,     "normal after held reset");
        apply_and_check(8'sd4,    8'sd5,    1'b1,   1'b1,  1'b0,  32'sd0,     "held clear first edge");

        @(posedge clk);
        #1;
        if (acc !== 32'sd0) begin
            $fatal(1, "held clear failed: expected 0, received %0d", acc);
        end

        //              a,        b,        enable, clear, reset, expected,   case_name
        apply_and_check(8'sd2,    8'sd2,    1'b1,   1'b0,  1'b0,  32'sd4,     "normal after held clear");

        @(negedge clk);
        rst = 1'b1;
        enable = 1'b1;
        a = 8'sd9;
        b = 8'sd9;
        #1;
        if (acc !== 32'sd4) begin
            $fatal(1, "reset changed acc before clock: expected 4, received %0d", acc);
        end

        @(posedge clk);
        #1;
        if (acc !== 32'sd0) begin
            $fatal(1, "reset failed after clock: expected 0, received %0d", acc);
        end


        //              a,        b,        enable, clear, reset, expected,   case_name
        apply_and_check(8'sd5,    8'sd5,    1'b1,   1'b0,  1'b0,  32'sd25,    "sum before synchronous clear");

        @(negedge clk);
        clr = 1'b1;
        enable = 1'b1;
        a = 8'sd8;
        b = 8'sd8;
        #1;
        if (acc !== 32'sd25) begin
            $fatal(1, "clear changed acc before clock: expected 25, received %0d", acc);
        end

        @(posedge clk);
        #1;
        if (acc !== 32'sd0) begin
            $fatal(1, "clear failed after clock: expected 0, received %0d", acc);
        end

        //              a,        b,        enable, clear, reset, expected,   case_name
        apply_and_check(8'sd127,  8'sd127,  1'b1,   1'b0,  1'b0,  32'sd16129, "wide sum first product");
        apply_and_check(8'sd127,  8'sd127,  1'b1,   1'b0,  1'b0,  32'sd32258, "wide sum second product");
        apply_and_check(8'sd127,  8'sd127,  1'b1,   1'b0,  1'b0,  32'sd48387, "wide sum exceeds 16 bits");

        apply_and_check(8'sd9, 8'sd9, 1'b1, 1'b1, 1'b1, 32'sd0, "reset and clear together");
        apply_and_check(8'sd2, 8'sd3, 1'b1, 1'b0, 1'b0, 32'sd6, "resume after reset and clear");

        $display("PASS: MAC testbench completed");
        $finish;
    end



    //  dump waveforms to a VCD file
    initial begin
        $dumpfile("mac.vcd");
        $dumpvars(0, tb_mac);
    end



    initial begin
        #1000;
        $fatal(1, "MAC testbench timed out");
    end



endmodule

`default_nettype wire

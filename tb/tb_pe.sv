`timescale 1ns/1ps
`default_nettype none

module tb_pe;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic enable = 1'b0;
    logic signed [7:0] a_in = 0, b_in = 0;
    logic signed [7:0] a_out, b_out;
    logic signed [31:0] acc;
    integer checks = 0;

    pe dut (
        .clk(clk), .reset(reset), .enable(enable),
        .a_in(a_in), .b_in(b_in),
        .a_out(a_out), .b_out(b_out),
        .acc(acc)
    );

    always #5 clk = ~clk;

    task automatic step(
        input logic signed [7:0] next_a, next_b,
        input logic next_enable, next_reset,
        input logic signed [31:0] expected_acc,
        input string case_name
    );
        logic [47:0] previous_outputs;
        logic [15:0] expected_forwarding;

        @(negedge clk);
        previous_outputs = {acc, a_out, b_out};
        a_in = next_a;
        b_in = next_b;
        enable = next_enable;
        reset = next_reset;
        expected_forwarding = next_reset ? 16'd0 :
            (next_enable ? {next_a, next_b} : {a_out, b_out});

        // Data and reset must both wait for the clock.
        #1;
        if ({acc, a_out, b_out} !== previous_outputs)
            $fatal(1, "%s: outputs changed before the rising edge", case_name);

        @(posedge clk);
        #1;
        if (acc !== expected_acc)
            $fatal(1, "%s: expected acc=%0d, got %0d", case_name, expected_acc, acc);
        if ({a_out, b_out} !== expected_forwarding)
            $fatal(1, "%s: incorrect registered forwarding", case_name);
        checks = checks + 1;
    endtask

    initial begin
        @(posedge clk);
        #1;
        if ({acc, a_out, b_out} !== 48'd0)
            $fatal(1, "initial reset did not clear all outputs");

        //      A,    B, enable, reset, expected accumulator
        step(   2,    3, 1, 0,      6, "first pair");
        step(   4,    5, 1, 0,     26, "consecutive pair");
        step(   4,    5, 0, 0,     26, "disabled holds all state");
        step( 127, -128, 0, 0,     26, "disabled ignores changed inputs");
        step(-128,  127, 0, 0,     26, "held disable");
        step(   0,   -7, 1, 0,     26, "zero padding forwards without adding");
        step( 127, -128, 1, 0, -16230, "signed negative product");
        step(-128, -128, 1, 0,    154, "two negative operands");
        step(   9,    9, 1, 1,      0, "reset overrides enable");
        step(   8,    7, 0, 1,      0, "held reset while disabled");
        step(  -3,    6, 1, 0,    -18, "resume after reset");
        step(   9,    9, 0, 1,      0, "reset clears while disabled");
        step(   8,    7, 1, 1,      0, "held reset");
        step( 127,  127, 1, 0,  16129, "resume after second reset");
        step( 127,  127, 1, 0,  32258, "wide sum second pair");
        step( 127,  127, 1, 0,  48387, "sum exceeds signed 16 bits");
        step(   1,    2, 0, 1,      0, "final reset while disabled");

        $display("PASS: PE initial reset and %0d cycle checks completed", checks);
        $finish;
    end

    initial begin
        $dumpfile("pe.vcd");
        $dumpvars(0, tb_pe);
        #1000;
        $fatal(1, "PE testbench timed out");
    end
endmodule

`default_nettype wire

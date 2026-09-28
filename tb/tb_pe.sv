`timescale 1ns/1ps
`default_nettype none

module tb_pe;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic clear = 1'b0;
    logic signed [7:0] a_in = 0, b_in = 0;
    logic a_valid_in = 0, b_valid_in = 0;
    logic signed [7:0] a_out, b_out;
    logic a_valid_out, b_valid_out;
    logic signed [31:0] acc;
    integer checks = 0;

    pe dut (
        .clk(clk), .reset(reset), .clear(clear),
        .a_in(a_in), .b_in(b_in),
        .a_valid_in(a_valid_in), .b_valid_in(b_valid_in),
        .a_out(a_out), .b_out(b_out),
        .a_valid_out(a_valid_out), .b_valid_out(b_valid_out),
        .acc(acc)
    );

    always #5 clk = ~clk;

    task automatic step(
        input logic signed [7:0] next_a, next_b,
        input logic next_a_valid, next_b_valid,
        input logic next_clear, next_reset,
        input logic signed [31:0] expected_acc,
        input string case_name
    );
        logic [49:0] previous_outputs;
        logic [17:0] expected_forwarding;

        @(negedge clk);
        previous_outputs = {acc, a_out, b_out, a_valid_out, b_valid_out};
        a_in = next_a;
        b_in = next_b;
        a_valid_in = next_a_valid;
        b_valid_in = next_b_valid;
        clear = next_clear;
        reset = next_reset;
        expected_forwarding = (next_reset || next_clear)
            ? 18'd0 : {next_a, next_b, next_a_valid, next_b_valid};

        // Data, validity, reset, and clear must all wait for the clock.
        #1;
        if ({acc, a_out, b_out, a_valid_out, b_valid_out} !== previous_outputs)
            $fatal(1, "%s: outputs changed before the rising edge", case_name);

        @(posedge clk);
        #1;
        if (acc !== expected_acc)
            $fatal(1, "%s: expected acc=%0d, got %0d", case_name, expected_acc, acc);
        if ({a_out, b_out, a_valid_out, b_valid_out} !== expected_forwarding)
            $fatal(1, "%s: incorrect registered data or validity", case_name);
        checks = checks + 1;
    endtask

    initial begin
        @(posedge clk);
        #1;
        if ({acc, a_out, b_out, a_valid_out, b_valid_out} !== 50'd0)
            $fatal(1, "initial reset did not clear all outputs");

        //      A,    B, A valid, B valid, clear, reset, expected accumulator
        step(   2,    3, 1, 1, 0, 0,      6, "first pair");
        step(   4,    5, 1, 1, 0, 0,     26, "consecutive pair");
        step(   4,    5, 0, 0, 0, 0,     26, "stale operands are ignored");
        step( 127, -128, 1, 0, 0, 0,     26, "A forwards while B is invalid");
        step(-128,  127, 0, 1, 0, 0,     26, "B forwards while A is invalid");
        step(   0,   -7, 1, 1, 0, 0,     26, "zero is a valid operand");
        step( 127, -128, 1, 1, 0, 0, -16230, "signed negative product");
        step(-128, -128, 1, 1, 0, 0,    154, "two negative operands");
        step(   9,    9, 1, 1, 1, 0,      0, "clear overrides valid operands");
        step(   8,    7, 1, 1, 1, 0,      0, "held clear");
        step(  -3,    6, 1, 1, 0, 0,    -18, "resume after clear");
        step(   9,    9, 1, 1, 0, 1,      0, "reset overrides valid operands");
        step(   8,    7, 1, 1, 0, 1,      0, "held reset");
        step( 127,  127, 1, 1, 0, 0,  16129, "resume after reset");
        step( 127,  127, 1, 1, 0, 0,  32258, "wide sum second pair");
        step( 127,  127, 1, 1, 0, 0,  48387, "sum exceeds signed 16 bits");
        step(   1,    2, 0, 0, 1, 0,      0, "clear with no valid operands");

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

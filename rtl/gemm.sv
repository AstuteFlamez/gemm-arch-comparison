/*
TODO: instantiate four FIFOs and connect memory controller, FIFOs, and systolic array
*/
`timescale 1ns/1ps
`default_nettype none

module gemm (
    input  logic clk,
    input  logic reset,

    /*
    - A, B, and C each have 64 elements requiring 6-bit addresses
    - A and B have 8-bit signed values
    - C holds 32-bit signed results
    */
    input  logic a_we,                 // A matrix write enable
    input  logic [5:0] a_wr_addr,      // 6-bit write address for A matrix (64 elements)
    input  logic signed [7:0] a_wdata, // 8-bit signed A matrix write data
    
    input  logic b_we,                 // B matrix write enable
    input  logic [5:0] b_wr_addr,      // 6-bit write address for B matrix (64 elements)
    input  logic signed [7:0] b_wdata, // 8-bit signed B matrix write data

    // control signals
    input  logic start,
    output logic busy,
    output logic done,

    input  logic [5:0] c_rd_addr,        // 6-bit address for output C matrix (64 elements)
    output logic signed [31:0] c_rd_data // 32-bit signed output C matrix read data
);

    logic mac_clear;             // clear MAC
    logic mac_enable;            // enable MAC
    logic signed [7:0] mac_a;    // MAC a value
    logic signed [7:0] mac_b;    // MAC b value
    logic signed [31:0] mac_acc; // MAC accumualator

    logic [5:0] a_rd_addr;       // A element to read
    logic [5:0] b_rd_addr;       // B element to read
    logic [5:0] c_wr_addr;       // C element to write
    logic compute_re;            // A/B read enable
    logic c_compute_we;          // C write enable

    mac mac_instance (
        .clk(clk),
        .reset(reset),
        .clear(mac_clear),
        .enable(mac_enable),
        .a(mac_a),
        .b(mac_b),
        .acc(mac_acc)
    );

    memory_wrapper memory_instance (
        .clk(clk),
        .reset(reset),
        .busy(busy),
        .ab_re(compute_re),

        .a_we(a_we),
        .a_wr_addr(a_wr_addr),
        .a_wr_data(a_wdata),
        .a_rd_addr(a_rd_addr),
        .a_rd_data(mac_a),

        .b_we(b_we),
        .b_wr_addr(b_wr_addr),
        .b_wr_data(b_wdata),
        .b_rd_addr(b_rd_addr),
        .b_rd_data(mac_b),

        .c_we(c_compute_we),
        .c_wr_addr(c_wr_addr),
        .c_wr_data(mac_acc),
        .c_rd_addr(c_rd_addr),
        .c_rd_data(c_rd_data)
    );

    gemm_controller controller_instance (
        .clk(clk),
        .reset(reset),
        .start(start),
        .a_we(a_we),
        .b_we(b_we),
        .busy(busy),
        .done(done),
        .compute_re(compute_re),
        .c_compute_we(c_compute_we),
        .mac_clear(mac_clear),
        .mac_enable(mac_enable),
        .a_rd_addr(a_rd_addr),
        .b_rd_addr(b_rd_addr),
        .c_wr_addr(c_wr_addr)
    );

endmodule

`default_nettype wire

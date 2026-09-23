`timescale 1ns/1ps
`default_nettype none

module gemm (
    input  logic clk,
    input  logic reset,

    input  logic a_we, // A matrix write enable
    input  logic [5:0] a_addr, // 6-bit address for A matrix (64 elements)
    input  logic signed [7:0] a_wdata, // 8-bit signed matrix write data
    
    input  logic b_we, // B matrix write enable
    input  logic [5:0] b_addr, // 6-bit address for B matrix (64 elements)
    input  logic signed [7:0] b_wdata, // 8-bit signed matrix write data

    // calculation control signals
    input  logic start,
    output logic busy,
    output logic done,

    input  logic [5:0] c_rd_addr, // 6-bit address for output C matrix (64 elements)
    output logic signed [31:0] c_rd_data // 32-bit signed output matrix read data
);

    logic mac_clear;
    logic mac_enable;
    logic signed [7:0] mac_a;
    logic signed [7:0] mac_b;
    logic signed [31:0] mac_acc;

    logic [5:0] a_compute_addr;
    logic [5:0] b_compute_addr;
    logic [5:0] c_compute_addr;
    logic compute_re;
    logic c_compute_we;

    mac mac_instance (
        .clk(clk),
        .reset(reset),
        .clear(mac_clear),
        .enable(mac_enable),
        .a(mac_a),
        .b(mac_b),
        .acc(mac_acc)
    );

    gemm_memory sram_instance (
        .clk(clk),
        .reset(reset),
        .busy(busy),
        .a_we(a_we),
        .a_addr(a_addr),
        .a_wdata(a_wdata),
        .b_we(b_we),
        .b_addr(b_addr),
        .b_wdata(b_wdata),
        .c_rd_addr(c_rd_addr),
        .c_rd_data(c_rd_data),
        .compute_re(compute_re),
        .a_compute_addr(a_compute_addr),
        .b_compute_addr(b_compute_addr),
        .c_compute_we(c_compute_we),
        .c_compute_addr(c_compute_addr),
        .a_compute_data(mac_a),
        .b_compute_data(mac_b),
        .c_compute_wdata(mac_acc)
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
        .a_compute_addr(a_compute_addr),
        .b_compute_addr(b_compute_addr),
        .c_compute_addr(c_compute_addr)
    );

endmodule

`default_nettype wire

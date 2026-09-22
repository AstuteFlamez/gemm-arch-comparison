`timescale 1ns/1ps
`default_nettype none

module gemm_memory(
    input logic clk,
    input logic reset,
    input logic busy,

    input logic a_we,
    input logic b_we,
    input logic [5:0] a_addr,
    input logic [5:0] b_addr,
    input logic [7:0] a_wdata,
    input logic [7:0] b_wdata,

    input logic [5:0] c_rd_addr,
    output logic signed [31:0] c_rd_data,

    input logic compute_re,
    input logic [5:0] a_compute_addr,
    input logic [5:0] b_compute_addr,
    output logic signed [7:0] a_compute_data,
    output logic signed [7:0] b_compute_data,

    input logic c_compute_we,
    input logic [5:0] c_compute_addr,
    input logic signed [31:0] c_compute_wdata
);

    logic [5:0] a_mem_addr;
    logic [7:0] a_mem_rdata;
    logic a_mem_we;
    logic a_mem_re;
    assign a_mem_addr = busy ? a_compute_addr : a_addr;
    assign a_mem_we = !reset && !busy && a_we;
    assign a_mem_re = !reset && busy && compute_re;

    logic [5:0] b_mem_addr;
    logic [7:0] b_mem_rdata;
    logic b_mem_we;
    logic b_mem_re;
    assign b_mem_addr = busy ? b_compute_addr : b_addr;
    assign b_mem_we = !reset && !busy && b_we;
    assign b_mem_re = !reset && busy && compute_re;

    logic [5:0] c_mem_addr;
    logic [31:0] c_mem_rdata;
    logic c_mem_we;
    logic c_mem_re;
    assign c_mem_addr = busy ? c_compute_addr : c_rd_addr;
    assign c_mem_we = !reset && busy && c_compute_we;
    assign c_mem_re = !reset && !busy;

    sram #(
        .DATA_WIDTH(8),
        .DEPTH(64)
    ) sram_a_instance (
        .clk(clk),
        .re(a_mem_re),
        .we(a_mem_we),
        .addr(a_mem_addr),
        .rdata(a_mem_rdata),
        .wdata(a_wdata)
    );

    sram #(
        .DATA_WIDTH(8),
        .DEPTH(64)
    ) sram_b_instance (
        .clk(clk),
        .re(b_mem_re),
        .we(b_mem_we),
        .addr(b_mem_addr),
        .rdata(b_mem_rdata),
        .wdata(b_wdata)
    );

    sram #(
        .DATA_WIDTH(32),
        .DEPTH(64)
    ) sram_c_instance (
        .clk(clk),
        .re(c_mem_re),
        .we(c_mem_we),
        .addr(c_mem_addr),
        .rdata(c_mem_rdata),
        .wdata(c_compute_wdata)
    );

    assign a_compute_data = $signed(a_mem_rdata);
    assign b_compute_data = $signed(b_mem_rdata);
    assign c_rd_data = $signed(c_mem_rdata);

endmodule

`default_nettype wire
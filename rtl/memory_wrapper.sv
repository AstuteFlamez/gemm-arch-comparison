`timescale 1ns/1ps
`default_nettype none

module memory_wrapper (
    // Shared control
    input  logic               clk,
    input  logic               reset,
    input  logic               busy,

    input  logic               ab_re,          // A/B read enable

    // A memory
    input  logic               a_we,           // A write enable
    input  logic        [5:0]  a_wr_addr,      // A write address
    input  logic        [7:0]  a_wr_data,      // A write data
    input  logic        [5:0]  a_rd_addr,      // A read address
    output logic signed [7:0]  a_rd_data,      // A read data

    // B memory
    input  logic               b_we,           // B write enable
    input  logic        [5:0]  b_wr_addr,      // B write address
    input  logic        [7:0]  b_wr_data,      // B write data
    input  logic        [5:0]  b_rd_addr,      // B read address
    output logic signed [7:0]  b_rd_data,      // B read data

    // C memory
    input  logic               c_we,           // C write enable
    input  logic        [5:0]  c_wr_addr,      // C write address
    input  logic signed [31:0] c_wr_data,      // C write data
    input  logic        [5:0]  c_rd_addr,      // C read address
    output logic signed [31:0] c_rd_data       // C read data
);

    logic host_access;    // when not busy, host can access memory
    logic compute_access; // when busy, GEMM can access memory
    logic operand_re;     // when busy and compute read enable, GEMM can read A/B memory

    assign host_access = !reset && !busy;
    assign compute_access = !reset && busy;
    assign operand_re = compute_access && ab_re;

    sram #(
        .DATA_WIDTH(8),
        .DEPTH(64)
    ) sram_a_instance (
        .clk(clk),
        .re(operand_re),
        .we(host_access && a_we),
        .addr(busy ? a_rd_addr : a_wr_addr),
        .rdata(a_rd_data),
        .wdata(a_wr_data)
    );

    sram #(
        .DATA_WIDTH(8),
        .DEPTH(64)
    ) sram_b_instance (
        .clk(clk),
        .re(operand_re),
        .we(host_access && b_we),
        .addr(busy ? b_rd_addr : b_wr_addr),
        .rdata(b_rd_data),
        .wdata(b_wr_data)
    );

    sram #(
        .DATA_WIDTH(32),
        .DEPTH(64)
    ) sram_c_instance (
        .clk(clk),
        .re(host_access),
        .we(compute_access && c_we),
        .addr(busy ? c_wr_addr : c_rd_addr),
        .rdata(c_rd_data),
        .wdata(c_wr_data)
    );

endmodule

`default_nettype wire

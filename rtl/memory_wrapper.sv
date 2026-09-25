`timescale 1ns/1ps
`default_nettype none

module gemm_memory (
    input logic clk,

    // control signals
    input logic reset,
    input logic busy,

    input logic a_we,                          // A write enable
    input logic b_we,                          // B write enable
    input logic [5:0] a_addr,                  // A load address
    input logic [5:0] b_addr,                  // B load address
    input logic [7:0] a_wdata,                 // A load value
    input logic [7:0] b_wdata,                 // B load value

    input logic [5:0] c_rd_addr,               // C address
    output logic signed [31:0] c_rd_data,      // C value

    input logic compute_re,                    // A/B read enable
    input logic [5:0] a_compute_addr,          // A compute address
    input logic [5:0] b_compute_addr,          // B compute address
    output logic signed [7:0] a_compute_data,  // A compute value
    output logic signed [7:0] b_compute_data,  // B compute value

    input logic c_compute_we,                  // C write enable
    input logic [5:0] c_compute_addr,          // C compute address
    input logic signed [31:0] c_compute_wdata  // C compute value
);

    logic [5:0] a_mem_addr;                             // A address current selected
    logic [7:0] a_mem_rdata;                            // A value from last read
    logic a_mem_we;                                     // A memory write enable
    logic a_mem_re;                                     // A memory read enable
    assign a_mem_addr = busy ? a_compute_addr : a_addr; // in-use conditional assignment
    assign a_mem_we = !reset && !busy && a_we;          // write if not reset, not busy, and write enable high 
    assign a_mem_re = !reset && busy && compute_re;     // read if not reset, busy, and compute read enable high

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

    assign a_compute_data = $signed(a_mem_rdata); // A memory -> MAC
    assign b_compute_data = $signed(b_mem_rdata); // B memory -> MAC
    assign c_rd_data = $signed(c_mem_rdata);      // C memory -> GEMM output

endmodule

`default_nettype wire

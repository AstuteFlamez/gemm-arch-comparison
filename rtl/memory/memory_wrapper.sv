`timescale 1ns/1ps
`default_nettype none

// All SRAM operations use the rising edge of clk; active-high reset gates access.
// IDLE host writes populate A/B; busy compute reads A/B and writes C.
// Addresses index matrix elements. Reset gates access without erasing stored data.
// Supported compile-time matrix dimensions: 8, 16, and 32.
module memory_wrapper #(
    parameter int MatrixDim = 8
) (
    input  logic clk,
    input  logic rst,
    input  logic busy,

    // Read A/B SRAMs
    input  logic ab_re,

    // A memory
    input  logic a_we,
    input  logic [$clog2(MatrixDim * MatrixDim) - 1:0] a_wr_addr,
    input  logic [7:0] a_wr_data,
    input  logic [$clog2(MatrixDim * MatrixDim) - 1:0] a_rd_addr,
    output logic signed [7:0] a_rd_data,

    // B memory
    input  logic b_we,
    input  logic [$clog2(MatrixDim * MatrixDim) - 1:0] b_wr_addr,
    input  logic [7:0] b_wr_data,
    input  logic [$clog2(MatrixDim * MatrixDim) - 1:0] b_rd_addr,
    output logic signed [7:0] b_rd_data,

    // C memory
    input  logic c_we,
    input  logic [$clog2(MatrixDim * MatrixDim) - 1:0] c_wr_addr,
    input  logic signed [31:0] c_wr_data,
    input  logic [$clog2(MatrixDim * MatrixDim) - 1:0] c_rd_addr,
    output logic signed [31:0] c_rd_data
);

    localparam int MATRIX_WORDS = MatrixDim * MatrixDim;
    localparam int INPUT_WIDTH  = 8;
    localparam int RESULT_WIDTH = 32;

    logic host_access;    // Host accesses memory while idle
    logic compute_access; // GEMM accesses memory while busy
    logic operand_re;     // A/B read request during computation

    // synthesis translate_off
    initial begin
        if (MatrixDim != 8 && MatrixDim != 16 && MatrixDim != 32) begin
            $fatal(1, "memory_wrapper: MatrixDim must be 8, 16, or 32");
        end
    end
    // synthesis translate_on

    // Reset suppresses all memory operations. While busy, the compute engine
    // owns the ports; host writes are ignored and host C read data holds.
    assign host_access    = !rst && !busy;
    assign compute_access = !rst && busy;
    assign operand_re     = compute_access && ab_re;

    // A and B share the same read schedule, with one word per memory per edge.
    sram #(
        .DATA_WIDTH(INPUT_WIDTH),
        .DEPTH(MATRIX_WORDS)
    ) u_sram_a (
        .clk(clk),

        .re(operand_re),
        .we(host_access && a_we),

        .addr(busy ? a_rd_addr : a_wr_addr),
        .rd_data(a_rd_data),
        .wr_data(a_wr_data)
    );

    sram #(
        .DATA_WIDTH(INPUT_WIDTH),
        .DEPTH(MATRIX_WORDS)
    ) u_sram_b (
        .clk(clk),

        .re(operand_re),
        .we(host_access && b_we),

        .addr(busy ? b_rd_addr : b_wr_addr),
        .rd_data(b_rd_data),
        .wr_data(b_wr_data)
    );

    // C accepts compute writes while busy and synchronous host reads while idle.
    sram #(
        .DATA_WIDTH(RESULT_WIDTH),
        .DEPTH(MATRIX_WORDS)
    ) u_sram_c (
        .clk(clk),

        .re(host_access),
        .we(compute_access && c_we),

        .addr(busy ? c_wr_addr : c_rd_addr),
        .rd_data(c_rd_data),
        .wr_data(c_wr_data)
    );

endmodule

`default_nettype wire

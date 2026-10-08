`timescale 1ns/1ps
`default_nettype none

// Fixed 8x8 signed INT8-to-INT32 GEMM, one matrix pair at a time on clk.
// Synchronous active-high reset aborts work without erasing A/B/C SRAM contents.
// An aborted job can leave partially updated C data; restart before using its result.
// IDLE A/B writes may share the accepted start edge; busy writes/starts are ignored.
// Done is sticky. IDLE C reads update after the rising edge; addresses index elements.
module systolic_gemm (
    input  logic clk,
    input  logic rst,

    // Write A: 64 signed 8-bit elements
    input  logic a_we,
    input  logic [5:0] a_wr_addr,
    input  logic signed [7:0] a_wdata,

    // Write B: 64 signed 8-bit elements
    input  logic b_we,
    input  logic [5:0] b_wr_addr,
    input  logic signed [7:0] b_wdata,

    // Start one full matrix multiplication
    input  logic start,
    output logic busy,
    output logic done,

    // Read C: 64 signed 32-bit results
    input  logic [5:0] c_rd_addr,
    output logic signed [31:0] c_rd_data
);

    localparam int INPUT_WIDTH  = 8;
    localparam int RESULT_WIDTH = 32;
    localparam int FIFO_DEPTH   = 8;

    // Tile-result selector encodings match the tile controller's output order.
    localparam logic [1:0] C00_SELECT = 2'd0;
    localparam logic [1:0] C01_SELECT = 2'd1;
    localparam logic [1:0] C10_SELECT = 2'd2;
    localparam logic [1:0] C11_SELECT = 2'd3;

    // Tile request and completion
    logic tile_start;
    logic tile_done;
    logic [2:0] tile_row;
    logic [2:0] tile_col;

    // SRAM controls, addresses, and data
    logic ab_re;
    logic c_we;
    logic [5:0] a_rd_addr;
    logic [5:0] b_rd_addr;
    logic [5:0] c_wr_addr;
    logic signed [INPUT_WIDTH - 1:0] a_rd_data;
    logic signed [INPUT_WIDTH - 1:0] b_rd_data;
    logic signed [RESULT_WIDTH - 1:0] c_wr_data;

    // FIFO controls, result selection, and buffered operands
    logic [1:0] fifo_push;
    logic [1:0] fifo_pop;
    logic [1:0] fifo_valid;
    logic [1:0] c_sel;
    logic signed [INPUT_WIDTH - 1:0] a0_fifo_data;
    logic signed [INPUT_WIDTH - 1:0] a1_fifo_data;
    logic signed [INPUT_WIDTH - 1:0] b0_fifo_data;
    logic signed [INPUT_WIDTH - 1:0] b1_fifo_data;

    // Array controls and accumulated results
    logic array_clr;
    logic array_enable;
    logic signed [RESULT_WIDTH - 1:0] c00_acc;
    logic signed [RESULT_WIDTH - 1:0] c01_acc;
    logic signed [RESULT_WIDTH - 1:0] c10_acc;
    logic signed [RESULT_WIDTH - 1:0] c11_acc;

    // Choose each of the 16 output tiles and announce when the full job is done
    top_level_controller u_controller (
        .clk(clk),
        .rst(rst),

        .start(start),
        .busy(busy),
        .done(done),

        .tile_start(tile_start),
        .tile_done(tile_done),
        .tile_row(tile_row),
        .tile_col(tile_col)
    );

    // For one tile: load the FIFOs, run the array, then store its four results
    systolic_tile_controller u_tile_controller (
        .clk(clk),
        .rst(rst),

        .start(tile_start),
        .done(tile_done),
        .tile_row(tile_row),
        .tile_col(tile_col),

        .ab_re(ab_re),
        .a_rd_addr(a_rd_addr),
        .b_rd_addr(b_rd_addr),

        .fifo_push(fifo_push),
        .fifo_pop(fifo_pop),
        .fifo_valid(fifo_valid),

        .array_clr(array_clr),
        .array_enable(array_enable),

        .c_we(c_we),
        .c_wr_addr(c_wr_addr),
        .c_sel(c_sel)
    );

    // The host accesses SRAM while idle; the tile controller accesses it while busy
    memory_wrapper u_memory (
        .clk(clk),
        .rst(rst),
        .busy(busy),
        .ab_re(ab_re),

        .a_we(a_we),
        .a_wr_addr(a_wr_addr),
        .a_wr_data(a_wdata),
        .a_rd_addr(a_rd_addr),
        .a_rd_data(a_rd_data),

        .b_we(b_we),
        .b_wr_addr(b_wr_addr),
        .b_wr_data(b_wdata),
        .b_rd_addr(b_rd_addr),
        .b_rd_data(b_rd_data),

        .c_we(c_we),
        .c_wr_addr(c_wr_addr),
        .c_wr_data(c_wr_data),
        .c_rd_addr(c_rd_addr),
        .c_rd_data(c_rd_data)
    );

    // Each FIFO holds eight values. Bit 0 controls A0/B0; bit 1 controls A1/B1
    // The fixed schedule fills and drains them completely for every tile
    fifo #(
        .DATA_WIDTH(INPUT_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_a0_fifo (
        .clk(clk),
        .rst(rst),

        .push(fifo_push[0]),
        .pop(fifo_pop[0]),

        .data_in(a_rd_data),
        .data_out(a0_fifo_data),
        .full(),
        .empty()
    );

    fifo #(
        .DATA_WIDTH(INPUT_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_a1_fifo (
        .clk(clk),
        .rst(rst),

        .push(fifo_push[1]),
        .pop(fifo_pop[1]),

        .data_in(a_rd_data),
        .data_out(a1_fifo_data),
        .full(),
        .empty()
    );

    fifo #(
        .DATA_WIDTH(INPUT_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_b0_fifo (
        .clk(clk),
        .rst(rst),

        .push(fifo_push[0]),
        .pop(fifo_pop[0]),

        .data_in(b_rd_data),
        .data_out(b0_fifo_data),
        .full(),
        .empty()
    );

    fifo #(
        .DATA_WIDTH(INPUT_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_b1_fifo (
        .clk(clk),
        .rst(rst),

        .push(fifo_push[1]),
        .pop(fifo_pop[1]),

        .data_in(b_rd_data),
        .data_out(b1_fifo_data),
        .full(),
        .empty()
    );

    // FIFO outputs hold their last popped value. Feed zero outside each pair's
    // valid window so old values are not multiplied again as the array drains.
    // Clear the array at the beginning of each tile to start fresh accumulators
    systolic_array u_array (
        .clk(clk),
        .rst(rst),
        .clr(array_clr),
        .enable(array_enable),

        .A0(fifo_valid[0] ? a0_fifo_data : 8'sd0),
        .A1(fifo_valid[1] ? a1_fifo_data : 8'sd0),
        .B0(fifo_valid[0] ? b0_fifo_data : 8'sd0),
        .B1(fifo_valid[1] ? b1_fifo_data : 8'sd0),

        .C00(c00_acc),
        .C01(c01_acc),
        .C10(c10_acc),
        .C11(c11_acc)
    );

    // C SRAM has one write port, so store one array result per STORE cycle.
    always_comb begin
        case (c_sel)
            C00_SELECT: begin
                c_wr_data = c00_acc;
            end
            C01_SELECT: begin
                c_wr_data = c01_acc;
            end
            C10_SELECT: begin
                c_wr_data = c10_acc;
            end
            C11_SELECT: begin
                c_wr_data = c11_acc;
            end
            default: begin
                c_wr_data = '0;
            end
        endcase
    end

endmodule

`default_nettype wire

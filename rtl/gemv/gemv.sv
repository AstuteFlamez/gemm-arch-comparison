// TODO: Replace the local operand/result arrays with an SRAM interface.
`timescale 1ns/1ps
`default_nettype none

// Fixed 8x8 signed matrix-vector multiplication; one MAC processes rows in order.
// Synchronous active-high reset aborts work without clearing the stored arrays.
// IDLE writes block start acceptance; done is sticky and y readback is combinational.
module gemv (
    input  logic clk,
    input  logic rst,

    // Write A: 64 signed 8-bit elements
    input  logic a_we,
    input  logic [5:0] a_addr,
    input  logic signed [7:0] a_wdata,

    // Write x: 8 signed 8-bit elements
    input  logic x_we,
    input  logic [2:0] x_addr,
    input  logic signed [7:0] x_wdata,

    // Start one matrix-vector multiplication
    input  logic start,
    output logic busy,
    output logic done,

    // Read y: 8 signed 32-bit results
    input  logic [2:0] y_rd_addr,
    output logic signed [31:0] y_rd_data
);

    localparam int MATRIX_DIM                 = 8;
    localparam int MATRIX_WORDS               = MATRIX_DIM * MATRIX_DIM;
    localparam logic [7:0] LAST_ELEMENT_INDEX = MATRIX_DIM - 1;

    // Compute one output row at a time: clear, accumulate eight terms, store.
    typedef enum logic [1:0] {
        IDLE,
        ROW_CLEAR,
        ACCUMULATE,
        STORE
    } state_e;
    state_e state_q;

    // Operand and result storage
    logic signed [7:0] matrix_a_q [0:MATRIX_WORDS - 1];
    logic signed [7:0] vector_x_q [0:MATRIX_DIM - 1];
    logic signed [31:0] vector_y_q [0:MATRIX_DIM - 1];

    logic [7:0] row_q;
    logic [7:0] column_q;

    // MAC controls, operands, and accumulated result
    logic mac_clr;
    logic mac_enable;
    logic signed [7:0] mac_a;
    logic signed [7:0] mac_b;
    logic signed [31:0] mac_acc;

    // Each row starts with a dedicated clear edge before its eight products.
    mac u_mac (
        .clk(clk),
        .rst(rst),
        .clr(mac_clr),
        .enable(mac_enable),

        .a(mac_a),
        .b(mac_b),
        .acc(mac_acc)
    );

    // Select one term of the current row's dot product
    assign mac_a = matrix_a_q[(row_q * MATRIX_DIM) + column_q];
    assign mac_b = vector_x_q[column_q];

    assign mac_clr    = (state_q == ROW_CLEAR);
    assign mac_enable = (state_q == ACCUMULATE);

    assign busy = (state_q != IDLE);

    // Unlike the GEMM SRAM interface, y readback is combinational.
    assign y_rd_data = vector_y_q[y_rd_addr];

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q  <= IDLE;
            row_q    <= '0;
            column_q <= '0;
            done     <= '0;
        end else begin
            case (state_q)
                IDLE: begin
                    // Accept writes while idle
                    if (a_we) begin
                        matrix_a_q[a_addr] <= a_wdata;
                    end

                    if (x_we) begin
                        vector_x_q[x_addr] <= x_wdata;
                    end

                    // Accept start only when neither write enable is high
                    if (start && !a_we && !x_we) begin
                        row_q    <= '0;
                        column_q <= '0;
                        done     <= '0;
                        state_q  <= ROW_CLEAR;
                    end
                end

                ROW_CLEAR: begin
                    // Clear the accumulator at this edge; MAC starts next edge
                    column_q <= '0;
                    state_q  <= ACCUMULATE;
                end

                ACCUMULATE: begin
                    // ACCUMULATE the operands selected before this rising edge
                    if (column_q < LAST_ELEMENT_INDEX) begin
                        column_q <= column_q + 8'd1;
                    end else begin
                        state_q <= STORE;
                    end
                end

                STORE: begin
                    // Save the completed dot product in the current result row
                    vector_y_q[row_q] <= mac_acc;

                    if (row_q < LAST_ELEMENT_INDEX) begin
                        // Rows 0-6: advance to the next row and clear the MAC
                        row_q    <= row_q + 8'd1;
                        column_q <= '0;
                        state_q  <= ROW_CLEAR;
                    end else begin
                        // Row 7: all results are stored
                        done    <= 1'b1;
                        state_q <= IDLE;
                    end
                end

                default: begin
                    state_q <= IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire

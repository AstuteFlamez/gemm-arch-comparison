/*
    TODO: need to interface w/ sram + lots lot more
*/
`timescale 1ns/1ps
`default_nettype none

module gemv (
    input  logic clk,
    input  logic reset,

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

    // Operand and result storage
    logic signed [7:0] A [0:63];
    logic signed [7:0] x [0:7];
    logic signed [31:0] y [0:7];

    logic [7:0] row;
    logic [7:0] column;

    // Compute one output row at a time
    typedef enum logic [1:0] {
        IDLE,
        ROW_CLEAR,
        MAC,
        STORE
    } state_t;
    state_t state;

    // MAC controls, operands, and accumulated result
    logic mac_clear;
    logic mac_enable;
    logic signed [7:0] mac_a;
    logic signed [7:0] mac_b;
    logic signed [31:0] mac_acc;

    mac mac_instance (
        .clk(clk),
        .reset(reset),
        .clear(mac_clear),
        .enable(mac_enable),

        .a(mac_a),
        .b(mac_b),
        .acc(mac_acc)
    );

    // Select one term of the current row's dot product
    assign mac_a = A[(row * 8) + column];
    assign mac_b = x[column];

    assign mac_clear  = (state == ROW_CLEAR);
    assign mac_enable = (state == MAC);

    assign busy = (state != IDLE);
    assign y_rd_data = y[y_rd_addr];

    always_ff @(posedge clk) begin
        if (reset) begin
            state  <= IDLE;
            row    <= 8'd0;
            column <= 8'd0;
            done   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    // Accept writes while idle
                    if (a_we) begin
                        A[a_addr] <= a_wdata;
                    end

                    if (x_we) begin
                        x[x_addr] <= x_wdata;
                    end

                    // Accept start only when neither write enable is high
                    if (start && !a_we && !x_we) begin
                        row    <= 8'd0;
                        column <= 8'd0;
                        done   <= 1'b0;
                        state  <= ROW_CLEAR;
                    end
                end

                ROW_CLEAR: begin
                    // Clear the accumulator at this edge; MAC starts next edge
                    column <= 8'd0;
                    state  <= MAC;
                end

                MAC: begin
                    // Accumulate the operands selected before this rising edge
                    if (column < 8'd7) begin
                        column <= column + 8'd1;
                    end else begin
                        state <= STORE;
                    end
                end

                STORE: begin
                    // Save the completed dot product in the current result row
                    y[row] <= mac_acc;

                    if (row < 8'd7) begin
                        // Rows 0-6: advance to the next row and clear the MAC
                        row    <= row + 8'd1;
                        column <= 8'd0;
                        state  <= ROW_CLEAR;
                    end else begin
                        // Row 7: all results are stored
                        done  <= 1'b1;
                        state <= IDLE;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule

`default_nettype wire

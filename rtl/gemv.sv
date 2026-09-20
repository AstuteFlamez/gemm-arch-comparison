`timescale 1ns/1ps
`default_nettype none

module gemv (
    input  logic clk,
    input  logic reset,

    input  logic a_we, // A matrix write enable
    input  logic [5:0] a_addr, // 6-bit address for A matrix (64 elements)
    input  logic signed [7:0] a_wdata, // 8-bit signed matrix write data
    
    input  logic x_we, // x matrix write enable
    input  logic [2:0] x_addr, // 3-bit address for x vector (8 elements)
    input  logic signed [7:0] x_wdata, // 8-bit signed vector write data

    // calculation control signals
    input  logic start,
    output logic busy,
    output logic done,

    input  logic [2:0] y_rd_addr, // 3-bit address for output y vector (8 elements)
    output logic signed [31:0] y_rd_data // 32-bit signed output vector read data
);

    logic signed [7:0] A [0:63]; // (matrix) 8-bits per 64 elements stored in a 1D array
    logic signed [7:0] x [0:7]; // (vector) 8-bits per 8 elements stored in a 1D array
    logic signed [31:0] y [0:7]; // (output vector) 32-bits per 8 elements stored in a 1D array
    logic [7:0] row;
    logic [7:0] column;

    //  state machine of IDLE=00 -> ROW_CLEAR=01 -> MAC=10 -> STORE=11 -> IDLE=00
    typedef enum logic [1:0] {
        IDLE,
        ROW_CLEAR,
        MAC,
        STORE
    } state_t;
    state_t state;

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

    assign mac_a = A[(row * 8) + column];    // select the matrix element based on the current row and column
    assign mac_b = x[column];                // select the vector element based on the current column
    assign mac_clear = (state == ROW_CLEAR); // assert mac_clear only in ROW_CLEAR state
    assign mac_enable = (state == MAC);      // assert mac_enable only in MAC state
    assign busy = (state != IDLE);           // assert busy whenever the controller is outside IDLE
    assign y_rd_data = y[y_rd_addr];         // read the result array element selected by y_rd_addr into y_rd_data


    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            row <= 8'd0;
            column <= 8'd0;
            done <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (a_we) begin // write to A array when a_we is high
                        A[a_addr] <= a_wdata;
                    end
                    if (x_we) begin // write to x array when x_we is high
                        x[x_addr] <= x_wdata;
                    end
                    if (start && !a_we && !x_we) begin // accept start only when neither write enable is high
                        row <= 8'd0;
                        column <= 8'd0;
                        done <= 1'b0;
                        state <= ROW_CLEAR;
                    end
                end

                ROW_CLEAR: begin // clear the MAC's accumulator at this edge, then advance to MAC for the next edge
                    column <= 8'd0;
                    state <= MAC;
                end

                MAC: begin // accumulate the operands selected before this rising edge
                    if (column < 8'd7) begin
                        column <= column + 8'd1;
                    end else begin
                        state <= STORE;
                    end
                end

                STORE: begin // save the MAC's completed accumulator into the current result row
                    y[row] <= mac_acc;
                    if (row < 8'd7) begin // for rows 0..6, advance the row, reset the column, and enter ROW_CLEAR
                        row <= row + 8'd1;
                        column <= 8'd0;
                        state <= ROW_CLEAR;
                    end else begin // for row 7, assert done and return to IDLE
                        done <= 1'b1;
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
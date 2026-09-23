`timescale 1ns/1ps
`default_nettype none

module gemm_controller(
    input logic clk,
    input logic reset,
    input logic start,
    input logic a_we,
    input logic b_we,

    output logic busy,
    output logic done,
    output logic compute_re,
    output logic c_compute_we,
    output logic mac_clear,
    output logic mac_enable,

    output logic [5:0] a_compute_addr,
    output logic [5:0] b_compute_addr,
    output logic [5:0] c_compute_addr
);

    logic [7:0] row;
    logic [7:0] column;
    logic [7:0] k;

    typedef enum logic [2:0] {
        IDLE,
        CLEAR,
        READ,
        MAC,
        STORE
    } state_t;
    state_t state;

    assign a_compute_addr = row * 8 + k;
    assign b_compute_addr = k * 8 + column;
    assign c_compute_addr = row * 8 + column;
    assign compute_re = (state == READ);
    assign c_compute_we = (state == STORE);
    assign mac_clear = (state == CLEAR);
    assign mac_enable = (state == MAC);
    assign busy = (state != IDLE);

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            row <= 8'd0;
            column <= 8'd0;
            k <= 8'd0;
            done <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start && !a_we && !b_we) begin // accept start only when neither write enable is high
                        row <= 8'd0;
                        column <= 8'd0;
                        done <= 1'b0;
                        state <= CLEAR;
                    end
                end

                CLEAR: begin // clear the MAC's accumulator at this edge, then advance to READ for the next edge
                    k <= 8'd0;
                    state <= READ;
                end

                READ: begin // register operands for the following MAC edge
                    state <= MAC;
                end

                MAC: begin // the MAC instance accumulates the registered operands at this edge
                    if (k < 8'd7) begin
                        k <= k + 8'd1;
                        state <= READ;
                    end else begin
                        state <= STORE;
                    end
                end

                STORE: begin // save the completed dot product at C[row][column]
                    if (column < 8'd7) begin
                        column <= column + 8'd1;
                        state <= CLEAR;
                    end else if (row < 8'd7) begin
                        column <= 8'd0;
                        row <= row + 8'd1;
                        state <= CLEAR;
                    end else begin
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
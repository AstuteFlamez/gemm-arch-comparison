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

    logic signed [7:0] A [0:63]; // (matrix) 8-bits per 64 elements stored in a 1D array
    logic signed [7:0] B [0:63]; // (matrix) 8-bits per 64 elements stored in a 1D array
    logic signed [31:0] C [0:63]; // (output matrix) 32-bits per 64 elements stored in a 1D array
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

    assign mac_clear = (state == CLEAR);     // assert mac_clear only in CLEAR state
    assign mac_enable = (state == MAC);      // assert mac_enable only in MAC state
    assign busy = (state != IDLE);           // assert busy whenever the controller is outside IDLE
    assign c_rd_data = C[c_rd_addr];         // asynchronously read the selected result element


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
                    if (a_we) begin // write to A array when a_we is high
                        A[a_addr] <= a_wdata;
                    end
                    if (b_we) begin // write to B array when b_we is high
                        B[b_addr] <= b_wdata;
                    end
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
                    mac_a <= A[(row * 8) + k];
                    mac_b <= B[(k * 8) + column];
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
                    C[(row * 8) + column] <= mac_acc;

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

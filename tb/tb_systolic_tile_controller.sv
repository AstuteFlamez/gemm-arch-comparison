`timescale 1ns/1ps
module tb_systolic_tile_controller;
    logic clk = 0, reset = 1, start = 0;
    always #5 clk = ~clk;
    logic [2:0] tile_row = 0, tile_col = 0;
    logic done, ab_re, array_clear, array_enable, c_we;
    logic [5:0] a_rd_addr, b_rd_addr, c_wr_addr;
    logic [1:0] fifo_push, fifo_pop, fifo_valid, c_sel;
    logic host_we = 0;
    logic [5:0] host_addr = 0;
    logic signed [7:0] aw = 0, bw = 0, ar, br;
    logic signed [7:0] aq0, aq1, bq0, bq1;
    logic signed [31:0] C00, C01, C10, C11;
    logic signed [7:0] amat [0:63], bmat [0:63];
    integer pops0, pops1, enabled;
    integer write_edges = 0;
    localparam integer TILE_CYCLES = 32;
    integer seed = 20260917;
    integer random_init;
    time accepted_at;
    logic c_read_en = 0;
    logic [5:0] c_read_addr = 0;
    logic signed [31:0] c_write_data, c_read_data;
    always_comb begin
        case (c_sel)
            0: c_write_data = C00;
            1: c_write_data = C01;
            2: c_write_data = C10;
            3: c_write_data = C11;
        endcase
    end
    sram #(.DATA_WIDTH(32), .DEPTH(64)) mc(
        .clk(clk), .re(c_read_en), .we(c_we),
        .addr(c_we ? c_wr_addr : c_read_addr),
        .wdata(c_write_data), .rdata(c_read_data));
    always @(posedge clk) begin
        if (!reset && c_we) begin
            write_edges = write_edges + 1;
            if (done || array_enable || fifo_pop != 0 || fifo_push != 0)
                $fatal(1, "unexpected control during writeback");
        end
    end
    systolic_tile_controller dut (.*);
    sram #(.DATA_WIDTH(8), .DEPTH(64)) ma(
        .clk(clk), .re(ab_re), .we(host_we),
        .addr(host_we ? host_addr : a_rd_addr), .wdata(aw), .rdata(ar));
    sram #(.DATA_WIDTH(8), .DEPTH(64)) mb(
        .clk(clk), .re(ab_re), .we(host_we),
        .addr(host_we ? host_addr : b_rd_addr), .wdata(bw), .rdata(br));
    fifo fa0(.clk(clk), .reset(reset), .push(fifo_push[0]),
        .pop(fifo_pop[0]), .data_in(ar), .data_out(aq0), .full(), .empty());
    fifo fa1(.clk(clk), .reset(reset), .push(fifo_push[1]),
        .pop(fifo_pop[1]), .data_in(ar), .data_out(aq1), .full(), .empty());
    fifo fb0(.clk(clk), .reset(reset), .push(fifo_push[0]),
        .pop(fifo_pop[0]), .data_in(br), .data_out(bq0), .full(), .empty());
    fifo fb1(.clk(clk), .reset(reset), .push(fifo_push[1]),
        .pop(fifo_pop[1]), .data_in(br), .data_out(bq1), .full(), .empty());
    systolic_array array_inst(.clk(clk), .reset(reset | array_clear),
        .enable(array_enable),
        .A0(fifo_valid[0] ? aq0 : 8'sd0),
        .A1(fifo_valid[1] ? aq1 : 8'sd0),
        .B0(fifo_valid[0] ? bq0 : 8'sd0),
        .B1(fifo_valid[1] ? bq1 : 8'sd0),
        .C00(C00), .C01(C01), .C10(C10), .C11(C11));

    // Independent dot-product reference: term k reaches PE(r,c) on
    // compute edge k+r+c+1, after the initial FIFO prefetch edge.
    function automatic integer expected(input integer r, c, step);
        integer av, bv;
        expected = 0;
        for (integer k = 0; k < 8; k = k + 1) begin
            if (k + r + c <= step - 1) begin
                av = amat[(tile_row+r)*8+k];
                bv = bmat[k*8+tile_col+c];
                expected = expected + av*bv;
            end
        end
    endfunction

    initial begin
        if ($value$plusargs("SEED=%d", seed)) begin end
        random_init = $urandom(seed);
        @(posedge clk); #1;
        @(negedge clk);
        reset = 0;
        for (integer trial = 0; trial < 32; trial = trial + 1) begin
            tile_row = 2*((trial/4)%4);
            tile_col = 2*(trial%4);
            for (integer i = 0; i < 64; i = i + 1) begin
                amat[i] = trial == 0 ? -128 : trial == 1 ? 127 : $urandom_range(0, 255) - 128;
                bmat[i] = trial == 0 ? -128 : trial == 1 ? -128 : $urandom_range(0, 255) - 128;
                @(negedge clk);
                host_we = 1;
                host_addr = i;
                aw = amat[i];
                bw = bmat[i];
            end
            @(negedge clk);
            host_we = 0;
            if (trial == 0) begin
                // Abort with reads/pushes in flight, then restart using the
                // same SRAM contents. Global reset also empties the FIFOs.
                start = 1;
                @(negedge clk);
                start = 0;
                repeat (9) @(negedge clk);
                reset = 1;
                #1;
                if ({ab_re, fifo_push, fifo_pop, fifo_valid, array_clear,
                     array_enable, c_we, done} !== 0)
                    $fatal(1, "memory/array operations were not gated during reset");
                @(posedge clk); #1;
                if (dut.state !== dut.IDLE)
                    $fatal(1, "reset did not return controller to IDLE");
                @(negedge clk);
                reset = 0;
            end
            start = 1;
            @(posedge clk);
            accepted_at = $time;
            @(negedge clk);
            start = 0;
            while (fifo_pop[0] !== 1'b1) @(negedge clk);
            pops0 = 0;
            pops1 = 0;
            enabled = 0;
            for (integer step = 0; step <= 10; step = step + 1) begin
                pops0 = pops0 + fifo_pop[0];
                pops1 = pops1 + fifo_pop[1];
                enabled = enabled + array_enable;
                @(posedge clk); #1;
                if (C00 !== expected(0,0,step) || C01 !== expected(0,1,step) ||
                    C10 !== expected(1,0,step) || C11 !== expected(1,1,step))
                    $fatal(1, "trial %0d step %0d: arithmetic mismatch", trial, step);
                if (step < 10) @(negedge clk);
            end
            if (pops0 != 8 || pops1 != 8 || enabled != 10)
                $fatal(1, "unexpected pop/enable counts");
            if (dut.state !== dut.STORE) $fatal(1, "did not enter STORE");
            for (integer result = 0; result < 4; result = result + 1) begin
                @(negedge clk);
                if (c_we !== 1 || c_sel !== result || done !== 0)
                    $fatal(1, "trial %0d write %0d: wrong write controls", trial, result);
                if (c_wr_addr !== (tile_row + result/2)*8 + tile_col + result%2)
                    $fatal(1, "trial %0d write %0d: wrong C address %0d", trial, result, c_wr_addr);
                if (c_write_data !== expected(result/2, result%2, 10))
                    $fatal(1, "wrong result selected for C write");
                @(posedge clk); #1;
                if (done !== (result == 3))
                    $fatal(1, "done must assert only after the fourth write");
                if (C00 !== expected(0,0,10) || C01 !== expected(0,1,10) ||
                    C10 !== expected(1,0,10) || C11 !== expected(1,1,10))
                    $fatal(1, "result changed during STORE");
            end
            if ($time - accepted_at != TILE_CYCLES*10 + 1)
                $fatal(1, "unexpected start-to-done latency: %0t", $time-accepted_at);
            if (c_we !== 0 || write_edges != (trial+1)*4)
                $fatal(1, "incorrect write count at completion");
            @(posedge clk); #1;
            if (done !== 0 || c_we !== 0 || dut.state !== dut.IDLE)
                $fatal(1, "done did not pulse for exactly one cycle and return to IDLE");
            for (integer result = 0; result < 4; result = result + 1) begin
                @(negedge clk);
                c_read_en = 1;
                c_read_addr = (tile_row + result/2)*8 + tile_col + result%2;
                @(posedge clk); #1;
                if (c_read_data !== expected(result/2, result%2, 10))
                    $fatal(1, "C SRAM readback mismatch at address %0d", c_read_addr);
                if (done !== 0 || c_we !== 0)
                    $fatal(1, "unexpected operation while idle");
            end
            @(negedge clk);
            c_read_en = 0;
        end
        $display("PASS: reset during loading, 32 consecutive tiles without reset, 352 compute-edge checks, 128 C writes/readbacks, one-cycle done pulses");
        $display("Start-to-done latency: %0d clocks per tile", TILE_CYCLES);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "timeout");
    end
endmodule

`timescale 1ns/1ps
`default_nettype none

module tb_gemm_controller;
    logic clk = 0, rst = 1, start = 1;
    logic busy, done, tile_start, tile_done, memory_done;
    logic [2:0] tile_row, tile_col;
    logic ab_re, array_clr, array_enable, c_we;
    logic [5:0] a_rd_addr, b_rd_addr, c_wr_addr;
    logic [1:0] fifo_push, fifo_pop, fifo_valid, c_sel;
    logic block_done = 0, manual_done = 0;
    integer completed_jobs = 0;
    integer rst_offsets [0:8];

    always #5 clk = ~clk;

    top_level_controller dut (
        .clk(clk), .rst(rst), .start(start), .busy(busy), .done(done),
        .tile_done(tile_done), .tile_start(tile_start),
        .tile_row(tile_row), .tile_col(tile_col)
    );

    // Use the real tile controller to verify the FINISH/start handoff.
    // Arithmetic and FIFO data are checked by test-systolic-tile-controller.
    systolic_tile_controller tile_controller (
        .clk(clk), .rst(rst), .start(tile_start),
        .tile_row(tile_row), .tile_col(tile_col), .done(memory_done),
        .ab_re(ab_re), .a_rd_addr(a_rd_addr), .b_rd_addr(b_rd_addr),
        .fifo_push(fifo_push), .fifo_pop(fifo_pop), .fifo_valid(fifo_valid),
        .array_clr(array_clr), .array_enable(array_enable),
        .c_we(c_we), .c_wr_addr(c_wr_addr), .c_sel(c_sel)
    );

    // One test delays a completion pulse to check that the top-level controller
    // waits for the handshake instead of assuming a fixed tile duration.
    assign tile_done = manual_done || (memory_done && !block_done);

    task automatic check_idle(input bit wanted_done);
        if ({busy, done, tile_start} !== {1'b0, wanted_done, 1'b0})
            $fatal(1, "expected idle with done=%b, got busy/done/start=%b",
                   wanted_done, {busy, done, tile_start});
    endtask

    task automatic idle_edges(input integer count, input bit wanted_done);
        repeat (count) begin
            @(negedge clk);
            start = 0;
            block_done = 0;
            manual_done = 0;
            @(posedge clk); #1;
            check_idle(wanted_done);
        end
    endtask

    task automatic begin_job;
        @(negedge clk);
        if (busy !== 0 || tile_start !== 0)
            $fatal(1, "job must begin from idle");
        start = 1;
        block_done = 0;
        manual_done = 0;
        @(posedge clk); #1;
        if ({busy, done, tile_start, tile_row, tile_col}
            !== {1'b1, 1'b0, 1'b1, 3'd0, 3'd0})
            $fatal(1, "accepted start did not request tile (0,0) and clear done");
    endtask

    task automatic finish_job(
        input string label_text,
        input bit busy_start = 0,
        input bit delay_first_completion = 0
    );
        integer launches, writes, acknowledgements, cycles;
        integer expected_row, expected_col, output_tile, local_result;
        integer wanted_cycles;
        bit previous_launch;
        launches = 0;
        writes = 0;
        acknowledgements = 0;
        cycles = 0;
        previous_launch = 0;

        // Each tile takes one launch edge, 32 work edges, and one acknowledgement
        // edge. The delayed test acknowledges tile 0 at edge 50 instead of 34.
        wanted_cycles = delay_first_completion ? 560 : 544;
        while (busy === 1'b1) begin
            @(negedge clk);
            start = busy_start;
            block_done = delay_first_completion && acknowledgements == 0;
            manual_done = delay_first_completion && cycles == 49;
            #1;
            if (done !== 0)
                $fatal(1, "%s: overall done asserted while busy", label_text);

            if (tile_start) begin
                expected_row = (launches / 4) * 2;
                expected_col = (launches % 4) * 2;
                if (launches >= 16 || tile_row !== expected_row || tile_col !== expected_col)
                    $fatal(1, "%s: launch %0d has wrong tile (%0d,%0d)",
                           label_text, launches, tile_row, tile_col);
                if (previous_launch || memory_done)
                    $fatal(1, "%s: launch pulse repeated or overlapped FINISH", label_text);
                launches = launches + 1;
            end else if (launches > 0) begin
                expected_row = ((launches - 1) / 4) * 2;
                expected_col = ((launches - 1) % 4) * 2;
                if (tile_row !== expected_row || tile_col !== expected_col)
                    $fatal(1, "%s: tile coordinates changed while waiting", label_text);
            end
            previous_launch = tile_start;

            if (c_we) begin
                output_tile = writes / 4;
                local_result = writes % 4;
                expected_row = (output_tile / 4) * 2 + local_result / 2;
                expected_col = (output_tile % 4) * 2 + local_result % 2;
                if (writes >= 64 || c_wr_addr !== expected_row*8 + expected_col ||
                    c_sel !== local_result || busy !== 1)
                    $fatal(1, "%s: write %0d has wrong address/selection", label_text, writes);
                writes = writes + 1;
            end

            if (tile_done) begin
                if (launches != acknowledgements + 1 || writes != 4*(acknowledgements + 1))
                    $fatal(1, "%s: completion without one fully stored tile", label_text);
                acknowledgements = acknowledgements + 1;
            end

            @(posedge clk); #1;
            cycles = cycles + 1;
            if (done !== 1'b1 && busy !== 1'b1)
                $fatal(1, "%s: busy dropped between tiles", label_text);
        end
        check_idle(1);
        if (launches != 16 || writes != 64 || acknowledgements != 16 || cycles != wanted_cycles)
            $fatal(1, "%s: launches/writes/acks/cycles=%0d/%0d/%0d/%0d",
                   label_text, launches, writes, acknowledgements, cycles);
        completed_jobs = completed_jobs + 1;
    endtask

    task automatic apply_rst;
        @(negedge clk);
        rst = 1;
        start = 1;
        manual_done = 1; // Reset must override both request and completion.
        block_done = 0;
        #1;
        if ({tile_start, ab_re, fifo_push, fifo_pop, fifo_valid,
             array_clr, array_enable, c_we} !== 0)
            $fatal(1, "operations were not gated during reset");
        repeat (2) begin
            @(posedge clk); #1;
            check_idle(0);
            if ({tile_row, tile_col} !== 0)
                $fatal(1, "reset did not select tile (0,0)");
        end
        @(negedge clk);
        rst = 0;
        start = 0;
        manual_done = 0;
        idle_edges(1, 0);
    endtask

    initial begin
        repeat (2) begin
            @(posedge clk); #1;
            check_idle(0);
        end
        @(negedge clk);
        rst = 0;
        start = 0;
        idle_edges(2, 0);

        begin_job();
        finish_job("baseline");
        idle_edges(3, 1); // Overall done is sticky.

        // A stray completion while idle must not launch another job.
        @(negedge clk);
        manual_done = 1;
        @(posedge clk); #1;
        check_idle(1);
        idle_edges(1, 1);

        begin_job();
        finish_job("starts while busy", 1);
        idle_edges(3, 1); // Busy starts must not be queued.

        begin_job();
        finish_job("delayed tile completion", 0, 1);
        idle_edges(1, 1);

        begin_job();
        finish_job("held start first job", 1);
        // A start still high at the next idle edge accepts a new full job.
        begin_job();
        finish_job("held start second job");
        idle_edges(1, 1);

        // Abort before launch, during loading/compute/store, while tile_done is
        // high, and just before the full matrix would finish. Restart each time.
        rst_offsets[0] = 0;
        rst_offsets[1] = 1;
        rst_offsets[2] = 9;
        rst_offsets[3] = 18;
        rst_offsets[4] = 27;
        rst_offsets[5] = 29;
        rst_offsets[6] = 32;
        rst_offsets[7] = 33;
        rst_offsets[8] = 543;
        for (integer i = 0; i < 9; i = i + 1) begin
            begin_job();
            repeat (rst_offsets[i]) begin
                @(negedge clk);
                start = 0;
                @(posedge clk); #1;
            end
            apply_rst();
            begin_job();
            finish_job($sformatf("restart after reset at edge %0d", rst_offsets[i]));
        end
        apply_rst(); // Reset also clears sticky done while idle.

        $display("PASS: top-level controller completed %0d jobs; 16 ordered tiles and 64 writes per job",
                 completed_jobs);
        $display("PASS: sticky done, busy starts, held-start restart, delayed completion, and 9 reset/restart cases");
        $display("PASS: 544 clocks per job with the current systolic tile controller");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "top-level controller testbench timed out");
    end
endmodule

`default_nettype wire

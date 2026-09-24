`timescale 1ns/1ps
`default_nettype none

module tb_gemm_controller;
    localparam integer OUTPUT_CYCLES = 18; // CLEAR + 8*(READ + MAC) + STORE
    localparam integer WORK_CYCLES = 64 * OUTPUT_CYCLES;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic start = 1'b1; // Reset must override even a pending start.
    logic a_we = 1'b0;
    logic b_we = 1'b0;
    logic busy;
    logic done;
    logic compute_re;
    logic c_compute_we;
    logic mac_clear;
    logic mac_enable;
    logic [5:0] a_compute_addr;
    logic [5:0] b_compute_addr;
    logic [5:0] c_compute_addr;

    integer checks = 0;
    integer completed_jobs = 0;
    integer clear_edges = 0;
    integer read_edges = 0;
    integer mac_edges = 0;
    integer store_edges = 0;
    integer reset_offsets [0:7];

    gemm_controller dut (
        .clk(clk), .reset(reset), .start(start), .a_we(a_we), .b_we(b_we),
        .busy(busy), .done(done),
        .compute_re(compute_re), .c_compute_we(c_compute_we),
        .mac_clear(mac_clear), .mac_enable(mac_enable),
        .a_compute_addr(a_compute_addr), .b_compute_addr(b_compute_addr),
        .c_compute_addr(c_compute_addr)
    );

    always #5 clk = ~clk;

    task automatic check_controls(
        input bit wanted_busy,
        input bit wanted_done,
        input logic [3:0] wanted_operations,
        input string label_text
    );
        // Case inequality catches X/Z, overlapping enables, and extra pulses.
        if ({busy, done, mac_clear, compute_re, mac_enable, c_compute_we}
            !== {wanted_busy, wanted_done, wanted_operations})
            $fatal(1, "%s at %0t: expected busy/done/clear/read/mac/store=%b, got %b",
                   label_text, $time, {wanted_busy, wanted_done, wanted_operations},
                   {busy, done, mac_clear, compute_re, mac_enable, c_compute_we});
        checks = checks + 1;
    endtask

    task automatic check_idle(input bit wanted_done, input string label_text);
        check_controls(1'b0, wanted_done, 4'b0000, label_text);
    endtask

    task automatic check_reset(input string label_text);
        check_idle(1'b0, label_text);
        if ({a_compute_addr, b_compute_addr, c_compute_addr} !== 18'd0)
            $fatal(1, "%s: compute addresses must be zero after reset", label_text);
        checks = checks + 1;
    endtask

    // Reference a numbered operation in the fixed job schedule, without
    // reading DUT state/counters or reproducing its next-state case statement.
    // Cycle 1 is the CLEAR edge after accepting start; cycle 1152 is STORE.
    task automatic check_work(input integer cycle, input string label_text);
        integer output_index;
        integer slot;
        integer pair_index;
        logic [3:0] wanted_operations;
        logic [5:0] wanted_a;
        logic [5:0] wanted_b;
        logic [5:0] wanted_c;
        string context_text;

        if (cycle < 1 || cycle > WORK_CYCLES)
            $fatal(1, "Invalid testbench work cycle %0d", cycle);
        output_index = (cycle - 1) / OUTPUT_CYCLES;
        slot = (cycle - 1) % OUTPUT_CYCLES;
        context_text = $sformatf("%s, cycle %0d, output %0d", label_text, cycle, output_index);
        if (slot == 0)
            wanted_operations = 4'b1000;
        else if (slot == OUTPUT_CYCLES - 1)
            wanted_operations = 4'b0001;
        else if (slot % 2 == 1)
            wanted_operations = 4'b0100;
        else
            wanted_operations = 4'b0010;
        check_controls(1'b1, 1'b0, wanted_operations, context_text);

        wanted_c = output_index;
        if (c_compute_addr !== wanted_c)
            $fatal(1, "%s: expected C address %0d, got %0d",
                   context_text, wanted_c, c_compute_addr);
        checks = checks + 1;

        // A/B addresses matter during READ and remain on the same pair in MAC.
        // Do not constrain unused operand addresses during CLEAR or STORE.
        if (slot >= 1 && slot <= 16) begin
            pair_index = (slot - 1) / 2;
            wanted_a = (output_index / 8) * 8 + pair_index;
            wanted_b = pair_index * 8 + (output_index % 8);
            if (a_compute_addr !== wanted_a || b_compute_addr !== wanted_b)
                $fatal(1, "%s: expected A/B addresses %0d/%0d, got %0d/%0d",
                       context_text, wanted_a, wanted_b, a_compute_addr, b_compute_addr);
            checks = checks + 1;
        end
    endtask

    task automatic idle_edge(
        input bit wanted_done,
        input bit request_start,
        input bit write_a,
        input bit write_b,
        input string label_text
    );
        @(negedge clk);
        start = request_start;
        a_we = write_a;
        b_we = write_b;
        #1;
        check_idle(wanted_done, {label_text, ": before edge"});
        @(posedge clk);
        check_idle(wanted_done, {label_text, ": at edge"});
        #1;
        check_idle(wanted_done, {label_text, ": after updates"});
    endtask

    task automatic check_write_collisions(input bit wanted_done);
        for (integer mode = 1; mode <= 3; mode = mode + 1) begin
            begin_job(mode == 1 ? wanted_done : 1'b1,
                      $sformatf("start with writes %0d (initial done=%b)", mode, wanted_done),
                      mode != 2, mode != 1);
            finish_job($sformatf("start with writes %0d (initial done=%b)", mode, wanted_done));
            idle_edge(1'b1, 1'b0, 1'b0, 1'b0, "single start launches only one job");
        end
    endtask

    task automatic missed_start_pulse(input bit wanted_done);
        @(negedge clk);
        start = 1'b1;
        a_we = 1'b0;
        b_we = 1'b0;
        #1;
        check_idle(wanted_done, "between-edge start pulse");
        #1;
        start = 1'b0;
        @(posedge clk);
        #1;
        check_idle(wanted_done, "start pulse missed the sampling edge");
    endtask

    task automatic begin_job(
        input bit previous_done,
        input string label_text,
        input bit write_a = 1'b0,
        input bit write_b = 1'b0
    );
        @(negedge clk);
        start = 1'b1;
        a_we = write_a;
        b_we = write_b;
        #1;
        check_idle(previous_done, {label_text, ": before accepting start"});
        @(posedge clk);
        check_idle(previous_done, {label_text, ": at start edge"});
        #1;
        check_work(1, {label_text, ": start accepted, CLEAR ready"});
    endtask

    task automatic work_edge(
        input integer cycle,
        input bit busy_noise,
        input bit hold_start,
        input string label_text
    );
        @(negedge clk);
        start = busy_noise || hold_start;
        // Cycle through A-only, B-only, and simultaneous host writes.
        a_we = busy_noise && (cycle % 3 != 1);
        b_we = busy_noise && (cycle % 3 != 2);
        #1;
        check_work(cycle, {label_text, ": before edge"});
        @(posedge clk);
        // These are the requests a memory/MAC would sample at this edge.
        check_work(cycle, {label_text, ": at edge"});
        clear_edges = clear_edges + mac_clear;
        read_edges = read_edges + compute_re;
        mac_edges = mac_edges + mac_enable;
        store_edges = store_edges + c_compute_we;
        #1;
        // One ns allows nonblocking updates; it is not an extra clock cycle.
        if (cycle == WORK_CYCLES)
            check_idle(1'b1, {label_text, ": final STORE completed"});
        else
            check_work(cycle + 1, {label_text, ": after updates"});
    endtask

    task automatic finish_job(
        input string label_text,
        input bit busy_noise = 1'b0,
        input bit hold_start = 1'b0
    );
        clear_edges = 0;
        read_edges = 0;
        mac_edges = 0;
        store_edges = 0;
        for (integer cycle = 1; cycle <= WORK_CYCLES; cycle = cycle + 1)
            work_edge(cycle, busy_noise, hold_start, label_text);
        if (clear_edges != 64 || read_edges != 512 || mac_edges != 512 || store_edges != 64)
            $fatal(1, "%s: expected clear/read/mac/store counts 64/512/512/64, got %0d/%0d/%0d/%0d",
                   label_text, clear_edges, read_edges, mac_edges, store_edges);
        completed_jobs = completed_jobs + 1;
        $display("PASS: %s (1152 cycles; 64 clears, 512 reads, 512 MACs, 64 stores)", label_text);
    endtask

    // next_cycle=0 means idle; otherwise it identifies the pending work edge.
    task automatic apply_reset(
        input integer next_cycle,
        input bit previous_done,
        input string label_text
    );
        @(negedge clk);
        reset = 1'b1;
        start = 1'b1; // Reset must take priority over start, including in IDLE.
        a_we = 1'b0;
        b_we = 1'b0;
        #1;
        if (next_cycle == 0)
            check_idle(previous_done, {label_text, ": reset before edge"});
        else
            check_work(next_cycle, {label_text, ": reset before edge"});
        @(posedge clk);
        // Controller requests still reflect the old state before updates.
        // The memory wrapper separately gates these requests during reset.
        if (next_cycle == 0)
            check_idle(previous_done, {label_text, ": reset sampling edge"});
        else
            check_work(next_cycle, {label_text, ": reset sampling edge"});
        #1;
        check_reset({label_text, ": after reset updates"});
        repeat (2) begin
            @(posedge clk);
            #1;
            check_reset({label_text, ": held reset overrides start"});
        end
        @(negedge clk);
        reset = 1'b0;
        start = 1'b0;
        idle_edge(1'b0, 1'b0, 1'b0, 1'b0, {label_text, ": reset released"});
    endtask

    initial begin
        repeat (2) begin
            @(posedge clk);
            #1;
            check_reset("initial reset overrides start");
        end
        @(negedge clk);
        reset = 1'b0;
        start = 1'b0;
        idle_edge(1'b0, 1'b0, 1'b0, 1'b0, "idle after reset");
        missed_start_pulse(1'b0);
        check_write_collisions(1'b0);
        $display("PASS: reset, idle, write/start collisions, and between-edge start pulse");

        begin_job(1'b1, "baseline job");
        finish_job("baseline job");
        repeat (3)
            idle_edge(1'b1, 1'b0, 1'b0, 1'b0, "done stays asserted while idle");
        for (integer mode = 1; mode <= 3; mode = mode + 1)
            idle_edge(1'b1, 1'b0, mode != 2, mode != 1, "writes without start preserve done");
        check_write_collisions(1'b1);
        missed_start_pulse(1'b1);
        $display("PASS: done holds through idle edges and writes, and clears on accepted starts");

        begin_job(1'b1, "busy requests");
        finish_job("busy requests", 1'b1);
        idle_edge(1'b1, 1'b0, 1'b0, 1'b0, "busy starts are not queued");

        begin_job(1'b1, "held start first job");
        finish_job("held start first job", 1'b0, 1'b1);
        // start stays high through completion and the very next idle edge.
        begin_job(1'b1, "held start second job");
        finish_job("held start second job");

        // Abort in CLEAR, READ, MAC, STORE, the next output's CLEAR,
        // READ/MAC with nonzero row/column/k, and the final STORE.
        reset_offsets[0] = 0;
        reset_offsets[1] = 1;
        reset_offsets[2] = 2;
        reset_offsets[3] = 17;
        reset_offsets[4] = 18;
        reset_offsets[5] = 171;
        reset_offsets[6] = 172;
        reset_offsets[7] = WORK_CYCLES - 1;
        for (integer i = 0; i < 8; i = i + 1) begin
            begin_job(1'b1, "job to abort");
            for (integer cycle = 1; cycle <= reset_offsets[i]; cycle = cycle + 1)
                work_edge(cycle, 1'b0, 1'b0, "before abort");
            apply_reset(reset_offsets[i] + 1, 1'b0,
                        $sformatf("reset at offset %0d", reset_offsets[i]));
            begin_job(1'b0, "restart after reset");
            finish_job($sformatf("restart after reset at offset %0d", reset_offsets[i]));
        end
        apply_reset(0, 1'b1, "reset clears sticky done in IDLE");

        $display("PASS: controller completed %0d jobs, 8 busy reset cases, and %0d checks",
                 completed_jobs, checks);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "GEMM controller testbench timed out");
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module tb_de2_115_gemm;
    `include "gemm_vectors.svh"
    localparam integer VECTOR_WORDS = CASE_COUNT * 64;
    localparam integer SUITE_LIMIT = CASE_COUNT * 900 + 100;
    logic clk = 0;
    logic [1:0] KEY = 2'b11;
    logic LED_READY, LED_BUSY, LED_PASS, LED_FAIL;
    integer jobs_started = 0;
    integer suite_jobs = 0;
    integer suite_checks = 0;
    integer total_checks = 0;
    integer suites_passed = 0;
    integer loads = 0;
    integer checks = 0;
    integer abort_offsets [0:5];
    bit injecting_fault = 0;
    logic signed [7:0] vectors_a [0:VECTOR_WORDS-1];
    logic signed [7:0] vectors_b [0:VECTOR_WORDS-1];

    initial begin
        $readmemh("inputs_a.hex", vectors_a);
        $readmemh("inputs_b.hex", vectors_b);
    end

    always #10 clk = ~clk;
    de2_115_gemm_top dut (.*);

    // Mathematical oracle independent of the stored expected.hex words.
    function automatic integer reference(input integer case_number, input integer address);
        integer r, c, a, b;
        r = address / 8;
        c = address % 8;
        reference = 0;
        for (integer k = 0; k < 8; k = k + 1) begin
            a = vectors_a[case_number*64 + r*8 + k];
            b = vectors_b[case_number*64 + k*8 + c];
            reference += a * b;
        end
    endfunction

    // Observe what the core samples, before nonblocking updates at each edge.
    always @(posedge clk) begin
        if (dut.core_rst) begin
            loads = 0;
            checks = 0;
            suite_jobs = 0;
            suite_checks = 0;
        end else begin
            if (dut.load_we) begin
                if (dut.core_busy || suite_jobs >= CASE_COUNT ||
                    suite_checks != suite_jobs*64 || dut.case_index_q !== suite_jobs ||
                    loads >= 64 || dut.word_index_q !== loads ||
                    dut.a_value_q !== vectors_a[suite_jobs*64 + loads] ||
                    dut.b_value_q !== vectors_b[suite_jobs*64 + loads])
                    $fatal(1, "incorrect operand load at case %0d index %0d", suite_jobs, loads);
                loads = loads + 1;
            end
            if (dut.core_start) begin
                if (loads != 64 || dut.core_busy || dut.case_index_q !== suite_jobs)
                    $fatal(1, "GEMM started before loading both matrices");
                jobs_started = jobs_started + 1;
                suite_jobs = suite_jobs + 1;
                loads = 0;
                checks = 0;
            end
            if (dut.state_q == dut.CHECK_C && !injecting_fault) begin
                if (dut.case_index_q !== suite_jobs - 1 || dut.word_index_q !== checks ||
                    dut.c_value !== reference(suite_jobs - 1, checks))
                    $fatal(1, "incorrect readback at case %0d C[%0d]", suite_jobs - 1, checks);
                checks = checks + 1;
                suite_checks = suite_checks + 1;
                total_checks = total_checks + 1;
            end
        end
    end

    task automatic tick;
        @(posedge clk); #1;
    endtask

    task automatic press_start;
        if (LED_READY !== 1)
            $fatal(1, "board must be ready before a new test");
        @(negedge clk);
        KEY[1] = 0;
        repeat (5) tick();
        if ({LED_READY, LED_BUSY, LED_PASS, LED_FAIL} !== 4'b0100)
            $fatal(1, "button did not launch a test and clear previous LEDs");
    endtask

    task automatic release_start;
        @(negedge clk);
        KEY[1] = 1;
        repeat (4) tick();
    endtask

    task automatic await_result(input bit want_pass, input integer limit = SUITE_LIMIT);
        integer cycles;
        cycles = 0;
        while (LED_READY !== 1 && cycles < limit) begin
            tick();
            cycles = cycles + 1;
        end
        if ({LED_READY, LED_BUSY, LED_PASS, LED_FAIL}
            !== {1'b1, 1'b0, want_pass, !want_pass})
            $fatal(1, "expected pass=%b, got ready/busy/pass/fail=%b",
                   want_pass, {LED_READY, LED_BUSY, LED_PASS, LED_FAIL});
        if (want_pass) begin
            if (suite_jobs != CASE_COUNT || suite_checks != VECTOR_WORDS || checks != 64)
                $fatal(1, "PASS asserted without checking all %0d pairs / %0d C words",
                       CASE_COUNT, VECTOR_WORDS);
            suites_passed = suites_passed + 1;
        end
    endtask

    task automatic rst_board;
        @(negedge clk);
        KEY = 2'b10;
        #1;
        if ({LED_READY, LED_BUSY, LED_PASS, LED_FAIL} !== 0)
            $fatal(1, "reset did not suppress LEDs immediately");
        repeat (3) tick();
        @(negedge clk);
        KEY = 2'b11;
        repeat (4) tick();
        if ({LED_READY, LED_BUSY, LED_PASS, LED_FAIL} !== 4'b1000)
            $fatal(1, "reset did not restore idle");
    endtask

    initial begin : tests
        integer previous_jobs;
        integer fault_case, fault_word;
        // Initial reset must work after configuration without pressing KEY0.
        repeat (6) tick();
        if ({LED_READY, LED_BUSY, LED_PASS, LED_FAIL} !== 4'b1000)
            $fatal(1, "power-up reset failed");
        for (integer i = 0; i < VECTOR_WORDS; i = i + 1) begin
            if ((^vectors_a[i] === 1'bx) || (^vectors_b[i] === 1'bx))
                $fatal(1, "missing input data at address %0d", i);
            if (dut.expected[i] !== reference(i / 64, i % 64))
                $fatal(1, "expected.hex missing or incorrect at address %0d", i);
        end

        press_start();
        await_result(1);
        $display("PASS: full board suite: %0d pairs, %0d independently checked outputs",
                 suite_jobs, suite_checks);
        previous_jobs = jobs_started;
        repeat (100) tick(); // Keep KEY1 held after completion.
        if (jobs_started != previous_jobs || LED_PASS !== 1)
            $fatal(1, "held button retriggered or PASS did not hold");
        release_start();

        // A new press during work is consumed, not queued for after completion.
        press_start();
        release_start();
        repeat (80) tick();
        @(negedge clk);
        KEY[1] = 0;
        await_result(1);
        previous_jobs = jobs_started;
        repeat (100) tick();
        if (jobs_started != previous_jobs || LED_PASS !== 1)
            $fatal(1, "busy button press was queued");
        release_start();

        // Exercise FAIL at the first, middle, and very last comparison. Injection is
        // testbench-only; no fault mux or switch is added to the real hardware.
        for (integer which = 0; which < 3; which = which + 1) begin
            fault_case = (which == 0) ? 0 : ((which == 1) ? CASE_COUNT/2 : CASE_COUNT-1);
            fault_word = (which == 0) ? 0 : ((which == 1) ? 31 : 63);
            press_start();
            release_start();
            while (dut.state_q !== dut.CHECK_C || dut.case_index_q != fault_case ||
                   dut.word_index_q != fault_word)
                @(negedge clk);
            injecting_fault = 1;
            force dut.c_value = 32'sh12345678;
            previous_jobs = jobs_started;
            tick();
            await_result(0);
            release dut.c_value;
            injecting_fault = 0;
            repeat (4) tick();
            if (LED_FAIL !== 1 || jobs_started != previous_jobs)
                $fatal(1, "FAIL did not hold or another pair started after a mismatch");
        end

        // Verify the board reports a stalled core and can run again afterward.
        press_start();
        release_start();
        while (dut.case_index_q != CASE_COUNT/2 || dut.state_q != dut.WAIT_CORE)
            @(negedge clk);
        force dut.core_done = 1'b0;
        await_result(0, 5000);
        release dut.core_done;
        press_start();
        release_start();
        await_result(1);

        // Reset during input loading, then during different GEMM phases and
        // result reads. Each restart must refill the FIFOs and recompute C.
        press_start();
        rst_board();
        abort_offsets[0] = 0;
        abort_offsets[1] = 9;
        abort_offsets[2] = 20;
        abort_offsets[3] = 31;
        abort_offsets[4] = 544;
        abort_offsets[5] = 570;
        for (integer i = 0; i < 6; i = i + 1) begin
            press_start();
            release_start();
            wait (dut.core_busy === 1);
            repeat (abort_offsets[i]) tick();
            rst_board();
            press_start();
            release_start();
            await_result(1);
        end

        // Reset between pairs late in the suite; the next press must start at
        // case zero, with fresh input loads and no stale PASS or case counter.
        press_start();
        release_start();
        while (dut.case_index_q != CASE_COUNT-1 || dut.state_q != dut.READ_INPUT)
            @(negedge clk);
        rst_board();
        press_start();
        release_start();
        await_result(1);
        rst_board();

        $display("PASS: %0d full suites; %0d total output checks", suites_passed, total_checks);
        $display("PASS: DE2-115 power-up, consecutive pairs, sticky LEDs, held/busy button behavior");
        $display("PASS: first/middle/final faults, later-pair timeout, reset during loading, work and between pairs");
        $finish;
    end

    initial begin
        #(CASE_COUNT * 1000 * 20 * 30);
        $fatal(1, "DE2-115 testbench timed out");
    end
endmodule

`default_nettype wire

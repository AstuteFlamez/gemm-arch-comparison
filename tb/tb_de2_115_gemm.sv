`timescale 1ns/1ps
`default_nettype none

module tb_de2_115_gemm;
    logic CLOCK_50 = 0;
    logic [1:0] KEY = 2'b11;
    logic LED_READY, LED_BUSY, LED_PASS, LED_FAIL;
    integer jobs_started = 0;
    integer loads = 0;
    integer checks = 0;
    integer abort_offsets [0:5];
    bit injecting_fault = 0;

    always #10 CLOCK_50 = ~CLOCK_50;
    de2_115_gemm_top dut (.*);

    // Mathematical oracle independent of the stored expected.hex words.
    function automatic integer reference(input integer address);
        integer r, c;
        r = address / 8;
        c = address % 8;
        reference = 0;
        for (integer k = 0; k < 8; k = k + 1)
            reference += (r*8 + k - 32) * (31 - k*8 - c);
    endfunction

    // Observe what the core samples, before nonblocking updates at each edge.
    always @(posedge CLOCK_50) begin
        if (dut.core_reset) begin
            loads = 0;
            checks = 0;
        end else begin
            if (dut.load_we) begin
                if (loads >= 64 || dut.word_index !== loads ||
                    dut.a_value !== loads - 32 || dut.b_value !== 31 - loads)
                    $fatal(1, "incorrect operand load at index %0d", loads);
                loads = loads + 1;
            end
            if (dut.core_start) begin
                if (loads != 64)
                    $fatal(1, "GEMM started before loading both matrices");
                jobs_started = jobs_started + 1;
            end
            if (dut.state == dut.CHECK_C && !injecting_fault) begin
                if (dut.word_index !== checks || dut.c_value !== reference(checks))
                    $fatal(1, "incorrect readback at C[%0d]", checks);
                checks = checks + 1;
            end
        end
    end

    task automatic tick;
        @(posedge CLOCK_50); #1;
    endtask

    task automatic press_start;
        if (LED_READY !== 1)
            $fatal(1, "board must be ready before a new test");
        @(negedge CLOCK_50);
        KEY[1] = 0;
        repeat (5) tick();
        if ({LED_READY, LED_BUSY, LED_PASS, LED_FAIL} !== 4'b0100)
            $fatal(1, "button did not launch a test and clear previous LEDs");
    endtask

    task automatic release_start;
        @(negedge CLOCK_50);
        KEY[1] = 1;
        repeat (4) tick();
    endtask

    task automatic await_result(input bit want_pass, input integer limit = 1000);
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
        if (want_pass && checks != 64)
            $fatal(1, "PASS asserted without checking all 64 C words");
    endtask

    task automatic reset_board;
        @(negedge CLOCK_50);
        KEY = 2'b10;
        #1;
        if ({LED_READY, LED_BUSY, LED_PASS, LED_FAIL} !== 0)
            $fatal(1, "reset did not suppress LEDs immediately");
        repeat (3) tick();
        @(negedge CLOCK_50);
        KEY = 2'b11;
        repeat (4) tick();
        if ({LED_READY, LED_BUSY, LED_PASS, LED_FAIL} !== 4'b1000)
            $fatal(1, "reset did not restore idle");
    endtask

    initial begin : tests
        integer previous_jobs;
        // Initial reset must work after configuration without pressing KEY0.
        repeat (6) tick();
        if ({LED_READY, LED_BUSY, LED_PASS, LED_FAIL} !== 4'b1000)
            $fatal(1, "power-up reset failed");
        for (integer i = 0; i < 64; i = i + 1)
            if (dut.expected[i] !== reference(i))
                $fatal(1, "expected.hex missing or incorrect at address %0d", i);

        press_start();
        await_result(1);
        previous_jobs = jobs_started;
        repeat (100) tick(); // Keep KEY1 held after completion.
        if (jobs_started != previous_jobs || LED_PASS !== 1)
            $fatal(1, "held button retriggered or PASS did not hold");
        release_start();

        // A new press during work is consumed, not queued for after completion.
        press_start();
        release_start();
        repeat (80) tick();
        @(negedge CLOCK_50);
        KEY[1] = 0;
        await_result(1);
        previous_jobs = jobs_started;
        repeat (100) tick();
        if (jobs_started != previous_jobs || LED_PASS !== 1)
            $fatal(1, "busy button press was queued");
        release_start();

        // Exercise FAIL for both the first and final comparison. Injection is
        // testbench-only; no fault mux or switch is added to the real hardware.
        for (integer which = 0; which < 2; which = which + 1) begin
            press_start();
            release_start();
            while (dut.state !== dut.CHECK_C || dut.word_index != which*63)
                @(negedge CLOCK_50);
            injecting_fault = 1;
            force dut.c_value = 32'sh12345678;
            tick();
            await_result(0);
            release dut.c_value;
            injecting_fault = 0;
            repeat (4) tick();
            if (LED_FAIL !== 1)
                $fatal(1, "FAIL did not hold");
        end

        // Verify the board reports a stalled core and can run again afterward.
        press_start();
        release_start();
        force dut.core_done = 1'b0;
        await_result(0, 5000);
        release dut.core_done;
        press_start();
        release_start();
        await_result(1);

        // Reset during input loading, then during different GEMM phases and
        // result reads. Each restart must refill the FIFOs and recompute C.
        press_start();
        reset_board();
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
            reset_board();
            press_start();
            release_start();
            await_result(1);
        end
        reset_board();

        $display("PASS: DE2-115 power-up, signed matrix readback, sticky LEDs, held/busy button behavior");
        $display("PASS: first/last-word faults, timeout recovery, reset during loading and 6 work phases");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "DE2-115 testbench timed out");
    end
endmodule

`default_nettype wire

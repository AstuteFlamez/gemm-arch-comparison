`timescale 1ns/1ps
`default_nettype none

module tb_fifo;
    parameter int DATA_WIDTH = 8;
    parameter int DEPTH = 4;
    logic clk = 0;
    logic reset = 1;
    logic push = 0;
    logic pop = 0;
    logic [DATA_WIDTH-1:0] data_in = 0;
    wire [DATA_WIDTH-1:0] data_out;
    wire full, empty;

    // Reference queue shifts on removal; it does not copy the DUT's pointers.
    logic [DATA_WIDTH-1:0] expected_queue [0:DEPTH-1];
    logic [DATA_WIDTH-1:0] expected_out = 0;
    integer queued = 0;
    integer cycles = 0;
    integer checks = 0;
    integer accepted_pushes = 0;
    integer accepted_pops = 0;
    integer coverage [0:DEPTH][0:3];
    integer reset_coverage [0:DEPTH][0:3];
    bit initialized = 0;
    logic [31:0] rng;
    integer seed;

    // The normal target also supports the original fixed 4x8 learning RTL.
    // The configuration target explicitly requires real DUT parameters.
`ifdef FIFO_PARAMETERIZED
    fifo #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
`else
    fifo dut (
`endif
        .clk(clk), .reset(reset), .push(push), .pop(pop),
        .data_in(data_in), .data_out(data_out), .full(full), .empty(empty)
    );
    always #5 clk = ~clk;

    task automatic check_outputs(input string label_text);
        if (data_out !== expected_out || full !== (queued == DEPTH) ||
            empty !== (queued == 0))
            $fatal(1, "%s cycle=%0d time=%0t reset/push/pop=%b%b%b count=%0d: expected out/full/empty=%h/%b/%b, got %h/%b/%b",
                   label_text, cycles, $time, reset, push, pop, queued,
                   expected_out, (queued == DEPTH), (queued == 0),
                   data_out, full, empty);
        checks = checks + 1;
    endtask

    // Called at a rising edge before the DUT's nonblocking updates take effect.
    task automatic sample_edge;
        bit take_push, take_pop;
        integer request_kind;
        if (initialized) check_outputs("before register updates");
        request_kind = {push, pop};
        if (reset) begin
            reset_coverage[queued][request_kind] = reset_coverage[queued][request_kind] + 1;
            queued = 0;
            expected_out = 0;
        end else begin
            coverage[queued][request_kind] = coverage[queued][request_kind] + 1;
            // Decide BOTH operations from occupancy before the edge.
            take_push = push && queued < DEPTH;
            take_pop = pop && queued > 0;
            if (take_pop) begin
                expected_out = expected_queue[0];
                for (integer i = 0; i < queued - 1; i = i + 1)
                    expected_queue[i] = expected_queue[i + 1];
                queued = queued - 1;
                accepted_pops = accepted_pops + 1;
            end
            if (take_push) begin
                expected_queue[queued] = data_in;
                queued = queued + 1;
                accepted_pushes = accepted_pushes + 1;
            end
        end
        cycles = cycles + 1;
        #1; // Observe registered outputs after nonblocking updates settle.
        initialized = 1;
        check_outputs("after register updates");
    endtask

    task automatic step(
        input bit rst, input bit request_push, input bit request_pop,
        input logic [DATA_WIDTH-1:0] value
    );
        @(negedge clk);
        reset = rst;
        push = request_push;
        pop = request_pop;
        data_in = value;
        #1;
        check_outputs("inputs changed between rising edges");
        @(posedge clk);
        sample_edge();
    endtask

    // A local generator makes the stimulus reproducible across simulators.
    task automatic next_random;
        rng = rng * 32'd1664525 + 32'd1013904223;
    endtask

    initial begin
        if (DEPTH < 2 || DATA_WIDTH < 1)
            $fatal(1, "Supported FIFO configurations require DEPTH >= 2 and DATA_WIDTH >= 1");
`ifdef FIFO_PARAMETERIZED
        // Icarus can merely warn about nonexistent override parameters. These
        // references make missing parameters an elaboration error instead.
        if (dut.DEPTH != DEPTH || dut.DATA_WIDTH != DATA_WIDTH)
            $fatal(1, "DUT parameter overrides did not take effect");
`else
        if (DEPTH != 4 || DATA_WIDTH != 8)
            $fatal(1, "Use the parameterized test target for nondefault configurations");
`endif
        for (integer n = 0; n <= DEPTH; n = n + 1)
            for (integer op = 0; op < 4; op = op + 1) begin
                coverage[n][op] = 0;
                reset_coverage[n][op] = 0;
            end
        if (!$value$plusargs("SEED=%d", seed)) seed = 20260917;
        rng = seed;
        $display("FIFO test depth=%0d width=%0d seed=%0d", DEPTH, DATA_WIDTH, seed);
        @(posedge clk);
        sample_edge();

        // Exercise every request combination at EVERY occupancy. Drain after
        // each experiment to expose lost, duplicated, reordered, or extra data.
        for (integer n = 0; n <= DEPTH; n = n + 1)
            for (integer op = 0; op < 4; op = op + 1) begin
                step(1, 0, 0, 0);
                for (integer i = 0; i < n; i = i + 1)
                    step(0, 1, 0, DATA_WIDTH'(i * 57 + n));
                step(0, op[1], op[0], DATA_WIDTH'('hA0 + op));
                repeat (DEPTH + 1) step(0, 0, 1, 0);
            end
        $display("PASS: all %0d occupancy/request combinations, ordering, overflow and underflow rejection", 4 * (DEPTH + 1));

        // Continuous simultaneous transfers repeatedly wrap both pointers.
        // Check every partial occupancy, including repeated wrap at depth 6.
        for (integer n = 1; n < DEPTH; n = n + 1) begin
            step(1, 0, 0, 0);
            for (integer i = 0; i < n; i = i + 1)
                step(0, 1, 0, DATA_WIDTH'(i + 17));
            for (integer i = 0; i < 256; i = i + 1)
                step(0, 1, 1, DATA_WIDTH'(i));
            repeat (DEPTH) step(0, 0, 1, 0);
        end
        $display("PASS: simultaneous transfers at every partial occupancy and repeated pointer wraparound");

        // Exercise every bit, especially bits above the original 8-bit width.
        for (integer i = 0; i < DATA_WIDTH; i = i + 1) begin
            step(0, 1, 0, DATA_WIDTH'(1) << i);
            step(0, 0, 1, 0);
            step(0, 1, 0, ~(DATA_WIDTH'(1) << i));
            step(0, 0, 1, 0);
        end
        step(0, 1, 0, '1);
        step(0, 0, 1, 0);
        step(0, 1, 0, '0);
        step(0, 0, 1, 0);
        $display("PASS: walking ones/zeros across all %0d data bits, all ones, and zero", DATA_WIDTH);

        // Reset wins over each request combination at every occupancy.
        for (integer n = 0; n <= DEPTH; n = n + 1)
            for (integer op = 0; op < 4; op = op + 1) begin
                step(1, 0, 0, 0);
                for (integer i = 0; i < n; i = i + 1)
                    step(0, 1, 0, DATA_WIDTH'('h80 + i));
                step(1, op[1], op[0], '1);
                step(1, 1, 1, '1); // Held reset still overrides requests.
                step(0, 0, 1, 0);  // Old queued data is no longer valid.
                step(0, 1, 0, '1);
                step(0, 0, 1, 0);
                repeat (2) step(0, 0, 0, 'hFF);
            end
        $display("PASS: reset at every occupancy with all requests, held reset, and reuse after reset");

        // Pulses entirely between rising edges must have no effect, including
        // synchronous reset. Keep one queued item and a nonzero output value.
        step(0, 1, 0, 'hC3);
        @(negedge clk);
        reset = 1; push = 1; pop = 1; data_in = 'hEE;
        #1;
        check_outputs("between-edge reset and request pulses");
        #1;
        reset = 0; push = 0; pop = 0;
        @(posedge clk);
        sample_edge();
        step(0, 0, 1, 0);
        $display("PASS: synchronous reset and requests, output hold between operations");

        repeat (2000) begin
            next_random();
            step(rng[15:8] == 0, rng[31], rng[23], DATA_WIDTH'(rng));
        end
        repeat (DEPTH + 1) step(0, 0, 1, 0);
        for (integer n = 0; n <= DEPTH; n = n + 1)
            for (integer op = 0; op < 4; op = op + 1)
                if (coverage[n][op] == 0 || reset_coverage[n][op] == 0)
                    $fatal(1, "Missing coverage: occupancy=%0d request=%0d", n, op);
        $display("PASS: FIFO depth=%0d width=%0d completed %0d cycles, %0d output checks, %0d accepted pushes and %0d accepted pops; all %0d normal and %0d reset combinations covered",
                 DEPTH, DATA_WIDTH, cycles, checks, accepted_pushes, accepted_pops,
                 4 * (DEPTH + 1), 4 * (DEPTH + 1));
        $finish;
    end

    initial begin
        #(100000 + DEPTH * DEPTH * 1000 + DATA_WIDTH * 100);
        $fatal(1, "FIFO testbench timed out");
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// These directed tests use locations 0 through 6, plus the last location.
// The default matches GEMM; parameter overrides also exercise a wider RAM.
module tb_sram;
    parameter int DATA_WIDTH = 8;
    parameter int DEPTH = 64;
    localparam int ADDR_WIDTH = $clog2(DEPTH);

    logic clk = 1'b0;
    logic re = 1'b0;
    logic we = 1'b0;
    logic [ADDR_WIDTH-1:0] addr = '0;
    logic [DATA_WIDTH-1:0] wdata = '0;
    logic [DATA_WIDTH-1:0] rdata;
    integer checks = 0;

    sram #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) dut (
        .clk(clk), .re(re), .we(we),
        .addr(addr), .wr_data(wdata), .rd_data(rdata)
    );

    // A 10 ns clock period. Delays belong in the testbench, not the RAM RTL.
    always #5 clk = ~clk;

    task automatic check_rdata(
        input logic [DATA_WIDTH-1:0] expected,
        input string label_text
    );
        // Case inequality also detects unexpected X/Z bits.
        if (rdata !== expected)
            $fatal(1, "%s at %0t: expected rdata=%h, got %h",
                   label_text, $time, expected, rdata);
        checks = checks + 1;
    endtask

    task automatic write_word(
        input logic [ADDR_WIDTH-1:0] write_addr,
        input logic [DATA_WIDTH-1:0] value,
        input bit also_request_read = 1'b0
    );
        logic [DATA_WIDTH-1:0] previous_read;
        // Drive on falling edges so inputs settle before the rising edge.
        @(negedge clk);
        previous_read = rdata;
        addr = write_addr;
        wdata = value;
        we = 1'b1;
        re = also_request_read;
        #1;
        check_rdata(previous_read, "write: output holds before rising edge");
        @(posedge clk);
        check_rdata(previous_read, "write: output holds at rising edge");
        #1;
        check_rdata(previous_read, "write: output holds after updates");
    endtask

    task automatic read_word(
        input logic [ADDR_WIDTH-1:0] read_addr,
        input logic [DATA_WIDTH-1:0] expected
    );
        logic [DATA_WIDTH-1:0] previous_read;
        @(negedge clk);
        previous_read = rdata;
        addr = read_addr;
        we = 1'b0;
        re = 1'b1;
        #1;
        check_rdata(previous_read, "read: output holds before rising edge");
        @(posedge clk);
        // We are still before nonblocking assignments update the registers.
        check_rdata(previous_read, "read: old output at sampling edge");
        #1;
        // One ns lets the simulator finish those updates; it is not an
        // additional clock cycle or a delay implemented inside the RAM.
        check_rdata(expected, $sformatf("read: address %0d after updates", read_addr));
    endtask

    function automatic logic [DATA_WIDTH-1:0] pattern(input integer index);
        pattern = DATA_WIDTH'(index * 3 + 17);
    endfunction

    initial begin
        if (DATA_WIDTH < 8 || DEPTH < 7)
            $fatal(1, "This testbench requires DATA_WIDTH >= 8 and DEPTH >= 7");

        // No initialization is promised. Reading an unwritten word gives X.
        #1;
        check_rdata('x, "read output starts unknown");
        read_word(ADDR_WIDTH'(DEPTH - 1), 'x);
        $display("PASS: uninitialized output and unwritten memory are unknown");

        // First learning example: write 13 into location 5, then read it.
        write_word(ADDR_WIDTH'(5), DATA_WIDTH'(13));
        read_word(ADDR_WIDTH'(5), DATA_WIDTH'(13));
        $display("PASS: write 13 to address 5, then synchronously read 13");

        // Distinct values expose address aliasing. Include first/last words.
        for (integer i = 0; i < DEPTH; i = i + 1)
            write_word(ADDR_WIDTH'(i), pattern(i));
        // re stays high across these consecutive reads. Each rising edge
        // must return that edge's selected word, with no extra register stage.
        for (integer i = 0; i < DEPTH; i = i + 1)
            read_word(ADDR_WIDTH'(i), pattern(i));
        $display("PASS: every address, including first/last, and consecutive reads");

        // Overwriting one word must leave its neighbors intact.
        write_word(ADDR_WIDTH'(5), DATA_WIDTH'(99));
        read_word(ADDR_WIDTH'(5), DATA_WIDTH'(99));
        read_word(ADDR_WIDTH'(4), pattern(4));
        read_word(ADDR_WIDTH'(6), pattern(6));
        $display("PASS: overwrite changes only the selected word");

        // With both enables low, changing address/data must change neither
        // rdata nor the stored words, even across multiple rising edges.
        read_word(ADDR_WIDTH'(5), DATA_WIDTH'(99));
        repeat (2) begin
            @(negedge clk);
            we = 1'b0;
            re = 1'b0;
            addr = ADDR_WIDTH'(2);
            wdata = DATA_WIDTH'(55);
            #1;
            check_rdata(DATA_WIDTH'(99), "disabled read: address change ignored");
            @(posedge clk);
            #1;
            check_rdata(DATA_WIDTH'(99), "disabled operations: output holds");
        end
        read_word(ADDR_WIDTH'(2), pattern(2));
        $display("PASS: disabled reads hold output and disabled writes preserve data");

        // A write-enable pulse entirely between rising edges must not write.
        read_word(ADDR_WIDTH'(5), DATA_WIDTH'(99));
        @(negedge clk);
        re = 1'b0;
        we = 1'b1;
        addr = ADDR_WIDTH'(5);
        wdata = DATA_WIDTH'(66);
        #2;
        we = 1'b0;
        @(posedge clk);
        #1;
        check_rdata(DATA_WIDTH'(99), "between-edge write pulse: output holds");
        read_word(ADDR_WIDTH'(5), DATA_WIDTH'(99));
        $display("PASS: write requests require a rising edge");

        // Likewise, a read-enable pulse between rising edges must not read.
        @(negedge clk);
        addr = ADDR_WIDTH'(2);
        we = 1'b0;
        re = 1'b1;
        #1;
        check_rdata(DATA_WIDTH'(99), "between-edge read pulse: output holds");
        #1;
        re = 1'b0;
        @(posedge clk);
        #1;
        check_rdata(DATA_WIDTH'(99), "missed read pulse: output still holds");
        $display("PASS: read requests require a rising edge");

        // Old word=99, new word=33, previous output=17: all differ, so this
        // distinguishes our hold-output policy from reading old or new data.
        read_word(ADDR_WIDTH'(0), pattern(0));
        write_word(ADDR_WIDTH'(5), DATA_WIDTH'(33), 1'b1);
        read_word(ADDR_WIDTH'(5), DATA_WIDTH'(33));
        $display("PASS: simultaneous read/write writes and holds read output");

        // Storage preserves bits. At an INT8 compute interface, 80/ff/fd
        // would be interpreted as -128/-1/-3; SRAM itself is unsigned.
        write_word(ADDR_WIDTH'(DEPTH - 1), '0);
        read_word(ADDR_WIDTH'(DEPTH - 1), '0);
        write_word(ADDR_WIDTH'(DEPTH - 1), DATA_WIDTH'(8'h7f));
        read_word(ADDR_WIDTH'(DEPTH - 1), DATA_WIDTH'(8'h7f));
        write_word(ADDR_WIDTH'(DEPTH - 1), DATA_WIDTH'(8'h80));
        read_word(ADDR_WIDTH'(DEPTH - 1), DATA_WIDTH'(8'h80));
        write_word(ADDR_WIDTH'(DEPTH - 1), DATA_WIDTH'(8'hfd));
        read_word(ADDR_WIDTH'(DEPTH - 1), DATA_WIDTH'(8'hfd));
        write_word(ADDR_WIDTH'(DEPTH - 1), '1);
        read_word(ADDR_WIDTH'(DEPTH - 1), '1);
        $display("PASS: zero, sign-bit patterns, and all bits set survive storage");

        $display("PASS: SRAM %0d x %0d completed %0d checks",
                 DEPTH, DATA_WIDTH, checks);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "SRAM testbench timed out");
    end
endmodule

`default_nettype wire

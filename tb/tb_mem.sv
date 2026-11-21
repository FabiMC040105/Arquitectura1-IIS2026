`timescale 1ns/1ps

// Testbench: baseline memory latency + eviction buffer behaviour.
// Run (Icarus):  iverilog -g2012 -o sim sync2.sv mem_ctrl.sv mem_subsystem.sv tb_mem.sv && vvp sim
module tb_mem;
    localparam int RATIO     = 5;       // Fp/Fm (20 MHz memory). Use 2, 4 or 5.
    localparam int FIRST_LAT = 3;       // clk_mem cycles; calibrate with the printout
    localparam int CPU_HALF  = 5;       // 5 ns half period -> 100 MHz
    localparam int TMEM      = 25 + 7*RATIO;

    logic clk = 0, clk_mem = 0, rst = 1;

    // Processor clock
    always #(CPU_HALF) clk = ~clk;

    // Memory clock: first rising edge coincides with a processor rising edge
    // (t = CPU_HALF), then one edge every RATIO processor cycles. This keeps
    // the edges aligned for ANY integer ratio (even or odd).
    initial begin
        #(CPU_HALF);
        forever begin
            clk_mem = 1; #(CPU_HALF*RATIO);
            clk_mem = 0; #(CPU_HALF*RATIO);
        end
    end

    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // DUT
    logic         rd_req = 0, ev_push = 0;
    logic [31:0]  rd_addr = 0, ev_addr = 0;
    logic [255:0] ev_line = 0;
    wire  [255:0] rd_data;
    wire          rd_done, ev_full, ev_empty, idle, timeout_err;

    mem_subsystem #(.EV_DEPTH(4), .FIRST_LAT(FIRST_LAT), .DATA_FILE("data.mem")) dut (
        .clk(clk), .clk_mem(clk_mem), .rst(rst),
        .rd_req(rd_req), .rd_addr(rd_addr), .rd_data(rd_data), .rd_done(rd_done),
        .ev_push(ev_push), .ev_addr(ev_addr), .ev_line(ev_line),
        .ev_full(ev_full), .ev_empty(ev_empty),
        .idle(idle), .timeout_err(timeout_err)
    );

    integer errors = 0;

    // ---------------- helpers ----------------
    function [255:0] make_line(input [15:0] id);
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1)
                make_line[32*k +: 32] = {id, 8'hA5, k[7:0]};
        end
    endfunction

    function [31:0] mw(input [31:0] a);   // word straight from the memory array
        mw = {dut.u_ctrl.memory[a+3], dut.u_ctrl.memory[a+2],
              dut.u_ctrl.memory[a+1], dut.u_ctrl.memory[a]};
    endfunction

    task tick;  begin @(posedge clk); #1; end endtask

    task do_read(input [31:0] a, output integer lat);
        integer t0;
        begin
            rd_addr = a; rd_req = 1; t0 = cyc;
            tick;
            while (!rd_done) tick;
            lat = cyc - t0;
            rd_req = 0;
        end
    endtask

    task wait_idle;
        begin
            tick;
            while (!idle || !ev_empty) tick;
        end
    endtask

    task push(input [31:0] a, input [255:0] l);
        begin
            ev_addr = a; ev_line = l; ev_push = 1;
            tick;
            ev_push = 0;
        end
    endtask

    task check_line_in_mem(input [31:0] a, input [255:0] l);
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1)
                if (mw(a + 4*k) !== l[32*k +: 32]) begin
                    $display("  FAIL: mem[%h] = %h, expected %h", a+4*k, mw(a+4*k), l[32*k +: 32]);
                    errors = errors + 1;
                end
        end
    endtask

    // ---------------- stimulus ----------------
    integer lat, p, lat_min, lat_max;

    initial begin
        #1000000; $display("GLOBAL TIMEOUT"); $finish;
    end

    initial begin
        repeat (4) @(posedge clk);
        rst = 0;
        tick; tick;

        // ---- Test 1: read latency, swept over all RATIO phases ----
        $display("\n[T1] Read latency (spec Tmem = 25 + 7*%0d = %0d proc cycles)", RATIO, TMEM);
        lat_min = 1<<30; lat_max = 0;
        for (p = 0; p < RATIO; p = p + 1) begin
            repeat (p) tick;
            do_read(32'h40, lat);
            $display("  phase %0d: latency = %0d proc cycles", p, lat);
            if (lat < lat_min) lat_min = lat;
            if (lat > lat_max) lat_max = lat;
            if (rd_data[31:0] !== 32'h43424140 || rd_data[255:224] !== 32'h5F5E5D5C) begin
                $display("  FAIL: wrong data %h", rd_data); errors = errors + 1;
            end
            wait_idle;
        end
        $display("  min=%0d max=%0d target=%0d -> adjust FIRST_LAT until it matches", lat_min, lat_max, TMEM);

        // ---- Test 2: reads have priority over buffered evictions ----
        $display("\n[T2] Read priority over eviction drain");
        push(32'h1000, make_line(16'h0001));
        push(32'h1020, make_line(16'h0002));
        push(32'h1040, make_line(16'h0003));
        do_read(32'h80, lat);
        $display("  read finished with %0d entries still in the eviction buffer (expect >= 1)", dut.count);
        if (dut.count < 1) begin $display("  FAIL"); errors = errors + 1; end
        wait_idle;
        check_line_in_mem(32'h1000, make_line(16'h0001));
        check_line_in_mem(32'h1020, make_line(16'h0002));
        check_line_in_mem(32'h1040, make_line(16'h0003));
        $display("  drained lines verified in memory");

        // ---- Test 3: RAW hazard (read of a line still in the buffer) ----
        $display("\n[T3] RAW hazard: read of an address still in the eviction buffer");
        push(32'h2000, make_line(16'h00AA));
        do_read(32'h2000, lat);
        if (rd_data !== make_line(16'h00AA)) begin
            $display("  FAIL: read returned stale data %h", rd_data); errors = errors + 1;
        end else
            $display("  OK: read returned the evicted (new) data after %0d cycles (drain + fill)", lat);
        wait_idle;

        // ---- Test 4: buffer full flag ----
        $display("\n[T4] Buffer full flag");
        push(32'h3000, make_line(16'h0101));
        push(32'h3020, make_line(16'h0102));
        push(32'h3040, make_line(16'h0103));
        push(32'h3060, make_line(16'h0104));
        $display("  ev_full=%b (depends on whether the first entry already started draining)", ev_full);
        wait_idle;

        $display("\ntimeout_err=%b  errors=%0d  -> %s", timeout_err, errors,
                 (errors == 0 && !timeout_err) ? "PASS" : "FAIL");
        $finish;
    end
endmodule
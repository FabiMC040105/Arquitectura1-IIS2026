`timescale 1ns/1ps
// Processor-side wrapper around the main memory:
//   - Eviction buffer: FIFO of dirty lines (addr + 32 bytes) coming from L2.
//   - Arbiter: read fills have priority over buffer drains, EXCEPT when the
//     read address is still in the buffer (RAW hazard -> STALL strategy:
//     keep draining until the matching entry is gone, then do the read).
//   - Clock-domain crossing: req/done are single-bit levels passed through
//     two-flop synchronizers; addr/data buses are held stable while req=1.
//
// Interface rules for the (future) L2:
//   * Read:  hold rd_req=1 with rd_addr stable. rd_done pulses for one cycle
//            with rd_data valid. L2 must drop rd_req in the cycle after rd_done.
//   * Evict: pulse ev_push for one cycle (only when !ev_full).
module mem_subsystem #(
    parameter int EV_DEPTH  = 4,        // 4..16 per spec
    parameter int FIRST_LAT = 3,        // clk_mem cycles (calibrate, see tb)
    parameter int TIMEOUT   = 2000,     // processor cycles
    parameter     DATA_FILE = ""
)(
    input  logic         clk,           // processor clock
    input  logic         clk_mem,       // memory clock
    input  logic         rst,

    // Read (line fill) port
    input  logic         rd_req,
    input  logic [31:0]  rd_addr,
    output logic [255:0] rd_data,
    output logic         rd_done,

    // Eviction buffer port
    input  logic         ev_push,
    input  logic [31:0]  ev_addr,
    input  logic [255:0] ev_line,
    output logic         ev_full,
    output logic         ev_empty,

    output logic         perf_mem_accept_o,
    output logic         perf_mem_write_o,
    output logic         perf_mem_busy_o,
    output logic         perf_mem_word_o,
    output logic         idle,
    output logic         timeout_err
);
    // ------------------------------------------------------------------
    // Eviction FIFO
    // ------------------------------------------------------------------
    logic [31:0]  fifo_addr [0:EV_DEPTH-1];
    logic [255:0] fifo_line [0:EV_DEPTH-1];
    logic [EV_DEPTH-1:0] valid;
    integer wr_ptr, rd_ptr, count;

    assign ev_empty = (count == 0);
    assign ev_full  = (count == EV_DEPTH);

    // RAW hazard: read line address present in the buffer
    logic hazard;
    integer j;
    always_comb begin
        hazard = 1'b0;
        for (j = 0; j < EV_DEPTH; j = j + 1)
            if (valid[j] && (((rd_addr ^ fifo_addr[j]) & 32'hFFFF_FFE0) == 32'd0))
                hazard = 1'b1;
    end

    // ------------------------------------------------------------------
    // Arbiter (processor domain)
    // ------------------------------------------------------------------
    localparam [1:0] A_IDLE = 2'd0, A_BUSY = 2'd1, A_REL = 2'd2;
    logic [1:0]   a_state;
    logic         req_c, we_c, is_rd;
    logic [31:0]  addr_c;
    logic [255:0] wline_c;
    integer       wd;

    logic         done_m, done_sync, req_sync;
    logic [255:0] rline_m;
    logic         access_error;
    wire          word_xfer_mem;
    logic         word_toggle_mem;
    wire          word_toggle_cpu;
    logic         word_toggle_cpu_prev;

    assign idle = (a_state == A_IDLE);

    // Eventos de rendimiento, en reloj de CPU.
    // Una transacción se registra cuando el árbitro
    // comienza a atenderla, no al entrar en un FIFO.
    assign perf_mem_accept_o =
        (a_state == A_IDLE) &&
        ((rd_req && !hazard) || !ev_empty);

    assign perf_mem_write_o =
        (a_state == A_IDLE) &&
        !(rd_req && !hazard) && !ev_empty;

    assign perf_mem_busy_o = (a_state == A_BUSY);

    wire do_push = ev_push && !ev_full;
    wire do_pop  = (a_state == A_BUSY) && done_sync && !is_rd;

    // FIFO storage / pointers
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0; rd_ptr <= 0; count <= 0; valid <= '0;
        end else begin
            if (do_push) begin
                fifo_addr[wr_ptr] <= ev_addr;
                fifo_line[wr_ptr] <= ev_line;
                valid[wr_ptr]     <= 1'b1;
                wr_ptr <= (wr_ptr == EV_DEPTH-1) ? 0 : wr_ptr + 1;
            end
            if (do_pop) begin
                valid[rd_ptr] <= 1'b0;
                rd_ptr <= (rd_ptr == EV_DEPTH-1) ? 0 : rd_ptr + 1;
            end
            count <= count + (do_push ? 1 : 0) - (do_pop ? 1 : 0);
        end
    end

    // Arbiter FSM
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            a_state     <= A_IDLE;
            req_c       <= 1'b0;
            we_c        <= 1'b0;
            is_rd       <= 1'b0;
            addr_c      <= 32'd0;
            wline_c     <= 256'd0;
            rd_done     <= 1'b0;
            rd_data     <= 256'd0;
            wd          <= 0;
            timeout_err <= 1'b0;
        end else begin
            rd_done <= 1'b0;
            case (a_state)
                A_IDLE: begin
                    wd <= 0;
                    if (rd_req && !hazard) begin            // read has priority
                        is_rd  <= 1'b1;
                        we_c   <= 1'b0;
                        addr_c <= rd_addr;
                        req_c  <= 1'b1;
                        a_state <= A_BUSY;
                    end else if (!ev_empty) begin           // drain (also resolves RAW)
                        is_rd   <= 1'b0;
                        we_c    <= 1'b1;
                        addr_c  <= fifo_addr[rd_ptr];
                        wline_c <= fifo_line[rd_ptr];
                        req_c   <= 1'b1;
                        a_state <= A_BUSY;
                    end
                end
                A_BUSY: begin
                    wd <= wd + 1;
                    if (wd > TIMEOUT) timeout_err <= 1'b1;
                    if (done_sync) begin
                        req_c <= 1'b0;
                        if (is_rd) begin
                            rd_data <= rline_m;
                            rd_done <= 1'b1;
                        end
                        a_state <= A_REL;
                    end
                end
                A_REL: begin
                    if (!done_sync) a_state <= A_IDLE;
                end
                default: a_state <= A_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Clock domain crossing + memory
    // ------------------------------------------------------------------
    flop_sync u_sync_req  (.clk_dst(clk_mem), .rst(rst), .d(req_c),  .q(req_sync));
    flop_sync u_sync_done (.clk_dst(clk),     .rst(rst), .d(done_m), .q(done_sync));

    mem_controller #(
        .FIRST_LAT(FIRST_LAT),
        .DATA_FILE(DATA_FILE)
    ) u_ctrl (
        .clk_mem      (clk_mem),
        .rst          (rst),
        .req          (req_sync),
        .we           (we_c),
        .addr         (addr_c),
        .wline        (wline_c),
        .done         (done_m),
        .rline        (rline_m),
        .access_error (access_error),
        .perf_word_xfer_o (word_xfer_mem)
    );

    // Cruce RAM -> CPU: un toggle por palabra transferida.
    // Memoria opera entre 20 y 50 MHz, CPU a 100 MHz.
    always_ff @(posedge clk_mem or posedge rst) begin
        if (rst)
            word_toggle_mem <= 1'b0;
        else if (word_xfer_mem)
            word_toggle_mem <= ~word_toggle_mem;
    end

    flop_sync perf_word_sync (
        .clk_dst(clk),
        .rst(rst),
        .d(word_toggle_mem),
        .q(word_toggle_cpu)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            word_toggle_cpu_prev <= 1'b0;
        else
            word_toggle_cpu_prev <= word_toggle_cpu;
    end

    assign perf_mem_word_o =
        word_toggle_cpu ^ word_toggle_cpu_prev;

endmodule
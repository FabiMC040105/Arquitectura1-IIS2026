`timescale 1ns/1ps
`ifndef DATA_FILE
  `define DATA_FILE "data.mem"
`endif

// Main memory + burst controller. Runs entirely on clk_mem.
//
//  - 64 KB, byte addressable, little-endian words (same layout as data_memory.sv)
//  - Transfers one 32-byte line (8 words) per request, read or write.
//  - Timing (in clk_mem cycles):
//        FIRST_LAT cycles  -> word 0 transferred
//        7 more cycles     -> words 1..7, one word per cycle
//  - Handshake: req (level, already synchronized to clk_mem) -> done (level).
//    done stays high until req is dropped.
//  - we / addr / wline are driven by the cpu domain and are held stable
//    while req is high, so they are NOT synchronized.
module mem_controller #(
    parameter int FIRST_LAT = 3,        // clk_mem cycles for the first word
    parameter int MEM_BYTES = 65536,
    parameter     DATA_FILE = `DATA_FILE
)(
    input  logic         clk_mem,
    input  logic         rst,

    input  logic         req,
    input  logic         we,
    input  logic [31:0]  addr,
    input  logic [255:0] wline,

    output logic         done,
    output logic [255:0] rline,
    output logic         access_error,
    output logic         perf_word_xfer_o
);
    logic [7:0] memory [0:MEM_BYTES-1];

    integer i;
    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1) memory[i] = 8'h00;
        if (DATA_FILE != "") begin
            $display("mem_controller: loading %s", DATA_FILE);
            $readmemh(DATA_FILE, memory);
        end
    end

    // Line-aligned base address (32-byte lines)
    wire [31:0] base = {addr[31:5], 5'b00000};

    // Out of range line -> flagged, no data transferred (timing unchanged)
    assign access_error = req && (base > (MEM_BYTES - 32));

    function [31:0] rd_word(input [31:0] a);
        rd_word = {memory[a+3], memory[a+2], memory[a+1], memory[a]};
    endfunction

    localparam [1:0] S_IDLE = 2'd0, S_FIRST = 2'd1, S_BURST = 2'd2, S_DONE = 2'd3;

    logic [1:0]  state;
    logic [7:0]  cnt;
    logic [2:0]  beat;

    // A word is transferred on the last FIRST cycle (word 0) and on every BURST cycle.
    wire       xfer = ((state == S_FIRST) && (cnt == FIRST_LAT-1)) || (state == S_BURST);
    wire [2:0] k    = (state == S_FIRST) ? 3'd0 : beat;

    assign perf_word_xfer_o = xfer && !access_error;

    // Data path
    always_ff @(posedge clk_mem) begin
        if (xfer && !access_error) begin
            if (we) begin
                memory[base + 4*k + 0] <= wline[32*k      +: 8];
                memory[base + 4*k + 1] <= wline[32*k + 8  +: 8];
                memory[base + 4*k + 2] <= wline[32*k + 16 +: 8];
                memory[base + 4*k + 3] <= wline[32*k + 24 +: 8];
            end else begin
                rline[32*k +: 32] <= rd_word(base + 4*k);
            end
        end
    end

    // Control FSM
    always_ff @(posedge clk_mem or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            cnt   <= 8'd0;
            beat  <= 3'd0;
            done  <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (req) begin
                        cnt   <= 8'd0;
                        state <= S_FIRST;
                    end
                end
                S_FIRST: begin
                    if (cnt == FIRST_LAT-1) begin
                        beat  <= 3'd1;
                        state <= S_BURST;
                    end else begin
                        cnt <= cnt + 8'd1;
                    end
                end
                S_BURST: begin
                    if (beat == 3'd7) begin
                        state <= S_DONE;
                        done  <= 1'b1;
                    end else begin
                        beat <= beat + 3'd1;
                    end
                end
                S_DONE: begin
                    if (!req) begin
                        state <= S_IDLE;
                        done  <= 1'b0;
                    end
                end
            endcase
        end
    end
endmodule
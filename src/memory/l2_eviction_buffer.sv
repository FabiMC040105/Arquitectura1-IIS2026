`timescale 1ns/1ps
module l2_eviction_buffer #(
    parameter integer DEPTH = 8
)(
    input logic clk,
    input logic rst,
    input  logic         evict_valid,
    output logic         evict_ready,
    input  logic [31:0]  evict_addr,
    input  logic [255:0] evict_data,
    output logic         wb_valid,
    output logic [31:0]  wb_addr,
    output logic [255:0] wb_data,
    input logic write_complete,
    input  logic [31:0] check_addr,
    output logic        raw_conflict,
    output logic full,
    output logic empty,
    output logic [$clog2(DEPTH+1)-1:0] count
);
    localparam integer PTR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;
    logic [31:0] addr_fifo [0:DEPTH-1];
    logic [255:0] data_fifo [0:DEPTH-1];
    logic [PTR_W-1:0] wr_ptr, rd_ptr;
    logic do_push, do_pop;

    assign full  = (count == DEPTH);
    assign empty = (count == 0);
    assign do_pop = write_complete && !empty;
    assign evict_ready = !full || do_pop;
    assign do_push = evict_valid && evict_ready;

    always @(*) begin
        wb_valid = !empty;
        wb_addr = 32'b0;
        wb_data = 256'b0;
        if (!empty) begin
            wb_addr = addr_fifo[rd_ptr];
            wb_data = data_fifo[rd_ptr];
        end
    end

    integer idx;
    always @(*) begin
        raw_conflict = 1'b0;
        idx = 0;
        for (integer i = 0; i < DEPTH; i = i + 1) begin
            idx = rd_ptr + i;
            if (idx >= DEPTH)
                idx = idx - DEPTH;
            if (i < count) begin
                if (addr_fifo[idx][31:5] == check_addr[31:5])
                    raw_conflict = 1'b1;
            end
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count <= '0;
        end else begin
            if (do_push) begin
                addr_fifo[wr_ptr] <= evict_addr;
                data_fifo[wr_ptr] <= evict_data;
                if (wr_ptr == DEPTH-1) wr_ptr <= '0;
                else wr_ptr <= wr_ptr + 1'b1;
            end
            if (do_pop) begin
                if (rd_ptr == DEPTH-1) rd_ptr <= '0;
                else rd_ptr <= rd_ptr + 1'b1;
            end
            case ({do_push,do_pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule

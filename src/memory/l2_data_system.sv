`timescale 1ns/1ps

// Integracion L2 + eviction buffer. Una sola transaccion de memoria activa.
// La memoria externa debe responder con mem_resp_valid tambien para escrituras.
module l2_data_system (
    input  logic         clk,
    input  logic         rst,
    input  logic         l2_req_valid,
    output logic         l2_req_ready,
    input  logic [31:0]  l2_req_addr,
    output logic         l2_resp_valid,
    output logic [255:0] l2_resp_data,
    input  logic         l2_write_valid,
    output logic         l2_write_ready,
    input  logic [31:0]  l2_write_addr,
    input  logic [31:0]  l2_write_data,

    // Puerto unico hacia controlador de memoria (persona 4).
    output logic         mem_req_valid,
    input  logic         mem_req_ready,
    output logic         mem_req_write,
    output logic [31:0]  mem_req_addr,
    output logic [255:0] mem_req_wdata,
    input  logic         mem_resp_valid,
    input  logic [255:0] mem_resp_data,

    output logic [31:0]  read_hits,
    output logic [31:0]  read_misses,
    output logic [31:0]  write_hits,
    output logic [31:0]  write_misses,
    output logic [3:0]   eviction_count
);
    logic         fill_req_valid, fill_req_ready;
    logic [31:0]  fill_req_addr;
    logic         fill_resp_valid;
    logic [255:0] fill_resp_data;

    logic         evict_valid, evict_ready;
    logic [31:0]  evict_addr;
    logic [255:0] evict_data;
    logic         wb_valid, wb_complete;
    logic [31:0]  wb_addr;
    logic [255:0] wb_data;
    logic         raw_conflict;
    logic         fifo_full, fifo_empty;

    l2_controller controller (
        .clk(clk), .rst(rst),
        .l2_req_valid(l2_req_valid),
        .l2_req_ready(l2_req_ready),
        .l2_req_addr(l2_req_addr),
        .l2_resp_valid(l2_resp_valid),
        .l2_resp_data(l2_resp_data),
        .l2_write_valid(l2_write_valid),
        .l2_write_ready(l2_write_ready),
        .l2_write_addr(l2_write_addr),
        .l2_write_data(l2_write_data),
        .mem_req_valid(fill_req_valid),
        .mem_req_ready(fill_req_ready),
        .mem_req_addr(fill_req_addr),
        .mem_resp_valid(fill_resp_valid),
        .mem_resp_data(fill_resp_data),
        .evict_valid(evict_valid),
        .evict_ready(evict_ready),
        .evict_addr(evict_addr),
        .evict_data(evict_data),
        .read_hits(read_hits),
        .read_misses(read_misses),
        .write_hits(write_hits),
        .write_misses(write_misses)
    );

    // Estrategia RAW: stall. Si un refill apunta a una linea que esta
    // en la FIFO, esperar a que se escriba antes de leerla de RAM.
    l2_eviction_buffer #(.DEPTH(8)) eviction_fifo (
        .clk(clk), .rst(rst),
        .evict_valid(evict_valid),
        .evict_ready(evict_ready),
        .evict_addr(evict_addr),
        .evict_data(evict_data),
        .wb_valid(wb_valid),
        .wb_addr(wb_addr),
        .wb_data(wb_data),
        .write_complete(wb_complete),
        .check_addr(fill_req_addr),
        .raw_conflict(raw_conflict),
        .full(fifo_full),
        .empty(fifo_empty),
        .count(eviction_count)
    );

    localparam [1:0] MEM_IDLE  = 2'd0;
    localparam [1:0] MEM_READ  = 2'd1;
    localparam [1:0] MEM_WRITE = 2'd2;
    logic [1:0] mem_state;

    // Las escrituras de la FIFO tienen prioridad. Se transfieren siempre
    // lineas completas de 256 bits (32 bytes alineados).
    always @(*) begin
        mem_req_valid = 1'b0;
        mem_req_write = 1'b0;
        mem_req_addr  = 32'b0;
        mem_req_wdata = 256'b0;
        fill_req_ready = 1'b0;

        if (!rst && mem_state == MEM_IDLE) begin
            if (wb_valid) begin
                mem_req_valid = 1'b1;
                mem_req_write = 1'b1;
                mem_req_addr = wb_addr;
                mem_req_wdata = wb_data;
            end else if (fill_req_valid && !raw_conflict) begin
                mem_req_valid = 1'b1;
                mem_req_write = 1'b0;
                mem_req_addr = fill_req_addr;
                fill_req_ready = mem_req_ready;
            end
        end
    end

    // La respuesta de escritura debe indicar FINALIZACION, no solo aceptacion.
    assign wb_complete = (mem_state == MEM_WRITE) && mem_resp_valid;
    assign fill_resp_valid = (mem_state == MEM_READ) && mem_resp_valid;
    assign fill_resp_data = mem_resp_data;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_state <= MEM_IDLE;
        end else begin
            case (mem_state)
                MEM_IDLE: begin
                    if (mem_req_valid && mem_req_ready)
                        mem_state <= mem_req_write ? MEM_WRITE : MEM_READ;
                end
                MEM_READ: begin
                    if (mem_resp_valid) mem_state <= MEM_IDLE;
                end
                MEM_WRITE: begin
                    if (mem_resp_valid) mem_state <= MEM_IDLE;
                end
                default: mem_state <= MEM_IDLE;
            endcase
        end
    end
endmodule

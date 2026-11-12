`timescale 1ns/1ps

module l2_controller (
    input  logic         clk,
    input  logic         rst,

    // Lecturas desde L1 (lineas de 256 bits).
    input  logic         l2_req_valid,
    output logic         l2_req_ready,
    input  logic [31:0]  l2_req_addr,
    output logic         l2_resp_valid,
    output logic [255:0] l2_resp_data,

    // Escrituras desde L1 (palabras de 32 bits).
    input  logic         l2_write_valid,
    output logic         l2_write_ready,
    input  logic [31:0]  l2_write_addr,
    input  logic [31:0]  l2_write_data,

    // Lectura de linea desde memoria principal.
    output logic         mem_req_valid,
    input  logic         mem_req_ready,
    output logic [31:0]  mem_req_addr,
    input  logic         mem_resp_valid,
    input  logic [255:0] mem_resp_data,

    // Insercion de victima dirty en eviction buffer.
    output logic         evict_valid,
    input  logic         evict_ready,
    output logic [31:0]  evict_addr,
    output logic [255:0] evict_data,

    // Contadores, sin modificar el ISA.
    output logic [31:0] read_hits,
    output logic [31:0] read_misses,
    output logic [31:0] write_hits,
    output logic [31:0] write_misses
);
    typedef enum logic [3:0] {
        IDLE, CHECK, L2_WAIT, HIT_RESPONSE, HIT_WRITE,
        MISS_PREPARE, EVICT, MEM_REQUEST, MEM_WAIT,
        FILL, POST_FILL_READ, POST_FILL_WRITE
    } state_t;

    state_t state;
    logic         pending_write;
    logic [31:0]  pending_addr;
    logic [31:0]  pending_data;
    logic         pending_hit;
    logic [2:0]   wait_counter;
    logic [255:0] fetched_line;

    logic         cache_hit;
    logic [255:0] cache_data;
    logic         cache_write;
    logic         cache_fill;

    logic [1:0]   candidate_way;
    logic         victim_valid;
    logic         victim_dirty;
    logic [31:0]  victim_addr;
    logic [255:0] victim_data;

    // Informacion congelada durante todo el miss.
    logic [1:0]   locked_way;
    logic [31:0]  locked_victim_addr;
    logic [255:0] locked_victim_data;

    cache_l2 cache_inst (
        .clk(clk), .rst(rst),
        .lookup_addr(pending_addr),
        .lookup_hit(cache_hit),
        .lookup_data(cache_data),
        .write_valid(cache_write),
        .write_addr(pending_addr),
        .write_data(pending_data),
        .fill_valid(cache_fill),
        .fill_addr(pending_addr),
        .fill_data(fetched_line),
        .fill_way_i(locked_way),
        .candidate_way(candidate_way),
        .victim_valid(victim_valid),
        .victim_dirty(victim_dirty),
        .victim_addr(victim_addr),
        .victim_data(victim_data)
    );

    assign cache_write = (state == HIT_WRITE) ||
                         (state == POST_FILL_WRITE);
    assign cache_fill = (state == FILL);

    // Prioridad a lecturas de L1 cuando ambas solicitudes llegan juntas.
    assign l2_req_ready = !rst && (state == IDLE);
    assign l2_write_ready = !rst && (state == IDLE) && !l2_req_valid;

    assign mem_req_valid = (state == MEM_REQUEST);
    assign mem_req_addr = {pending_addr[31:5], 5'b0};

    // No usar las salidas combinacionales de cache_l2 mientras
    // el eviction buffer esta esperando espacio: estan congeladas.
    assign evict_valid = (state == EVICT);
    assign evict_addr = locked_victim_addr;
    assign evict_data = locked_victim_data;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            pending_write <= 1'b0;
            pending_addr <= 32'b0;
            pending_data <= 32'b0;
            pending_hit <= 1'b0;
            wait_counter <= 3'b0;
            fetched_line <= 256'b0;
            locked_way <= 2'b0;
            locked_victim_addr <= 32'b0;
            locked_victim_data <= 256'b0;
            l2_resp_valid <= 1'b0;
            l2_resp_data <= 256'b0;
            read_hits <= 32'b0;
            read_misses <= 32'b0;
            write_hits <= 32'b0;
            write_misses <= 32'b0;
        end else begin
            l2_resp_valid <= 1'b0;
            case (state)
                IDLE: begin
                    if (l2_req_valid && l2_req_ready) begin
                        pending_write <= 1'b0;
                        pending_addr <= l2_req_addr;
                        pending_data <= 32'b0;
                        state <= CHECK;
                    end else if (l2_write_valid && l2_write_ready) begin
                        pending_write <= 1'b1;
                        pending_addr <= l2_write_addr;
                        pending_data <= l2_write_data;
                        state <= CHECK;
                    end
                end
                CHECK: begin
                    pending_hit <= cache_hit;
                    if (pending_write) begin
                        if (cache_hit) write_hits <= write_hits + 1'b1;
                        else           write_misses <= write_misses + 1'b1;
                    end else begin
                        if (cache_hit) read_hits <= read_hits + 1'b1;
                        else           read_misses <= read_misses + 1'b1;
                    end
                    // Desde el handshake hasta resp_valid de un read hit:
                    // 8 ciclos de CPU (CHECK + espera + HIT_RESPONSE).
                    wait_counter <= 3'd5;
                    state <= L2_WAIT;
                end
                L2_WAIT: begin
                    if (wait_counter != 0)
                        wait_counter <= wait_counter - 1'b1;
                    else if (pending_hit)
                        state <= pending_write ? HIT_WRITE : HIT_RESPONSE;
                    else
                        state <= MISS_PREPARE;
                end
                HIT_RESPONSE: begin
                    l2_resp_data <= cache_data;
                    l2_resp_valid <= 1'b1;
                    state <= IDLE;
                end
                HIT_WRITE: begin
                    // cache_write esta activo en este flanco.
                    state <= IDLE;
                end
                MISS_PREPARE: begin
                    // Una sola captura del numero de via y la victima.
                    locked_way <= candidate_way;
                    locked_victim_addr <= victim_addr;
                    locked_victim_data <= victim_data;
                    state <= (victim_valid && victim_dirty) ? EVICT : MEM_REQUEST;
                end
                EVICT: begin
                    // No reemplace hasta que la FIFO acepte la linea dirty.
                    if (evict_ready)
                        state <= MEM_REQUEST;
                end
                MEM_REQUEST: begin
                    if (mem_req_ready)
                        state <= MEM_WAIT;
                end
                MEM_WAIT: begin
                    if (mem_resp_valid) begin
                        fetched_line <= mem_resp_data;
                        state <= FILL;
                    end
                end
                FILL: begin
                    // cache_fill instala la nueva linea en locked_way.
                    state <= pending_write ? POST_FILL_WRITE : POST_FILL_READ;
                end
                POST_FILL_READ: begin
                    l2_resp_data <= fetched_line;
                    l2_resp_valid <= 1'b1;
                    state <= IDLE;
                end
                POST_FILL_WRITE: begin
                    // cache_write escribe la palabra y marca dirty.
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule

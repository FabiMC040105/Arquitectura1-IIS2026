`timescale 1ns/1ps

module cache_l2 (
    input  logic         clk,
    input  logic         rst,

    // Consulta combinacional (una linea completa).
    input  logic [31:0]  lookup_addr,
    output logic         lookup_hit,
    output logic [255:0] lookup_data,

    // Escritura de una palabra en una linea existente.
    input  logic         write_valid,
    input  logic [31:0]  write_addr,
    input  logic [31:0]  write_data,

    // Refill: la via es elegida y congelada por el controlador.
    input  logic         fill_valid,
    input  logic [31:0]  fill_addr,
    input  logic [255:0] fill_data,
    input  logic [1:0]   fill_way_i,

    // Propuesta combinacional de victima (antes de congelarla).
    output logic [1:0]   candidate_way,
    output logic         victim_valid,
    output logic         victim_dirty,
    output logic [31:0]  victim_addr,
    output logic [255:0] victim_data
);
    localparam integer NUM_SETS = 128;
    localparam integer NUM_WAYS = 4;

    logic [255:0] data_array  [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic [19:0]  tag_array   [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic         valid_array [0:NUM_SETS-1][0:NUM_WAYS-1];
    logic         dirty_array [0:NUM_SETS-1][0:NUM_WAYS-1];

    logic [15:0] lfsr;

    wire [6:0]  lookup_set = lookup_addr[11:5];
    wire [19:0] lookup_tag = lookup_addr[31:12];
    wire [6:0]  write_set  = write_addr[11:5];
    wire [19:0] write_tag  = write_addr[31:12];
    wire [6:0]  fill_set   = fill_addr[11:5];
    wire [19:0] fill_tag   = fill_addr[31:12];

    logic       write_hit;
    logic [1:0] write_way;
    logic       found_free;

    integer s, w;

    // La consulta no modifica el contenido de L2.
    always @(*) begin
        lookup_hit  = 1'b0;
        lookup_data = 256'b0;
        for (integer k = 0; k < NUM_WAYS; k = k + 1) begin
            if (valid_array[lookup_set][k] &&
                tag_array[lookup_set][k] == lookup_tag) begin
                lookup_hit  = 1'b1;
                lookup_data = data_array[lookup_set][k];
            end
        end
    end

    // Buscar la via que contiene la palabra a modificar.
    always @(*) begin
        write_hit = 1'b0;
        write_way = 2'b00;
        for (integer k = 0; k < NUM_WAYS; k = k + 1) begin
            if (valid_array[write_set][k] &&
                tag_array[write_set][k] == write_tag) begin
                write_hit = 1'b1;
                write_way = k[1:0];
            end
        end
    end

    // Primero una via invalida; si no hay, replacement Random.
    // Mientras no se haga refill, lfsr no cambia.
    always @(*) begin
        candidate_way = lfsr[1:0];
        found_free = 1'b0;
        for (integer k = 0; k < NUM_WAYS; k = k + 1) begin
            if (!found_free && !valid_array[fill_set][k]) begin
                candidate_way = k[1:0];
                found_free = 1'b1;
            end
        end
    end

    // Estos datos pertenecen SIEMPRE a candidate_way.
    // El controlador debe capturarlos junto con candidate_way.
    always @(*) begin
        victim_valid = valid_array[fill_set][candidate_way];
        victim_dirty = victim_valid && dirty_array[fill_set][candidate_way];
        victim_addr  = {tag_array[fill_set][candidate_way], fill_set, 5'b0};
        victim_data  = data_array[fill_set][candidate_way];
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lfsr <= 16'hACE1;
            for (s = 0; s < NUM_SETS; s = s + 1) begin
                for (w = 0; w < NUM_WAYS; w = w + 1) begin
                    data_array[s][w]  <= 256'b0;
                    tag_array[s][w]   <= 20'b0;
                    valid_array[s][w] <= 1'b0;
                    dirty_array[s][w] <= 1'b0;
                end
            end
        end else begin
            // No se permite fill + write simultaneos.
            // El controlador garantiza que solo uno este activo.
            if (fill_valid) begin
                data_array[fill_set][fill_way_i]  <= fill_data;
                tag_array[fill_set][fill_way_i]   <= fill_tag;
                valid_array[fill_set][fill_way_i] <= 1'b1;
                dirty_array[fill_set][fill_way_i] <= 1'b0;
                lfsr <= {lfsr[14:0],
                         lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
            end else if (write_valid && write_hit &&
                         write_addr[1:0] == 2'b00) begin
                data_array[write_set][write_way][write_addr[4:2]*32 +: 32]
                    <= write_data;
                dirty_array[write_set][write_way] <= 1'b1;
            end
        end
    end
endmodule

`timescale 1ns/1ps

module performance_counters (
    input  logic clk_i,
    input  logic rst_i,
    input  logic measure_i,

    // Eventos del pipeline. Los cuatro bits indican slots no NOP en WB.
    input  logic retire_valid_i,
    input  logic [3:0] retire_slots_i,
    input  logic pipeline_stall_i,
    input  logic cache_stall_i,
    input  logic branch_stall_i,
    input  logic stall_l2_lookup_i,
    input  logic stall_memory_i,
    input  logic stall_buffer_i,

    // L1: un pulso por solicitud original, antes de cualquier refill.
    input  logic l1_access_i,
    input  logic l1_write_i,
    input  logic l1_hit_i,

    // Memoria: eventos expresados en el dominio del reloj del procesador.
    input  logic mem_accept_i,
    input  logic mem_write_i,
    input  logic mem_busy_i,
    input  logic mem_word_i,

    output logic [63:0] cycles_o,
    output logic [63:0] bundles_o,
    output logic [63:0] instructions_o,
    output logic [63:0] cache_stall_cycles_o,
    output logic [63:0] branch_stall_cycles_o,
    output logic [63:0] l2_lookup_stall_cycles_o,
    output logic [63:0] memory_stall_cycles_o,
    output logic [63:0] buffer_stall_cycles_o,
    output logic [63:0] l1_read_hits_o,
    output logic [63:0] l1_read_misses_o,
    output logic [63:0] l1_write_hits_o,
    output logic [63:0] l1_write_misses_o,
    output logic [63:0] mem_reads_o,
    output logic [63:0] mem_writes_o,
    output logic [63:0] mem_busy_cycles_o,
    output logic [63:0] mem_words_o
);

    // Cada slot representa una instruccion, no una escritura a registros.
    wire [2:0] active_slots = {2'b0, retire_slots_i[0]} +
                              {2'b0, retire_slots_i[1]} +
                              {2'b0, retire_slots_i[2]} +
                              {2'b0, retire_slots_i[3]};

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            cycles_o                 <= 0;
            bundles_o                <= 0;
            instructions_o           <= 0;
            cache_stall_cycles_o     <= 0;
            branch_stall_cycles_o    <= 0;
            l2_lookup_stall_cycles_o <= 0;
            memory_stall_cycles_o    <= 0;
            buffer_stall_cycles_o    <= 0;
            l1_read_hits_o           <= 0;
            l1_read_misses_o         <= 0;
            l1_write_hits_o          <= 0;
            l1_write_misses_o        <= 0;
            mem_reads_o              <= 0;
            mem_writes_o             <= 0;
            mem_busy_cycles_o       <= 0;
            mem_words_o              <= 0;
        end else if (measure_i) begin
            // El reloj sigue corriendo aunque el pipeline este detenido.
            cycles_o <= cycles_o + 1;

            // Un bundle congelado en WB no se vuelve a contar.
            if (retire_valid_i && !pipeline_stall_i) begin
                bundles_o      <= bundles_o + 1;
                instructions_o <= instructions_o + active_slots;
            end

            if (cache_stall_i) begin
                cache_stall_cycles_o <= cache_stall_cycles_o + 1;

                // Las fases deben ser excluyentes al conectar el controlador.
                if (stall_buffer_i)
                    buffer_stall_cycles_o <= buffer_stall_cycles_o + 1;
                else if (stall_memory_i)
                    memory_stall_cycles_o <= memory_stall_cycles_o + 1;
                else if (stall_l2_lookup_i)
                    l2_lookup_stall_cycles_o <= l2_lookup_stall_cycles_o + 1;
            end else if (branch_stall_i && !pipeline_stall_i) begin
                // No contamos una penalidad de salto encima de un stall de cache.
                branch_stall_cycles_o <= branch_stall_cycles_o + 1;
            end

            // Separamos lecturas y escrituras para obtener sus tasas por aparte.
            if (l1_access_i) begin
                if (l1_write_i) begin
                    if (l1_hit_i)
                        l1_write_hits_o <= l1_write_hits_o + 1;
                    else
                        l1_write_misses_o <= l1_write_misses_o + 1;
                end else begin
                    if (l1_hit_i)
                        l1_read_hits_o <= l1_read_hits_o + 1;
                    else
                        l1_read_misses_o <= l1_read_misses_o + 1;
                end
            end

            // Una transaccion de memoria se cuenta al aceptar la solicitud.
            if (mem_accept_i) begin
                if (mem_write_i)
                    mem_writes_o <= mem_writes_o + 1;
                else
                    mem_reads_o <= mem_reads_o + 1;
            end

            if (mem_busy_i)
                mem_busy_cycles_o <= mem_busy_cycles_o + 1;

            if (mem_word_i)
                mem_words_o <= mem_words_o + 1;
        end
    end
endmodule

`timescale 1ns/1ps

module tb_performance;
    logic clk = 0;
    always #5 clk = ~clk;

    logic rst, measure, retire_valid, pipeline_stall, cache_stall;
    logic branch_stall, stall_l2_lookup, stall_memory, stall_buffer;
    logic [3:0] retire_slots;
    logic l1_access, l1_write, l1_hit;
    logic mem_accept, mem_write, mem_busy, mem_word;

    wire [63:0] cycles, bundles, instructions, cache_cycles, branch_cycles;
    wire [63:0] lookup_cycles, memory_cycles, buffer_cycles;
    wire [63:0] l1_rh, l1_rm, l1_wh, l1_wm;
    wire [63:0] mem_reads, mem_writes, mem_busy_cycles, mem_words;

    performance_counters dut (
        .clk_i(clk), .rst_i(rst), .measure_i(measure),
        .retire_valid_i(retire_valid), .retire_slots_i(retire_slots),
        .pipeline_stall_i(pipeline_stall), .cache_stall_i(cache_stall),
        .branch_stall_i(branch_stall), .stall_l2_lookup_i(stall_l2_lookup),
        .stall_memory_i(stall_memory), .stall_buffer_i(stall_buffer),
        .l1_access_i(l1_access), .l1_write_i(l1_write), .l1_hit_i(l1_hit),
        .mem_accept_i(mem_accept), .mem_write_i(mem_write),
        .mem_busy_i(mem_busy), .mem_word_i(mem_word),
        .cycles_o(cycles), .bundles_o(bundles), .instructions_o(instructions),
        .cache_stall_cycles_o(cache_cycles), .branch_stall_cycles_o(branch_cycles),
        .l2_lookup_stall_cycles_o(lookup_cycles),
        .memory_stall_cycles_o(memory_cycles), .buffer_stall_cycles_o(buffer_cycles),
        .l1_read_hits_o(l1_rh), .l1_read_misses_o(l1_rm),
        .l1_write_hits_o(l1_wh), .l1_write_misses_o(l1_wm),
        .mem_reads_o(mem_reads), .mem_writes_o(mem_writes),
        .mem_busy_cycles_o(mem_busy_cycles), .mem_words_o(mem_words)
    );

    // Dejamos las entradas en cero antes de preparar el siguiente ciclo.
    task automatic clear_events;
        begin
            retire_valid = 0; retire_slots = 0;
            pipeline_stall = 0; cache_stall = 0; branch_stall = 0;
            stall_l2_lookup = 0; stall_memory = 0; stall_buffer = 0;
            l1_access = 0; l1_write = 0; l1_hit = 0;
            mem_accept = 0; mem_write = 0; mem_busy = 0; mem_word = 0;
        end
    endtask

    task automatic tick;
        begin
            @(posedge clk);
            #1; // Esperamos a que se actualicen los registros.
        end
    endtask

    task automatic check_value(input string name,
                               input logic [63:0] actual,
                               input logic [63:0] expected);
        begin
            if (actual !== expected)
                $fatal(1, "%s: esperado %0d, obtenido %0d", name, expected, actual);
            $display("PASS: %s = %0d", name, actual);
        end
    endtask

    initial begin
        rst = 1; measure = 0; clear_events();
        tick(); rst = 0;
        measure = 1;

        // 1. Bundle con tres instrucciones y un hit de lectura.
        retire_valid = 1; retire_slots = 4'b1011;
        l1_access = 1; l1_hit = 1; tick(); clear_events();

        // 2. Miss de L1. El bundle sigue en WB, pero no termina otra vez.
        retire_valid = 1; retire_slots = 4'b1011;
        pipeline_stall = 1; cache_stall = 1; stall_l2_lookup = 1;
        l1_access = 1; tick(); clear_events();

        // 3 y 4. Espera por memoria. Solo se acepta una solicitud.
        pipeline_stall = 1; cache_stall = 1; stall_memory = 1;
        mem_accept = 1; mem_busy = 1; tick();
        mem_accept = 0; mem_word = 1; tick(); clear_events();

        // 5. Se reanuda el pipeline. Un store puede fallar en L1.
        retire_valid = 1; retire_slots = 4'b0100;
        l1_access = 1; l1_write = 1; tick(); clear_events();

        // 6. Bundle valido con solo NOPs y penalidad de un salto.
        retire_valid = 1; branch_stall = 1;
        l1_access = 1; l1_write = 1; l1_hit = 1; tick(); clear_events();

        // 7. Espera por buffer lleno.
        pipeline_stall = 1; cache_stall = 1; stall_buffer = 1;
        tick(); clear_events();

        // 8. Escritura a memoria en segundo plano, sin detener el pipeline.
        mem_accept = 1; mem_write = 1; mem_busy = 1; mem_word = 1;
        tick(); clear_events();

        // Fuera de la ventana de medicion no debe aumentar ningun contador.
        measure = 0; retire_valid = 1; retire_slots = 4'b1111;
        l1_access = 1; mem_accept = 1; cache_stall = 1; tick();
        clear_events();

        check_value("Ciclos", cycles, 8);
        check_value("Bundles", bundles, 3);
        check_value("Instrucciones", instructions, 4);
        check_value("Stalls cache", cache_cycles, 4);
        check_value("Stalls salto", branch_cycles, 1);
        check_value("Stalls consulta L2", lookup_cycles, 1);
        check_value("Stalls memoria", memory_cycles, 2);
        check_value("Stalls buffer", buffer_cycles, 1);
        check_value("L1 read hits", l1_rh, 1);
        check_value("L1 read misses", l1_rm, 1);
        check_value("L1 write hits", l1_wh, 1);
        check_value("L1 write misses", l1_wm, 1);
        check_value("Memoria lecturas", mem_reads, 1);
        check_value("Memoria escrituras", mem_writes, 1);
        check_value("Memoria ciclos ocupada", mem_busy_cycles, 3);
        check_value("Memoria palabras", mem_words, 2);

        rst = 1; tick(); rst = 0;
        check_value("Reset ciclos", cycles, 0);
        check_value("Reset instrucciones", instructions, 0);
        check_value("Reset accesos L1", l1_rh + l1_rm + l1_wh + l1_wm, 0);
        check_value("Reset memoria", mem_reads + mem_writes + mem_words, 0);

        $display("OK: todas las pruebas de contadores pasaron");
        $finish;
    end
endmodule

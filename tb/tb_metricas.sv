
`timescale 1ns/1ps

module tb_metricas;
    logic clk_i = 0;
    logic clk_mem_i = 0;
    logic rst_i = 1;

    always #5 clk_i = ~clk_i;
    always #20 clk_mem_i = ~clk_mem_i;

    wire [63:0] cycles, instructions;
    wire [63:0] cache_stall_cycles;
    wire [63:0] mem_reads, mem_words;
    wire [63:0] l2_misses;

    top #(
        .PROGRAM_FILE("tb/datos_metricas/programa_metricas.mem"),
        .DATA_FILE("tb/datos_metricas/memoria_metricas.mem")
    ) dut (
        .clk_i(clk_i),
        .clk_mem_i(clk_mem_i),
        .rst_i(rst_i),
        .stall_i(1'b0),
        .perf_cycles_o(cycles),
        .perf_cache_stall_cycles_o(cache_stall_cycles),
        .perf_instructions_o(instructions),
        .perf_mem_reads_o(mem_reads),
        .perf_mem_words_o(mem_words),
        .perf_l2_read_misses_o(l2_misses)
    );

    integer k;

    initial begin
        repeat (4) @(negedge clk_i);
        rst_i = 0;

        for (k = 0; k < 2000; k = k + 1) begin
            @(negedge clk_i);

            if (dut.regfile_inst.regs[3] === 32'h11223344
                && instructions >= 2) begin

                $display("=== RENDIMIENTO TOP ===");
                $display("Ciclos=%0d", cycles);
                $display("Stalls cache=%0d", cache_stall_cycles);
                $display("Instrucciones=%0d", instructions);
                $display("x2=%h", dut.regfile_inst.regs[2]);
                $display("x3=%h", dut.regfile_inst.regs[3]);
                $display("L1 misses=%0d",
                    dut.performance_counters_inst.l1_read_misses_o);
                $display("L2 misses=%0d", l2_misses);
                $display("RAM lecturas=%0d", mem_reads);
                $display("RAM palabras=%0d", mem_words);

                if (dut.regfile_inst.regs[2] !== 32'd9 ||
                    dut.performance_counters_inst.l1_read_misses_o !== 64'd1 ||
                    l2_misses !== 64'd1 ||
                    mem_reads !== 64'd1 ||
                    mem_words !== 64'd8)
                    $fatal(1, "ERROR: integracion de rendimiento");

                if (cache_stall_cycles == 0 ||
                    cache_stall_cycles > cycles)
                    $fatal(1, "ERROR: conteo de stalls invalido");


                $display("=== FASES DE STALL ===");

                for (integer j = 0; j < 12; j = j + 1)
                    if (l2_phase_cycles[j] > 0)
                        $display("L2 estado %0d: %0d ciclos",
                                 j, l2_phase_cycles[j]);

                $display("RAM ocupada durante stall: %0d",
                         ram_busy_during_stall);

                $display("Buffer L2 bloqueado: %0d",
                         buffer_block_cycles);


                $display("=== CONTADORES DETALLADOS ===");
                $display("L2 lookup=%0d",
                    dut.perf_l2_lookup_stall_cycles_o);
                $display("Memoria wait=%0d",
                    dut.perf_memory_stall_cycles_o);
                $display("Buffer wait=%0d",
                    dut.perf_buffer_stall_cycles_o);

                if (dut.perf_l2_lookup_stall_cycles_o !== 64'd7 ||
                    dut.perf_memory_stall_cycles_o !== 64'd56 ||
                    dut.perf_buffer_stall_cycles_o !== 64'd0)
                    $fatal(1, "ERROR: fases de stall incorrectas");

                $display("PASS: contadores detallados de stalls");
                $display("PASS: CPU + L1 + L2 + RAM + contadores");
                begin : guardar_metricas
                    integer archivo;
                    archivo = $fopen("build/benchmarks/metricas_prueba.csv", "w");
                    if (archivo == 0) $fatal(1, "No se pudo crear CSV");
                    $fdisplay(archivo, "benchmark,configuration,status,memory_mhz,cycles,bundles,instructions,cache_stall_cycles,branch_stall_cycles,l2_lookup_stall_cycles,memory_stall_cycles,buffer_stall_cycles,l1_read_hits,l1_read_misses,l1_write_hits,l1_write_misses,l2_read_hits,l2_read_misses,l2_write_hits,l2_write_misses,mem_reads,mem_writes,mem_busy_cycles,mem_words");
                    $fwrite(archivo, "prueba_load,l1_l2_ram,PASS,25");
                    $fwrite(archivo, ",%0d", cycles);
                    $fwrite(archivo, ",%0d", dut.perf_bundles_o);
                    $fwrite(archivo, ",%0d", instructions);
                    $fwrite(archivo, ",%0d", cache_stall_cycles);
                    $fwrite(archivo, ",%0d", dut.performance_counters_inst.branch_stall_cycles_o);
                    $fwrite(archivo, ",%0d", dut.perf_l2_lookup_stall_cycles_o);
                    $fwrite(archivo, ",%0d", dut.perf_memory_stall_cycles_o);
                    $fwrite(archivo, ",%0d", dut.perf_buffer_stall_cycles_o);
                    $fwrite(archivo, ",%0d", dut.performance_counters_inst.l1_read_hits_o);
                    $fwrite(archivo, ",%0d", dut.performance_counters_inst.l1_read_misses_o);
                    $fwrite(archivo, ",%0d", dut.performance_counters_inst.l1_write_hits_o);
                    $fwrite(archivo, ",%0d", dut.performance_counters_inst.l1_write_misses_o);
                    $fwrite(archivo, ",%0d", dut.perf_l2_read_hits_o);
                    $fwrite(archivo, ",%0d", dut.perf_l2_read_misses_o);
                    $fwrite(archivo, ",%0d", dut.perf_l2_write_hits_o);
                    $fwrite(archivo, ",%0d", dut.perf_l2_write_misses_o);
                    $fwrite(archivo, ",%0d", mem_reads);
                    $fwrite(archivo, ",%0d", dut.perf_mem_writes_o);
                    $fwrite(archivo, ",%0d", dut.perf_mem_busy_cycles_o);
                    $fwrite(archivo, ",%0d", mem_words);
                    $fwrite(archivo, "\n");
                    $fclose(archivo);
                    $display("CSV de metricas generado correctamente");
                end

                $finish;
            end
        end

        $fatal(1, "ERROR: timeout del programa minimo");
    end

    integer l2_phase_cycles [0:11];
    integer ram_busy_during_stall = 0;
    integer buffer_block_cycles = 0;
    integer diag_i;

    initial begin
        for (diag_i = 0; diag_i < 12; diag_i = diag_i + 1)
            l2_phase_cycles[diag_i] = 0;
    end

    always @(posedge clk_i) begin
        if (!rst_i && dut.cache_stall === 1'b1) begin
            if (dut.l2_data_system_inst.controller.state < 12)
                l2_phase_cycles[
                    dut.l2_data_system_inst.controller.state
                ] = l2_phase_cycles[
                    dut.l2_data_system_inst.controller.state
                ] + 1;

            if (dut.mem_subsystem_inst.a_state == 2'd1)
                ram_busy_during_stall = ram_busy_during_stall + 1;

            if (dut.l2_data_system_inst.evict_valid &&
                !dut.l2_data_system_inst.evict_ready)
                buffer_block_cycles = buffer_block_cycles + 1;
        end
    end

endmodule

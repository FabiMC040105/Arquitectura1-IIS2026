// Testbench para medir los patrones de acceso a memoria.
// Usa el mismo criterio de terminacion que tb_run.
// RAW significa que aun falta validar los registros finales.
`timescale 1ns/1ps

// Numero maximo de ciclos antes de abortar, por si el programa no termina. Se puede subir con -DMAX_CICLOS=...
`ifndef MAX_CICLOS
  `define MAX_CICLOS 100000
`endif

// Cuantas palabras de memoria de datos se vuelcan al terminar.
`ifndef DUMP_PALABRAS
  `define DUMP_PALABRAS 16384
`endif

module tb_benchmarks_hw;

    // Cuantos bundles de NOP seguidos se consideran fin de programa.
    localparam integer NOPS_FIN = 40;

    logic clk_i;
    logic clk_mem_i;
    logic rst_i;
    logic stall_i;

    logic global_stall_o;

    logic [31:0]  pc_o;
    logic [127:0] bundle_o;
    logic         fetch_valid_o;

    logic [31:0] instr_alu_o;
    logic [31:0] instr_lsu_o;
    logic [31:0] instr_bru_o;
    logic [31:0] instr_feist_o;

    logic valid_alu_o;
    logic valid_lsu_o;
    logic valid_bru_o;
    logic valid_feist_o;
    logic dispatch_valid_o;

    top dut (
        .clk_i(clk_i),
        .clk_mem_i(clk_mem_i),
        .rst_i(rst_i),
        .stall_i(stall_i),

        .global_stall_o(global_stall_o),

        .pc_o(pc_o),
        .bundle_o(bundle_o),
        .fetch_valid_o(fetch_valid_o),

        .instr_alu_o(instr_alu_o),
        .instr_lsu_o(instr_lsu_o),
        .instr_bru_o(instr_bru_o),
        .instr_feist_o(instr_feist_o),

        .valid_alu_o(valid_alu_o),
        .valid_lsu_o(valid_lsu_o),
        .valid_bru_o(valid_bru_o),
        .valid_feist_o(valid_feist_o),

        .dispatch_valid_o(dispatch_valid_o)
    );

    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    // clk_mem_i: dominio de reloj separado para la memoria principal.
    // CPU a 100 MHz (periodo 10) y memoria a 25 MHz (periodo 40) => razon 4.
    initial begin
        clk_mem_i = 1'b0;
        forever #20 clk_mem_i = ~clk_mem_i;
    end

    string perf_nombre;
    string perf_csv;
    integer perf_fd;
    integer ciclos;
    integer nops_seguidos;
    integer i;
    logic [31:0] palabra;
    logic [15:0] direccion;

    // Vuelca los 16 registros
    task automatic volcar_registros;
        begin
            $display("");
            $display("--- Registros ---");
            for (i = 0; i < 16; i = i + 1) begin
                $display("  x%0d%s = %08h", i, (i < 10) ? " " : "",
                         dut.regfile_inst.regs[i]);
            end
        end
    endtask

    // Vuelca las primeras palabras de la memoria de datos. La memoria es direccionable por bytes y little-endian.
    task automatic volcar_memoria;
        begin
            $display("");
            $display("--- Memoria de datos (primeras %0d palabras) ---", `DUMP_PALABRAS);
            for (i = 0; i < `DUMP_PALABRAS; i = i + 1) begin
                palabra = {dut.mem_subsystem_inst.u_ctrl.memory[i*4 + 3],
                           dut.mem_subsystem_inst.u_ctrl.memory[i*4 + 2],
                           dut.mem_subsystem_inst.u_ctrl.memory[i*4 + 1],
                           dut.mem_subsystem_inst.u_ctrl.memory[i*4 + 0]};
                direccion = i*4;
                $display("  [%04h] = %08h", direccion, palabra);
            end
        end
    endtask

    initial begin
        // VCD desactivado para los benchmarks.
        // Las metricas se exportan a CSV.

        $display("========================================");
        $display("Ejecutando programa: %s", `PROGRAM_FILE);
        $display("Datos iniciales:     %s", `DATA_FILE);
        $display("========================================");

        ciclos = 0;
        nops_seguidos = 0;

        // Reset durante dos flancos.
        rst_i = 1'b1;
        stall_i = 1'b0;
        @(posedge clk_i);
        @(posedge clk_i);
        rst_i = 1'b0;

        // Ejecutar hasta detectar fin de programa o agotar el limite.
        while (ciclos < `MAX_CICLOS && nops_seguidos < NOPS_FIN) begin
            @(posedge clk_i);
            ciclos = ciclos + 1;

            // Un bundle completamente vacio es un NOP en los cuatro
            // slots. Varios seguidos indican que el programa ya no
            // tiene trabajo pendiente.
            if (dispatch_valid_o && !global_stall_o) begin
                if (bundle_o === 128'b0)
                    nops_seguidos = nops_seguidos + 1;
                else
                    nops_seguidos = 0;
            end
        end

        $display("");
        if (nops_seguidos >= NOPS_FIN)
            $display("Programa terminado tras %0d ciclos (%0d NOPs seguidos).",
                     ciclos, nops_seguidos);
        else
            $display("AVISO: limite de %0d ciclos alcanzado sin detectar fin.",
                     `MAX_CICLOS);

        $display("PC final = %08h", pc_o);

        volcar_registros();

        // Solo exportamos si el programa termino normalmente.
        if (nops_seguidos < NOPS_FIN)
            $fatal(1, "Benchmark sin finalizar");

        if (!$value$plusargs("BENCHMARK=%s", perf_nombre))
            $fatal(1, "Falta BENCHMARK");
        if (!$value$plusargs("PERF_CSV=%s", perf_csv))
            $fatal(1, "Falta PERF_CSV");

        perf_fd = $fopen(perf_csv, "w");
        if (perf_fd == 0) $fatal(1, "No se pudo abrir CSV");
        $fdisplay(perf_fd, "benchmark,configuration,status,memory_mhz,cycles,bundles,instructions,cache_stall_cycles,branch_stall_cycles,l2_lookup_stall_cycles,memory_stall_cycles,buffer_stall_cycles,l1_read_hits,l1_read_misses,l1_write_hits,l1_write_misses,l2_read_hits,l2_read_misses,l2_write_hits,l2_write_misses,mem_reads,mem_writes,mem_busy_cycles,mem_words");
        $fwrite(perf_fd, "%0s,l1_l2_ram,RAW,25", perf_nombre);
        $fwrite(perf_fd, ",%0d", dut.perf_cycles_o);
        $fwrite(perf_fd, ",%0d", dut.perf_bundles_o);
        $fwrite(perf_fd, ",%0d", dut.perf_instructions_o);
        $fwrite(perf_fd, ",%0d", dut.perf_cache_stall_cycles_o);
        $fwrite(perf_fd, ",%0d", dut.performance_counters_inst.branch_stall_cycles_o);
        $fwrite(perf_fd, ",%0d", dut.perf_l2_lookup_stall_cycles_o);
        $fwrite(perf_fd, ",%0d", dut.perf_memory_stall_cycles_o);
        $fwrite(perf_fd, ",%0d", dut.perf_buffer_stall_cycles_o);
        $fwrite(perf_fd, ",%0d", dut.performance_counters_inst.l1_read_hits_o);
        $fwrite(perf_fd, ",%0d", dut.performance_counters_inst.l1_read_misses_o);
        $fwrite(perf_fd, ",%0d", dut.performance_counters_inst.l1_write_hits_o);
        $fwrite(perf_fd, ",%0d", dut.performance_counters_inst.l1_write_misses_o);
        $fwrite(perf_fd, ",%0d", dut.perf_l2_read_hits_o);
        $fwrite(perf_fd, ",%0d", dut.perf_l2_read_misses_o);
        $fwrite(perf_fd, ",%0d", dut.perf_l2_write_hits_o);
        $fwrite(perf_fd, ",%0d", dut.perf_l2_write_misses_o);
        $fwrite(perf_fd, ",%0d", dut.perf_mem_reads_o);
        $fwrite(perf_fd, ",%0d", dut.perf_mem_writes_o);
        $fwrite(perf_fd, ",%0d", dut.perf_mem_busy_cycles_o);
        $fwrite(perf_fd, ",%0d", dut.perf_mem_words_o);
        $fwrite(perf_fd, "\n");
        $fclose(perf_fd);
        $display("Metricas RAW exportadas: %s", perf_csv);

        volcar_memoria();

        $display("");
        $display("========================================");
        $display("Ejecucion finalizada");
        $display("========================================");
        $finish;
    end

endmodule

`timescale 1ns/1ps

// Numero maximo de ciclos antes de abortar, por si el programa no termina. Se puede subir con -DMAX_CICLOS=...
`ifndef MAX_CICLOS
  `define MAX_CICLOS 2500000
`endif

// Cuantas palabras de memoria de datos se vuelcan al terminar.
`ifndef DUMP_PALABRAS
  `define DUMP_PALABRAS 16384
`endif

module tb_run;

    // Cuantos bundles de NOP seguidos se consideran fin de programa.
    localparam integer NOPS_FIN = 40;

    // Limite de ciclos para esperar flush_done_o antes de desistir. Con
    // EV_DEPTH lineas pendientes en el peor caso y Tmem ciclos cada una,
    // sobra margen generoso para cualquier combinacion razonable.
    localparam integer MAX_CICLOS_FLUSH = 100000;

    logic clk_i;
    logic clk_mem_i;
    logic rst_i;
    logic stall_i;
    logic flush;
    logic flush_done;

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
        .flush_i(flush),
        .flush_done_o(flush_done),

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
        flush = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    // clk_mem_i: dominio de reloj separado para la memoria principal.
    // CPU a 100 MHz (periodo 10) y memoria a 25 MHz (periodo 40) => razon 4.
    initial begin
        clk_mem_i = 1'b0;
        forever #20 clk_mem_i = ~clk_mem_i;
    end

    integer ciclos;
    integer ciclos_flush;
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

    // Vuelca las lineas dirty que siguen en L2 y que por lo tanto todavia
    // no llegaron a memoria principal (L2 es write-back, sin flush al
    // terminar el programa). Util para distinguir un store perdido de un
    // store que solo esta pendiente de eviccion.
    integer set_idx, way_idx;
    task automatic volcar_l2_dirty;
        begin
            $display("");
            $display("--- Lineas dirty en L2 (aun no escritas a memoria principal) ---");
            for (set_idx = 0; set_idx < 128; set_idx = set_idx + 1) begin
                for (way_idx = 0; way_idx < 4; way_idx = way_idx + 1) begin
                    if (dut.l2_data_system_inst.controller.cache_inst.valid_array[set_idx][way_idx] &&
                        dut.l2_data_system_inst.controller.cache_inst.dirty_array[set_idx][way_idx]) begin
                        $display("  set=%0d way=%0d addr_base=%08h data=%h",
                            set_idx, way_idx,
                            {dut.l2_data_system_inst.controller.cache_inst.tag_array[set_idx][way_idx], set_idx[6:0], 5'b0},
                            dut.l2_data_system_inst.controller.cache_inst.data_array[set_idx][way_idx]);
                    end
                end
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_run.vcd");
        $dumpvars(0, tb_run);

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

        // Al terminar el programa, L2 todavia puede tener lineas dirty
        // que nunca se evictaron (write-back sin flush implicito). Se
        // pide un flush total y se espera su propia senal de fin en vez
        // de un numero fijo de ciclos: el numero de lineas a drenar, y
        // por lo tanto la duracion real, depende del programa.
        flush = 1'b1;
        ciclos_flush = 0;
        while (!flush_done && ciclos_flush < MAX_CICLOS_FLUSH) begin
            @(posedge clk_i);
            ciclos_flush = ciclos_flush + 1;
        end
        @(posedge clk_i);
        flush = 1'b0;

        if (!flush_done && ciclos_flush >= MAX_CICLOS_FLUSH)
            $display("AVISO: flush no completo tras %0d ciclos.", MAX_CICLOS_FLUSH);

        $display("");
        if (nops_seguidos >= NOPS_FIN)
            $display("Programa terminado tras %0d ciclos (%0d NOPs seguidos).",
                     ciclos, nops_seguidos);
        else
            $display("AVISO: limite de %0d ciclos alcanzado sin detectar fin.",
                     `MAX_CICLOS);

        $display("PC final = %08h", pc_o);

        volcar_registros();
        volcar_l2_dirty();
        volcar_memoria();
        

        $display("");
        $display("========================================");
        $display("Ejecucion finalizada");
        $display("========================================");
        $finish;
    end

endmodule

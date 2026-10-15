`timescale 1ns/1ps

// Harness de ejecucion para programas arbitrarios del compilador.
//
// A diferencia de los testbenches de verificacion, este modulo no
// comprueba valores esperados: solo ejecuta el programa y vuelca el
// estado final. Sirve para correr binarios de la contraparte CE1108.
//
//   make run PROGRAM=salida_compilador.mem
//   make run PROGRAM=salida_compilador.mem DATA=mis_datos.mem
//
// El programa y los datos llegan por las macros PROGRAM_FILE y
// DATA_FILE que define el Makefile con -D. Si no se pasan, se usan
// program_test.mem e input.mem.

// Numero maximo de ciclos antes de abortar, por si el programa
// no termina. Se puede subir con -DMAX_CICLOS=...
`ifndef MAX_CICLOS
  `define MAX_CICLOS 100000
`endif

// Cuantas palabras de memoria de datos se vuelcan al terminar.
`ifndef DUMP_PALABRAS
  `define DUMP_PALABRAS 32
`endif

module tb_run;

    // Cuantos bundles de NOP seguidos se consideran fin de programa.
    localparam integer NOPS_FIN = 8;

    logic clk_i;
    logic rst_i;
    logic stall_i;

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

    // top toma PROGRAM_FILE y DATA_FILE de las macros, asi que no
    // hace falta sobreescribir parametros aqui.
    top dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_i),

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

    // Reloj de 10 ns de periodo.
    initial begin
        clk_i = 1'b0;
        forever #5 clk_i = ~clk_i;
    end

    integer ciclos;
    integer nops_seguidos;
    integer i;
    logic [31:0] palabra;
    logic [15:0] direccion;

    // Vuelca los 16 registros arquitectonicos.
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

    // Vuelca las primeras palabras de la memoria de datos.
    // La memoria es direccionable por bytes y little-endian.
    task automatic volcar_memoria;
        begin
            $display("");
            $display("--- Memoria de datos (primeras %0d palabras) ---",
                     `DUMP_PALABRAS);
            for (i = 0; i < `DUMP_PALABRAS; i = i + 1) begin
                palabra = {dut.data_memory_inst.memory[i*4 + 3],
                           dut.data_memory_inst.memory[i*4 + 2],
                           dut.data_memory_inst.memory[i*4 + 1],
                           dut.data_memory_inst.memory[i*4 + 0]};
                direccion = i*4;
                $display("  [%04h] = %08h", direccion, palabra);
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
            if (dispatch_valid_o) begin
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
        volcar_memoria();

        $display("");
        $display("========================================");
        $display("Ejecucion finalizada");
        $display("========================================");
        $finish;
    end

endmodule

`timescale 1ns/1ps

module tb_vliw_cuatro_unidades;

    // Reloj y señales de control
    logic clk_i = 0;
    logic rst_i;
    logic stall_i;

    // Salidas de observación
    wire [31:0] pc_o;
    wire [127:0] bundle_o;
    wire fetch_valid_o;

    integer i;
    logic vio_paralelismo = 0;

    // Procesador VLIW completo
    top #(
        .IMEM_WORDS(128),
        .PROGRAM_FILE("program_test.mem")
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_i),
        .pc_o(pc_o),
        .bundle_o(bundle_o),
        .fetch_valid_o(fetch_valid_o)
    );

    // Reloj de 10 nanosegundos
    always #5 clk_i = ~clk_i;

    // Construir instrucción ALU ADDI
    function automatic [31:0] alu_addi(
        input [11:0] imm,
        input [3:0] rs1,
        input [3:0] rd
    );
        alu_addi = {8'b0, imm, rs1, rd, 1'b1, 3'b001};
    endfunction

    // Construir instrucción LSU LOAD
    function automatic [31:0] lsu_load(
        input [11:0] offset,
        input [3:0] base,
        input [3:0] rd
    );
        lsu_load = {10'b0, offset, base, rd, 2'b01};
    endfunction

    // Construir instrucción AUTH
    function automatic [31:0] feist_auth(
        input [3:0] rs2,
        input [3:0] rs1
    );
        feist_auth = {21'b0, rs2, rs1, 3'b001};
    endfunction

    // Construir instrucción KSTORE
    function automatic [31:0] feist_kstore(
        input [1:0] key,
        input [1:0] round,
        input [3:0] rs1
    );
        feist_kstore = {21'b0, key, round, rs1, 3'b011};
    endfunction

    // Construir instrucción FROUND
    function automatic [31:0] feist_round(
        input [3:0] rdL,
        input [3:0] rdR,
        input [3:0] rsL,
        input [3:0] rsR,
        input [1:0] key,
        input [1:0] round,
        input mode
    );
        feist_round = {
            8'b0, rdL, rdR, rsL, rsR,
            key, round, mode, 3'b100
        };
    endfunction

    // Detectar que las tres unidades ejecutan
    // instrucciones válidas en la misma etapa EX
    always @(posedge clk_i) begin
        if (rst_i)
            vio_paralelismo <= 0;
        else if (
            dut.rr_ex_valid_out &&
            dut.ex_alu_valid &&
            dut.ex_lsu_mem_read &&
            dut.ex_feist_result_valid && 
            dut.ex_bru_valid && 
            dut.ex_bru_opcode == 3'b100 && 
            dut.ex_bru_branch_taken == 1'b0
        )
            vio_paralelismo <= 1;
    end

    
    // Construir instruccion BEQ del slot BRU
    function automatic [31:0] bru_beq(
        input [11:0] offset,
        input [3:0] rs2,
        input [3:0] rs1
    );
        bru_beq = {
            9'b0, offset, rs2, rs1, 3'b100
        };
    endfunction
    
    
    
    initial begin
        rst_i = 1;
        stall_i = 0;

        // Esperar inicialización de memorias
        #1;

        // Limpiar la memoria de instrucciones
        for (i = 0; i < 32; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 0;

        // Bundle 1: autenticarse con x2 y x3
        dut.fetch_inst.instruction_memory_inst.memory[1] = {
            feist_auth(4'd3, 4'd2),
            96'b0
        };

        // Bundle 6: guardar subllave desde x4
        dut.fetch_inst.instruction_memory_inst.memory[6] = {
            feist_kstore(2'd0, 2'd0, 4'd4),
            96'b0
        };

        // Bundle 11: tres unidades en paralelo
        // ALU:   x11 = x0 + 9
        // LSU:   x12 = memoria[0]
        // FEIST: x13 y x14 = FROUND(x5, x6)
        dut.fetch_inst.instruction_memory_inst.memory[11] = {
            feist_round(4'd13, 4'd14, 4'd5, 4'd6,
                        2'd0, 2'd0, 1'b0),
            bru_beq(12'd16, 4'd2, 4'd0),
            lsu_load(12'd0, 4'd0, 4'd12),
            alu_addi(12'd9, 4'd0, 4'd11)
        };

        // Preparar memoria para LOAD
        // Dato hexadecimal 11223344
        dut.data_memory_inst.memory[0] = 8'h44;
        dut.data_memory_inst.memory[1] = 8'h33;
        dut.data_memory_inst.memory[2] = 8'h22;
        dut.data_memory_inst.memory[3] = 8'h11;

        // Liberar reset
        @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 0;

        // Preparar credenciales, subllave y mensaje
        dut.regfile_inst.regs[2] = 32'hC0DE1234;
        dut.regfile_inst.regs[3] = 32'hABCD5678;
        dut.regfile_inst.regs[4] = 32'hDEADBEEF;
        dut.regfile_inst.regs[5] = 32'h01234567;
        dut.regfile_inst.regs[6] = 32'h89ABCDEF;

        // Esperar a que las instrucciones lleguen a WB
        repeat (23) @(posedge clk_i);
        #1;

        // PRUEBA 1: Autenticación
        if (dut.key_vault_inst.authorized !== 1'b1)
            $fatal(1, "ERROR: AUTH fallo");

        $display("PASS: Boveda autenticada");

        // PRUEBA 2: KSTORE
        if (dut.key_vault_inst.subkeys[0][0]
            !== 32'hDEADBEEF)
            $fatal(1, "ERROR: KSTORE fallo");

        $display("PASS: Subllave almacenada");

        // PRUEBA 3: Ejecución simultánea en EX
        if (vio_paralelismo !== 1'b1)
            $fatal(1, "ERROR: no hubo ejecucion paralela");

        $display("PASS: Tres unidades activas en EX");

        // PRUEBA 4: ALU
        if (dut.regfile_inst.regs[11] !== 32'd9)
            $fatal(1, "ERROR: resultado ALU");

        $display("PASS: ALU escribio x11 = 9");

        // PRUEBA 5: LSU
        if (dut.regfile_inst.regs[12] !== 32'h11223344)
            $fatal(1, "ERROR: resultado LSU");

        $display("PASS: LSU escribio x12 = 11223344");

        // PRUEBA 6: FEISTEL
        if (dut.regfile_inst.regs[13] !== 32'h89ABCDEF)
            $fatal(1, "ERROR: L de Feistel");

        if (dut.regfile_inst.regs[14] !== 32'h6CB9C8B2)
            $fatal(1, "ERROR: R de Feistel");

        $display("PASS: FROUND escribio x13 y x14");

        // PRUEBA 7: Proteger x0
        if (dut.regfile_inst.regs[0] !== 32'b0)
            $fatal(1, "ERROR: x0 fue modificado");

        $display("PASS: x0 permanece en cero");

        $display("----------------------------------");
        $display("PRUEBA DE TRES UNIDADES SUPERADA");
        $display("----------------------------------");

        $finish;
    end

endmodule

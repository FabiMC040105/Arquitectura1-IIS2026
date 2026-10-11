`timescale 1ns/1ps

module tb_feistel_memoria;

    // Reloj y control del procesador
    logic clk_i = 0;
    logic rst_i;
    logic stall_i;

    // Salidas para observar el procesador
    wire [31:0] pc_o;
    wire [127:0] bundle_o;
    wire fetch_valid_o;

    integer i;
    integer rondas_vistas = 0;

    // Instancia del procesador completo
    top #(
        .IMEM_WORDS(512),
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

    // Construir instruccion AUTH
    function automatic [31:0] feist_auth(
        input [3:0] rs2,
        input [3:0] rs1
    );
        feist_auth = {21'b0, rs2, rs1, 3'b001};
    endfunction

    // Construir instruccion KSTORE
    function automatic [31:0] feist_kstore(
        input [1:0] key,
        input [1:0] round,
        input [3:0] rs1
    );
        feist_kstore = {21'b0, key, round, rs1, 3'b011};
    endfunction

    // Construir instruccion FROUND
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


    // Construir instruccion STORE para guardar datos en memoria
    function automatic [31:0] lsu_store(
        input [11:0] offset,
        input [3:0] base,
        input [3:0] rs1
    );
        lsu_store = {
            10'b0, offset, base, rs1, 2'b10
        };
    endfunction


    // Contar las rondas que realmente se ejecutan
    always @(posedge clk_i) begin
        if (rst_i)
            rondas_vistas <= 0;
        else if (dut.ex_feist_fround_req &&
                 dut.ex_feist_result_valid)
            rondas_vistas <= rondas_vistas + 1;
    end

    initial begin

        rst_i = 1;
        stall_i = 0;

        // Esperar inicializacion de memoria
        #1;

        // Limpiar el programa de prueba
        for (i = 0; i < 128; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 0;

        // =============================================
        // ETAPA 1: AUTENTICACION
        // =============================================

        // AUTH utilizando x2 y x3
        dut.fetch_inst.instruction_memory_inst.memory[1] = {
            feist_auth(4'd3, 4'd2), 96'b0
        };

        // =============================================
        // ETAPA 2: GUARDAR LAS CUATRO SUBLLAVES
        // =============================================

        // Todas pertenecen a la llave numero 0
        // Se insertan NOPs entre instrucciones

        dut.fetch_inst.instruction_memory_inst.memory[6] = {
            feist_kstore(0, 0, 4'd11), 96'b0
        };

        dut.fetch_inst.instruction_memory_inst.memory[11] = {
            feist_kstore(0, 1, 4'd12), 96'b0
        };

        dut.fetch_inst.instruction_memory_inst.memory[16] = {
            feist_kstore(0, 2, 4'd13), 96'b0
        };

        dut.fetch_inst.instruction_memory_inst.memory[21] = {
            feist_kstore(0, 3, 4'd14), 96'b0
        };

        // =============================================
        // ETAPA 3: CIFRADO DE CUATRO RONDAS
        // =============================================

        // Ronda 0: x5/x6 -> x7/x8
        dut.fetch_inst.instruction_memory_inst.memory[26] = {
            feist_round(7, 8, 5, 6, 0, 0, 0),
            96'b0
        };

        // Ronda 1: x7/x8 -> x7/x8
        dut.fetch_inst.instruction_memory_inst.memory[31] = {
            feist_round(7, 8, 7, 8, 0, 1, 0),
            96'b0
        };

        // Ronda 2: x7/x8 -> x7/x8
        dut.fetch_inst.instruction_memory_inst.memory[36] = {
            feist_round(7, 8, 7, 8, 0, 2, 0),
            96'b0
        };

        // Ronda 3: x7/x8 -> x9/x10
        // Guardamos el bloque cifrado en x9/x10
        dut.fetch_inst.instruction_memory_inst.memory[41] = {
            feist_round(9, 10, 7, 8, 0, 3, 0),
            96'b0
        };

        // =============================================
        // ETAPA 4: DESCIFRADO DE CUATRO RONDAS
        // =============================================

        // Utilizar las subllaves en orden contrario

        // Ronda inversa 3
        dut.fetch_inst.instruction_memory_inst.memory[46] = {
            feist_round(7, 8, 9, 10, 0, 3, 1),
            96'b0
        };

        // Ronda inversa 2
        dut.fetch_inst.instruction_memory_inst.memory[51] = {
            feist_round(7, 8, 7, 8, 0, 2, 1),
            96'b0
        };

        // Ronda inversa 1
        dut.fetch_inst.instruction_memory_inst.memory[56] = {
            feist_round(7, 8, 7, 8, 0, 1, 1),
            96'b0
        };

        // Ronda inversa 0
        dut.fetch_inst.instruction_memory_inst.memory[61] = {
            feist_round(7, 8, 7, 8, 0, 0, 1),
            96'b0
        };


    // =============================================
    // ETAPA: GUARDAR RESULTADOS EN MEMORIA
    // =============================================

    // Guardar primera mitad cifrada en direcciones 0-3
    dut.fetch_inst.instruction_memory_inst.memory[66] = {
        64'b0,
        lsu_store(12'd0, 4'd0, 4'd9),
        32'b0
    };

    // Guardar segunda mitad cifrada en direcciones 4-7
    dut.fetch_inst.instruction_memory_inst.memory[71] = {
        64'b0,
        lsu_store(12'd4, 4'd0, 4'd10),
        32'b0
    };

    // Guardar primera mitad descifrada en direcciones 8-11
    dut.fetch_inst.instruction_memory_inst.memory[76] = {
        64'b0,
        lsu_store(12'd8, 4'd0, 4'd7),
        32'b0
    };

    // Guardar segunda mitad descifrada en direcciones 12-15
    dut.fetch_inst.instruction_memory_inst.memory[81] = {
        64'b0,
        lsu_store(12'd12, 4'd0, 4'd8),
        32'b0
    };


    // =============================================
    // ETAPA 5: PREPARAR LOS REGISTROS DE PRUEBA
    // =============================================

    // Mantener reset durante un flanco
    @(posedge clk_i);
    @(negedge clk_i);
    rst_i = 0;

    // Credenciales de autenticacion
    dut.regfile_inst.regs[2] = 32'hC0DE1234;
    dut.regfile_inst.regs[3] = 32'hABCD5678;

    // Mensaje HOLA1234
    dut.regfile_inst.regs[5] = 32'h484F4C41;
    dut.regfile_inst.regs[6] = 32'h31323334;

    // Cuatro subllaves de 32 bits
    dut.regfile_inst.regs[11] = 32'h12345678;
    dut.regfile_inst.regs[12] = 32'hABCDEF01;
    dut.regfile_inst.regs[13] = 32'h98765432;
    dut.regfile_inst.regs[14] = 32'hFEDCBA98;

    // Esperar a que termine el programa
    repeat (100) @(posedge clk_i);
    #1;

    // =============================================
    // ETAPA 6: COMPROBAR RESULTADOS
    // =============================================

    // PRUEBA 1: Autenticacion
    if (dut.key_vault_inst.authorized !== 1'b1)
        $fatal(1, "ERROR: AUTH fallo");

    $display("PASS: Boveda autenticada");

    // PRUEBA 2: Las cuatro subllaves
    if (dut.key_vault_inst.subkeys[0][0] !== 32'h12345678 ||
        dut.key_vault_inst.subkeys[0][1] !== 32'hABCDEF01 ||
        dut.key_vault_inst.subkeys[0][2] !== 32'h98765432 ||
        dut.key_vault_inst.subkeys[0][3] !== 32'hFEDCBA98)
        $fatal(1, "ERROR: subllaves incorrectas");

    $display("PASS: Cuatro subllaves almacenadas");

    // PRUEBA 3: Se ejecutaron ocho rondas
    if (rondas_vistas !== 8)
        $fatal(1, "ERROR: se ejecutaron %0d rondas",
            rondas_vistas);

    $display("PASS: 4 rondas de cifrado y 4 de descifrado");

    // PRUEBA 4: Resultado del cifrado
    if (dut.regfile_inst.regs[9] !== 32'h58991CF5 ||
        dut.regfile_inst.regs[10] !== 32'h18432589)
        $fatal(1, "ERROR: cifrado incorrecto");

    $display("PASS: Cifrado correcto");
    $display("Cifrado: %h %h",
            dut.regfile_inst.regs[9],
            dut.regfile_inst.regs[10]);

    // PRUEBA 5: Recuperar HOLA1234
    if (dut.regfile_inst.regs[7] !== 32'h484F4C41 ||
        dut.regfile_inst.regs[8] !== 32'h31323334)
        $fatal(1, "ERROR: descifrado incorrecto");

    $display("PASS: Descifrado correcto");
    $display("Recuperado: %h %h",
            dut.regfile_inst.regs[7],
            dut.regfile_inst.regs[8]);

    $display("--------------------------------");
    $display("FEISTEL4 COMPLETO EN PIPELINE SUPERADO");
    $display("--------------------------------");

    
    
    // =============================================
    // COMPROBAR LA MEMORIA REAL
    // =============================================

    $display("===== MEMORIA DE DATOS =====");

    if ({
        dut.data_memory_inst.memory[3],
        dut.data_memory_inst.memory[2],
        dut.data_memory_inst.memory[1],
        dut.data_memory_inst.memory[0]
    } !== 32'h58991CF5)
        $fatal(1, "ERROR: primera mitad cifrada en memoria");

    if ({
        dut.data_memory_inst.memory[7],
        dut.data_memory_inst.memory[6],
        dut.data_memory_inst.memory[5],
        dut.data_memory_inst.memory[4]
    } !== 32'h18432589)
        $fatal(1, "ERROR: segunda mitad cifrada en memoria");

    if ({
        dut.data_memory_inst.memory[11],
        dut.data_memory_inst.memory[10],
        dut.data_memory_inst.memory[9],
        dut.data_memory_inst.memory[8]
    } !== 32'h484F4C41)
        $fatal(1, "ERROR: primera mitad descifrada en memoria");

    if ({
        dut.data_memory_inst.memory[15],
        dut.data_memory_inst.memory[14],
        dut.data_memory_inst.memory[13],
        dut.data_memory_inst.memory[12]
    } !== 32'h31323334)
        $fatal(1, "ERROR: segunda mitad descifrada en memoria");

    $display("PASS: Cifrado y descifrado guardados en memoria");

    $display("CIFRADO EN MEMORIA:    %h %h",
        dut.regfile_inst.regs[9],
        dut.regfile_inst.regs[10]);

    $display("DESCIFRADO EN MEMORIA: %h %h",
        dut.regfile_inst.regs[7],
        dut.regfile_inst.regs[8]);
        
        
    

        
        $finish;
    end

endmodule

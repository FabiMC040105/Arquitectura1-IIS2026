
`timescale 1ns/1ps

module tb_feist_decoder;

    // Instrucción recibida desde el dispatcher general
    logic [31:0] instr_feist_i;
    logic valid_feist_i;

    // Señales que genera nuestro decodificador
    wire auth_en;
    wire logout_en;
    wire kstore_en;
    wire fround_en;
    wire illegal_opcode;

    // Registros utilizados para AUTH y KSTORE
    wire [3:0] auth_rs1_o, auth_rs2_o;
    wire [3:0] kstore_rs1_o;

    // Registros de entrada y salida de FROUND
    wire [3:0] rdL_o, rdR_o;
    wire [3:0] rsL_o, rsR_o;

    // Selección de llave, ronda y modo
    wire [1:0] key_o, round_o;
    wire mode_o;

    // Instancia del decodificador que queremos probar
    feist_decoder dut (
        .instr_feist_i(instr_feist_i),
        .valid_feist_i(valid_feist_i),

        .auth_en(auth_en),
        .logout_en(logout_en),
        .kstore_en(kstore_en),
        .fround_en(fround_en),
        .illegal_opcode(illegal_opcode),

        .auth_rs1_o(auth_rs1_o),
        .auth_rs2_o(auth_rs2_o),
        .kstore_rs1_o(kstore_rs1_o),

        .rdL_o(rdL_o),
        .rdR_o(rdR_o),
        .rsL_o(rsL_o),
        .rsR_o(rsR_o),

        .key_o(key_o),
        .round_o(round_o),
        .mode_o(mode_o)
    );

    // Tarea para comprobar las 5 señales de control
    task automatic revisar_controles(
        input string nombre,
        input logic [4:0] esperado
    );
        begin
            #1;

            if ({auth_en, logout_en, kstore_en,
                 fround_en, illegal_opcode} !== esperado)
                $fatal(1, "ERROR en controles: %s", nombre);

            $display("PASS: %s", nombre);
        end
    endtask

    initial begin

        // Archivo para visualizar las señales
        $dumpfile("tb_feist_decoder.vcd");
        $dumpvars(0, tb_feist_decoder);

        // Inicializar entradas
        instr_feist_i = 32'b0;
        valid_feist_i = 0;

        // PRUEBA 1: NOP
        instr_feist_i = 32'b0;
        valid_feist_i = 1;
        revisar_controles("NOP", 5'b00000);

        // PRUEBA 2: AUTH
        // rs1 = x2, rs2 = x3
        instr_feist_i = {
            21'b0,
            4'd3,
            4'd2,
            3'b001
        };

        revisar_controles("AUTH", 5'b10000);

        if (auth_rs1_o !== 4'd2 ||
            auth_rs2_o !== 4'd3)
            $fatal(1, "ERROR: registros AUTH incorrectos");

        $display("PASS: Registros AUTH correctos");

        // PRUEBA 3: LOGOUT
        instr_feist_i = 32'h00000002;
        revisar_controles("LOGOUT", 5'b01000);

        // PRUEBA 4: KSTORE
        // Llave 2, ronda 1, registro x6
        instr_feist_i = {
            21'b0,
            2'd2,
            2'd1,
            4'd6,
            3'b011
        };

        revisar_controles("KSTORE", 5'b00100);

        if (key_o !== 2'd2 ||
            round_o !== 2'd1 ||
            kstore_rs1_o !== 4'd6)
            $fatal(1, "ERROR: campos KSTORE incorrectos");

        $display("PASS: Campos KSTORE correctos");

        // PRUEBA 5: FROUND
        // FROUND x4, x5, x2, x3, 2, 1, 0
        instr_feist_i = {
            8'b0,
            4'd4,  // rdL = x4
            4'd5,  // rdR = x5
            4'd2,  // rsL = x2
            4'd3,  // rsR = x3
            2'd2,  // Llave 2
            2'd1,  // Ronda 1
            1'b0,  // Cifrado
            3'b100 // FROUND
        };

        revisar_controles("FROUND", 5'b00010);

        if (rdL_o !== 4'd4 ||
            rdR_o !== 4'd5 ||
            rsL_o !== 4'd2 ||
            rsR_o !== 4'd3 ||
            key_o !== 2'd2 ||
            round_o !== 2'd1 ||
            mode_o !== 1'b0)
            $fatal(1, "ERROR: campos FROUND incorrectos");

        $display("PASS: Registros y campos FROUND correctos");

        // PRUEBA 6: Cambiar a modo descifrado
        instr_feist_i[3] = 1'b1;
        #1;

        if (mode_o !== 1'b1)
            $fatal(1, "ERROR: modo descifrado incorrecto");

        $display("PASS: Modo descifrado correcto");

        // PRUEBA 7: Opcode desconocido
        instr_feist_i = 32'h00000007;
        revisar_controles("Opcode ilegal", 5'b00001);

        // PRUEBA 8: Instrucción no válida
        instr_feist_i = 32'h00000004;
        valid_feist_i = 0;

        revisar_controles("Instruccion no valida", 5'b00000);

        // Los operandos también deben quedar en cero
        if ({rdL_o, rdR_o, rsL_o, rsR_o,
             key_o, round_o, mode_o} !== 21'b0)
            $fatal(1, "ERROR: operandos activos sin validez");

        $display("PASS: Operandos desactivados");

        $display("--------------------------------");
        $display("TODAS LAS PRUEBAS DEL DECODER PASARON");
        $display("--------------------------------");

        $finish;
    end

endmodule

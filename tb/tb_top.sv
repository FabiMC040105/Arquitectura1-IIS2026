`timescale 1ns/1ps

// Prueba de integracion del pipeline completo.
// Ejecuta program_test.mem: construye credenciales y una llave de
// prueba, autentica ante la boveda, guarda la subllave en las 4
// rondas de K0 y descifra 25 bloques de 64 bits de input.mem con
// Feistel, verificando el resultado contra el modelo de referencia.
module tb_top;

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

    top #(
        .IMEM_WORDS(800),
        .PROGRAM_FILE("program_test.mem"),
        .DATA_FILE("input.mem")
    ) dut (
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

    // Reloj de 10 ns.
    initial clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    /
    // PC del bundle jmp-self con el que termina program_test.mem (linea 196 -> (196-1)*16 = 3120 = 0xC30).
    localparam logic [31:0] HALT_PC = 32'h00000C30;

    // Direccion de memoria del primer bloque de 64 bits descifrado.
    localparam logic [31:0] BLOCK0_ADDR = 32'h00000000;

    // Resultado esperado del primer bloque tras las 4 rondas de descifrado con subllave=1 
    localparam logic [31:0] BLOCK0_L_EXPECTED = 32'h7F020100;
    localparam logic [31:0] BLOCK0_R_EXPECTED = 32'h0041FF80;

    integer ciclo;
    integer halt_streak;
    integer timeout;

    initial begin
        $display("========================================");
        $display("Inicio de pruebas de TOP");
        $display("========================================");
        rst_i   = 1'b1;
        stall_i = 1'b0;

        // 1. El reset deja el PC en su valor inicial.
        @(posedge clk_i);
        #1;

        if (pc_o !== 32'h00000000)
            $fatal(1, "ERROR: PC incorrecto despues del reset");

        $display("PASS: reset deja el PC en 0x0");

        if (dut.if_access_error !== 1'b0)
            $fatal(1, "ERROR: Fetch detecto un error de acceso inesperado");

        @(negedge clk_i);
        rst_i = 1'b0;

        // 2. El PC avanza 16 bytes por ciclo.
        @(posedge clk_i);
        #1;

        if (pc_o !== 32'h00000010)
            $fatal(1, "ERROR: el PC no avanzo 16 bytes (pc=%h)", pc_o);

        $display("PASS: el PC avanza un bundle por ciclo");

        // 3. Con stall el PC se mantiene.
        @(negedge clk_i);
        stall_i = 1'b1;

        @(posedge clk_i);
        #1;

        if (pc_o !== 32'h00000010)
            $fatal(1, "ERROR: el PC avanzo durante stall (pc=%h)", pc_o);

        $display("PASS: stall mantiene el PC");

        @(negedge clk_i);
        stall_i = 1'b0;

        // 4. Dispatch debe separar cada bundle en sus 4 slots y marcar como valido unicamente el slot que trae una instruccion distinta de NOP. 
        #1;

        if (dut.id_pc !== 32'h00000000)
            $fatal(1, "ERROR: se esperaba el bundle de PC=0x0 en ID, pero id_pc=%h", dut.id_pc);

        if (!dispatch_valid_o)
            $fatal(1, "ERROR: Dispatch no valido para el bundle de PC=0x0");

        if (!valid_alu_o || valid_lsu_o || valid_bru_o || valid_feist_o)
            $fatal(1, "ERROR: validez de slots incorrecta en el bundle de PC=0x0 (alu=%b lsu=%b bru=%b feist=%b)",
                   valid_alu_o, valid_lsu_o, valid_bru_o, valid_feist_o);

        if (instr_alu_o !== dut.id_bundle[31:0])
            $fatal(1, "ERROR: el slot ALU no coincide con el bundle recibido");

        if (instr_lsu_o !== dut.id_bundle[63:32])
            $fatal(1, "ERROR: el slot LSU no coincide con el bundle recibido");

        if (instr_bru_o !== dut.id_bundle[95:64])
            $fatal(1, "ERROR: el slot BRU no coincide con el bundle recibido");

        if (instr_feist_o !== dut.id_bundle[127:96])
            $fatal(1, "ERROR: el slot FEIST no coincide con el bundle recibido");

        $display("PASS: Dispatch separa correctamente el bundle de PC=0x0");

        // 5. Dejar correr hasta que x4 (subllave de prueba, linea 71, PC=0x460) termine de escribirse en WB: 
        timeout = 0;
        while (!(dut.ex_wb_valid_out && dut.wb_alu_write_enable &&
                 dut.wb_pc == 32'h00000460) && timeout < 200) begin
            @(posedge clk_i);
            #1;
            timeout = timeout + 1;
        end
        if (timeout >= 200)
            $fatal(1, "ERROR: timeout esperando WB de x4 (PC=0x460)");
        @(posedge clk_i);
        #1;

        if (dut.regfile_inst.regs[2] !== 32'hC0DE1234)
            $fatal(1, "ERROR: x2 = %h, se esperaba C0DE1234 (AUTH_ID)",
                   dut.regfile_inst.regs[2]);

        $display("PASS: x2 = 0xC0DE1234 (credencial de usuario)");

        if (dut.regfile_inst.regs[3] !== 32'hABCD5678)
            $fatal(1, "ERROR: x3 = %h, se esperaba ABCD5678 (AUTH_PASS)",
                   dut.regfile_inst.regs[3]);

        $display("PASS: x3 = 0xABCD5678 (credencial de usuario)");

        if (dut.regfile_inst.regs[4] !== 32'd1)
            $fatal(1, "ERROR: x4 = %0d, se esperaba 1 (subllave de prueba)",
                   dut.regfile_inst.regs[4]);

        $display("PASS: x4 = 1 (subllave de prueba)");

        // x0 debe seguir siendo cero.
        if (dut.regfile_inst.regs[0] !== 32'd0)
            $fatal(1, "ERROR: x0 fue modificado");

        $display("PASS: x0 permanece en cero");

        // 6. AUTH (linea 76, PC=0x4B0) debe autorizar la boveda: 
        timeout = 0;
        while (!(dut.ex_feist_auth_req && dut.ex_pc == 32'h000004B0) && timeout < 100) begin
            @(posedge clk_i);
            timeout = timeout + 1;
        end
        if (timeout >= 100)
            $fatal(1, "ERROR: timeout esperando AUTH en EX (PC=0x4B0)");
        @(posedge clk_i);
        #1;

        if (dut.key_vault_inst.authorized !== 1'b1)
            $fatal(1, "ERROR: AUTH no autorizo la boveda");

        $display("PASS: AUTH autoriza la boveda con las credenciales correctas");

        // 7. Los 4 KSTORE (lineas 81-96, PC=0x500..0x5F0) deben guardar la subllave=1 en las 4 rondas de la llave 0. 
        timeout = 0;
        while (!(dut.ex_feist_kstore_req && dut.ex_pc == 32'h000005F0) && timeout < 100) begin
            @(posedge clk_i);
            timeout = timeout + 1;
        end
        if (timeout >= 100)
            $fatal(1, "ERROR: timeout esperando KSTORE final en EX (PC=0x5F0)");
        @(posedge clk_i);
        #1;

        if (dut.key_vault_inst.subkeys[0][0] !== 32'd1 ||
            dut.key_vault_inst.subkeys[0][1] !== 32'd1 ||
            dut.key_vault_inst.subkeys[0][2] !== 32'd1 ||
            dut.key_vault_inst.subkeys[0][3] !== 32'd1)
            $fatal(1, "ERROR: K0 no quedo con subllave=1 en las 4 rondas (%0d,%0d,%0d,%0d)",
                   dut.key_vault_inst.subkeys[0][0], dut.key_vault_inst.subkeys[0][1],
                   dut.key_vault_inst.subkeys[0][2], dut.key_vault_inst.subkeys[0][3]);

        $display("PASS: K0[0..3] = 1 guardadas en la boveda");

        // 8. Dejar correr el loop de descifrado hasta que el JMP-self (fin del programa) se ejecute varias veces en EX.
        halt_streak = 0;
        ciclo = 0;
        while (halt_streak < 5 && ciclo < 2000) begin
            @(posedge clk_i);
            #1;
            if (dut.ex_branch_taken && dut.ex_pc == HALT_PC)
                halt_streak = halt_streak + 1;
            ciclo = ciclo + 1;
        end

        if (halt_streak < 5)
            $fatal(1, "ERROR: el programa no alcanzo el jmp-self en %0d ciclos (pc=%h)",
                   ciclo, pc_o);

        $display("PASS: el programa termina en el jmp-self (pc=%h) tras %0d ciclos",
                  dut.ex_pc, ciclo);

        // Dejar drenar el pipeline para que el ultimo STORE del loop se complete en memoria.
        for (ciclo = 0; ciclo < 5; ciclo = ciclo + 1) begin
            @(posedge clk_i);
        end
        #1;

        // 9. x5 (contador de bloques) debe llegar a 0 y x14 (puntero) debe apuntar al final de los 200 bytes descifrados.
        if (dut.regfile_inst.regs[5] !== 32'd0)
            $fatal(1, "ERROR: x5 = %0d, se esperaba 0 (loop completo)",
                   dut.regfile_inst.regs[5]);

        $display("PASS: x5 = 0 (los 25 bloques fueron procesados)");

        if (dut.regfile_inst.regs[14] !== 32'd200)
            $fatal(1, "ERROR: x14 = %0d, se esperaba 200 (puntero al final de los datos)",
                   dut.regfile_inst.regs[14]);

        $display("PASS: x14 = 200 (puntero avanzo los 25 bloques de 8 bytes)");

        // 10. El primer bloque descifrado en memoria debe coincidir con el modelo de referencia.
        if ({dut.data_memory_inst.memory[BLOCK0_ADDR+3],
             dut.data_memory_inst.memory[BLOCK0_ADDR+2],
             dut.data_memory_inst.memory[BLOCK0_ADDR+1],
             dut.data_memory_inst.memory[BLOCK0_ADDR]} !== BLOCK0_L_EXPECTED)
            $fatal(1, "ERROR: bloque 0 (L) descifrado incorrecto, obtuve %h, esperaba %h",
                   {dut.data_memory_inst.memory[BLOCK0_ADDR+3],
                    dut.data_memory_inst.memory[BLOCK0_ADDR+2],
                    dut.data_memory_inst.memory[BLOCK0_ADDR+1],
                    dut.data_memory_inst.memory[BLOCK0_ADDR]}, BLOCK0_L_EXPECTED);

        if ({dut.data_memory_inst.memory[BLOCK0_ADDR+7],
             dut.data_memory_inst.memory[BLOCK0_ADDR+6],
             dut.data_memory_inst.memory[BLOCK0_ADDR+5],
             dut.data_memory_inst.memory[BLOCK0_ADDR+4]} !== BLOCK0_R_EXPECTED)
            $fatal(1, "ERROR: bloque 0 (R) descifrado incorrecto, obtuve %h, esperaba %h",
                   {dut.data_memory_inst.memory[BLOCK0_ADDR+7],
                    dut.data_memory_inst.memory[BLOCK0_ADDR+6],
                    dut.data_memory_inst.memory[BLOCK0_ADDR+5],
                    dut.data_memory_inst.memory[BLOCK0_ADDR+4]}, BLOCK0_R_EXPECTED);

        $display("PASS: bloque 0 descifrado correctamente (L=%h R=%h)",
                  BLOCK0_L_EXPECTED, BLOCK0_R_EXPECTED);

        $display("========================================");
        $display("Pruebas de TOP finalizadas: TODAS PASARON");
        $display("========================================");
        $finish;
    end

endmodule

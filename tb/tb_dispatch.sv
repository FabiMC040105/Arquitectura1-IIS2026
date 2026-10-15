`timescale 1ns/1ps

module tb_dispatch;

    // Entradas que voy a utilizar para probar Dispatch.
    logic [127:0] bundle_i;
    logic [31:0] pc_i;
    logic valid_i;

    // Salidas con las instrucciones completas de cada slot.
    logic [31:0] instr_alu_o;
    logic [31:0] instr_lsu_o;
    logic [31:0] instr_bru_o;
    logic [31:0] instr_feist_o;

    // Salida del PC.
    logic [31:0] pc_o;

    // Senales que indican si cada slot tiene una instruccion valida.
    logic valid_alu_o;
    logic valid_lsu_o;
    logic valid_bru_o;
    logic valid_feist_o;

    // Senal que indica si el bundle completo es valido.
    logic valid_o;

    // Instancia del modulo que voy a probar.
    dispatch dut (
        .bundle_i(bundle_i),
        .pc_i(pc_i),
        .valid_i(valid_i),

        .instr_alu_o(instr_alu_o),
        .instr_lsu_o(instr_lsu_o),
        .instr_bru_o(instr_bru_o),
        .instr_feist_o(instr_feist_o),

        .pc_o(pc_o),

        .valid_alu_o(valid_alu_o),
        .valid_lsu_o(valid_lsu_o),
        .valid_bru_o(valid_bru_o),
        .valid_feist_o(valid_feist_o),

        .valid_o(valid_o)
    );

    initial begin

        $display("========================================");
        $display("Inicio de pruebas de DISPATCH");
        $display("========================================");

        // PRUEBA 1:
        // Compruebo que cada instruccion llegue completa
        // al slot que le corresponde y que el PC se conserve.

        bundle_i = {
            32'h12345671,  // Slot 3: FEIST
            32'hABCDEF05,  // Slot 2: BRU
            32'h87654322,  // Slot 1: LSU
            32'hFEDCBA13   // Slot 0: ALU
        };

        pc_i = 32'h00000100;
        valid_i = 1'b1;

        #1;

        if (instr_alu_o !== 32'hFEDCBA13)
            $fatal(1, "Error: la instruccion ALU no coincide");

        if (instr_lsu_o !== 32'h87654322)
            $fatal(1, "Error: la instruccion LSU no coincide");

        if (instr_bru_o !== 32'hABCDEF05)
            $fatal(1, "Error: la instruccion BRU no coincide");

        if (instr_feist_o !== 32'h12345671)
            $fatal(1, "Error: la instruccion FEIST no coincide");

        if (pc_o !== 32'h00000100)
            $fatal(1, "Error: el PC no se conserva correctamente");

        if (valid_o !== 1'b1)
            $fatal(1, "Error: el bundle deberia ser valido");

        $display("PASS: separacion de slots y PC");


        // PRUEBA 2:
        // Compruebo que los slots con opcode distinto de cero
        // se marquen como validos.

        if (valid_alu_o !== 1'b1)
            $fatal(1, "Error: validez de ALU incorrecta");

        if (valid_lsu_o !== 1'b1)
            $fatal(1, "Error: validez de LSU incorrecta");

        if (valid_bru_o !== 1'b1)
            $fatal(1, "Error: validez de BRU incorrecta");

        if (valid_feist_o !== 1'b1)
            $fatal(1, "Error: validez de FEIST incorrecta");

        $display("PASS: validez de los slots");


        // PRUEBA 3:
        // Coloco NOP en los cuatro slots.
        // Como todos los opcodes son cero, ningun slot debe ser valido.

        bundle_i = 128'b0;
        pc_i = 32'h00000110;
        valid_i = 1'b1;

        #1;

        if (valid_alu_o !== 1'b0)
            $fatal(1, "Error: ALU deberia detectar NOP");

        if (valid_lsu_o !== 1'b0)
            $fatal(1, "Error: LSU deberia detectar NOP");

        if (valid_bru_o !== 1'b0)
            $fatal(1, "Error: BRU deberia detectar NOP");

        if (valid_feist_o !== 1'b0)
            $fatal(1, "Error: FEIST deberia detectar NOP");

        // El bundle sigue siendo valido aunque contenga NOP.
        if (valid_o !== 1'b1)
            $fatal(1, "Error: valid_o deberia seguir activo");

        $display("PASS: deteccion de NOP");


        // PRUEBA 4:
        // Compruebo que las salidas sean cero cuando Fetch
        // indica que el bundle no es valido.

        bundle_i = {
            32'h12345671,
            32'hABCDEF05,
            32'h87654322,
            32'hFEDCBA13
        };

        pc_i = 32'h00000120;
        valid_i = 1'b0;

        #1;

        if (instr_alu_o !== 32'b0 ||
            instr_lsu_o !== 32'b0 ||
            instr_bru_o !== 32'b0 ||
            instr_feist_o !== 32'b0)
            $fatal(1, "Error: las instrucciones deberian ser cero");

        if (pc_o !== 32'b0)
            $fatal(1, "Error: el PC deberia ser cero");

        if (valid_o !== 1'b0)
            $fatal(1, "Error: valid_o deberia ser cero");

        if (valid_alu_o !== 1'b0 ||
            valid_lsu_o !== 1'b0 ||
            valid_bru_o !== 1'b0 ||
            valid_feist_o !== 1'b0)
            $fatal(1, "Error: las validez de los slots deberian ser cero");

        $display("PASS: bundle invalido");

        
        $display("========================================");
        $display("Pruebas de DISPATCH Finalizadas: TODAS PASARON");
        $display("========================================");
        $finish;

    end

endmodule
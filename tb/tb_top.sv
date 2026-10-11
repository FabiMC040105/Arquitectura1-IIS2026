`timescale 1ns/1ps

// Prueba de integracion del pipeline completo.
// Comprueba que un bundle recorre las cinco etapas y que el
// resultado del ALU llega al register file en WB.
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

    // Señales auxiliares para depurar la memoria.
    // Solo se necesitan si después las conectamos a señales internas.
    logic [31:0] mem_addr_debug;
    logic [31:0] mem_read_debug;

    top #(
        .IMEM_WORDS(64),
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

    // Construye una instruccion ALU de tipo I.
    // imm[23:12], rs1[11:8], rd[7:4], imm_op[3], opcode[2:0]
    function automatic [31:0] alu_i(
        input [11:0] imm,
        input [3:0]  rs1,
        input [3:0]  rd,
        input [2:0]  opcode
    );
        alu_i = {8'b0, imm, rs1, rd, 1'b1, opcode};
    endfunction

    // Construye una instruccion ALU de tipo R.
    // rs2[15:12], rs1[11:8], rd[7:4], imm_op[3], opcode[2:0]
    function automatic [31:0] alu_r(
        input [3:0] rs2,
        input [3:0] rs1,
        input [3:0] rd,
        input [2:0] opcode
    );
        alu_r = {16'b0, rs2, rs1, rd, 1'b0, opcode};
    endfunction

    localparam ADDI = 3'b001;
    localparam ADD  = 3'b001;

    integer ciclo;

    initial begin
        rst_i   = 1'b1;
        stall_i = 1'b0;

        // 1. El reset deja el PC en su valor inicial.
        @(posedge clk_i);
        #1;

        if (pc_o !== 32'h00000000)
            $fatal(1, "ERROR: PC incorrecto despues del reset");

        $display("PASS: reset deja el PC en 0x0");
        $display("DEBUG: x2 despues de reset = %h", dut.regfile_inst.regs[2]);
        $display("DEBUG: bundle 0 = %h", dut.fetch_inst.instruction_memory_inst.memory[0]);

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

        // 4. Dejamos correr el pipeline hasta que los tres
        //    resultados hayan pasado por WB.
        for (ciclo = 0; ciclo < 12; ciclo = ciclo + 1) begin
            @(posedge clk_i);
        end
        #1;

        // 5. Comprobamos los valores escritos en el register file.
        if (dut.regfile_inst.regs[2] !== 32'd5)
            $fatal(1, "ERROR: x2 = %0d, se esperaba 5",
                   dut.regfile_inst.regs[2]);

        $display("PASS: x2 = 5 escrito en WB");

        if (dut.regfile_inst.regs[3] !== 32'd7)
            $fatal(1, "ERROR: x3 = %0d, se esperaba 7",
                   dut.regfile_inst.regs[3]);

        $display("PASS: x3 = 7 escrito en WB");

        if (dut.regfile_inst.regs[4] !== 32'd12)
            $fatal(1, "ERROR: x4 = %0d, se esperaba 12",
                   dut.regfile_inst.regs[4]);

        $display("PASS: x4 = x2 + x3 = 12 (operandos leidos en RR)");

        // 6. x0 debe seguir siendo cero.
        if (dut.regfile_inst.regs[0] !== 32'd0)
            $fatal(1, "ERROR: x0 fue modificado");

        $display("PASS: x0 permanece en cero");
        if (instr_alu_o !== dut.id_bundle[31:0])
            $fatal(1, "ERROR: el slot ALU no coincide con el bundle recibido");

        if (instr_lsu_o !== dut.id_bundle[63:32])
            $fatal(1, "ERROR: el slot LSU no coincide con el bundle recibido");

        if (instr_bru_o !== dut.id_bundle[95:64])
            $fatal(1, "ERROR: el slot BRU no coincide con el bundle recibido");

        if (instr_feist_o !== dut.id_bundle[127:96])
            $fatal(1, "ERROR: el slot FEIST no coincide con el bundle recibido");
        $display("TODAS LAS PRUEBAS DE TOP PASARON");
        $finish;
    end

endmodule

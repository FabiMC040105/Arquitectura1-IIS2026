
`timescale 1ns/1ps

module tb_bru_conexion;

    logic valid;
    logic [31:0] instr, pc;
    logic [31:0] valor1, valor2;

    wire [3:0] rs1, rs2;
    wire taken, illegal;
    wire [31:0] target;

    // Modulo que conecta decoder + BRU
    bru_conexion dut (
        .valid_i(valid),
        .instr_i(instr),
        .pc_i(pc),
        .src1_value_i(valor1),
        .src2_value_i(valor2),

        .rs1_o(rs1),
        .rs2_o(rs2),

        .branch_taken_o(taken),
        .branch_target_o(target),
        .illegal_o(illegal)
    );

    initial begin

        $dumpfile("bru_conexion.vcd");
        $dumpvars(0, tb_bru_conexion);

        // PRUEBA 1: BEQ x3, x4, +32
        valid = 1'b1;
        instr = 32'h0001021C;
        pc = 32'd256;

        // Valores simulados del Register File
        valor1 = 32'd10;
        valor2 = 32'd10;

        #1;

        if (rs1 !== 4'd3 ||
            rs2 !== 4'd4 ||
            taken !== 1'b1 ||
            target !== 32'd288 ||
            illegal !== 1'b0)
            $fatal(1, "FALLO: BEQ tomado");

        $display("OK 1: BEQ tomado, destino = %0d", target);

        // PRUEBA 2: BEQ con registros diferentes
        valor2 = 32'd20;

        #1;

        if (taken !== 1'b0 ||
            target !== 32'd0)
            $fatal(1, "FALLO: BEQ no tomado");

        $display("OK 2: BEQ no tomado");

        // PRUEBA 3: JMP +32
        valid = 1'b1;
        instr = {9'b0, 20'd32, 3'b001};
        pc = 32'd256;

        #1;

        if (taken !== 1'b1 ||
            target !== 32'd288 ||
            illegal !== 1'b0)
            $fatal(1, "FALLO: JMP");

        $display("OK 3: JMP +32");

        // PRUEBA 4: NOP del dispatcher
        valid = 1'b0;
        instr = 32'd0;

        #1;

        if (taken !== 1'b0 ||
            target !== 32'd0 ||
            illegal !== 1'b0)
            $fatal(1, "FALLO: NOP");

        $display("OK 4: NOP");

        // PRUEBA 5: Opcode ilegal
        valid = 1'b1;
        instr = 32'h00000006;

        #1;

        if (illegal !== 1'b1 ||
            taken !== 1'b0 ||
            target !== 32'd0)
            $fatal(1, "FALLO: Opcode ilegal");

        $display("OK 5: Opcode ilegal");

        $display("PASS: conexion decoder + BRU");
        $finish;

    end

endmodule

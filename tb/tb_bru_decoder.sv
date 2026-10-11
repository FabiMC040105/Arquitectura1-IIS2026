
`timescale 1ns/1ps

module tb_bru_decoder;

    logic valid_i;
    logic [31:0] instr_i;

    wire [2:0] opcode_o;
    wire [3:0] rs1_o, rs2_o;
    wire [31:0] offset_o;
    wire illegal_o;

    integer pruebas = 0;

    bru_decoder dut (
        .valid_i(valid_i),
        .instr_i(instr_i),
        .opcode_o(opcode_o),
        .rs1_o(rs1_o),
        .rs2_o(rs2_o),
        .offset_o(offset_o),
        .illegal_o(illegal_o)
    );

    // Crear una instruccion tipo J
    function automatic [31:0] inst_j(
        input [19:0] offset
    );
        inst_j = {9'b0, offset, 3'b001};
    endfunction

    // Crear una instruccion tipo B
    function automatic [31:0] inst_b(
        input [2:0] op,
        input [3:0] rs1,
        input [3:0] rs2,
        input [11:0] offset
    );
        inst_b = {9'b0, offset, rs2, rs1, op};
    endfunction

    // Verificar las salidas del decoder
    task automatic probar(
        input string nombre,
        input logic valido,
        input logic [31:0] instruccion,
        input logic [2:0] op_esp,
        input logic [3:0] rs1_esp,
        input logic [3:0] rs2_esp,
        input logic [31:0] offset_esp,
        input logic ilegal_esp
    );
        begin
            valid_i = valido;
            instr_i = instruccion;

            #1;

            if (opcode_o !== op_esp ||
                rs1_o !== rs1_esp ||
                rs2_o !== rs2_esp ||
                offset_o !== offset_esp ||
                illegal_o !== ilegal_esp) begin

                $display("FALLO: %s", nombre);

                $display(
                    "Entrada: valid=%b instr=%h",
                    valid_i, instr_i
                );

                $display(
                    "Esperado: op=%b rs1=%0d rs2=%0d offset=%h illegal=%b",
                    op_esp, rs1_esp, rs2_esp,
                    offset_esp, ilegal_esp
                );

                $display(
                    "Obtenido: op=%b rs1=%0d rs2=%0d offset=%h illegal=%b",
                    opcode_o, rs1_o, rs2_o,
                    offset_o, illegal_o
                );

                $fatal(1, "Fallo en decoder BRU");
            end

            pruebas = pruebas + 1;
            $display("OK %0d: %s", pruebas, nombre);
        end
    endtask

    initial begin

        $dumpfile("tb_bru_decoder.vcd");
        $dumpvars(0, tb_bru_decoder);

        valid_i = 0;
        instr_i = 0;

        // NOP: el dispatcher envia valid=0
        probar("NOP con valid=0",
               0, 32'h00000000,
               0, 0, 0, 0, 0);

        probar("NOP bits extra valid=0",
               0, 32'h80000000,
               0, 0, 0, 0, 0);

        probar("NOP otros bits valid=0",
               0, 32'hfffffff8,
               0, 0, 0, 0, 0);

        probar("valid=0 ignora JMP",
               0, inst_j(20'd32),
               0, 0, 0, 0, 0);

        // JMP: offset de 20 bits
        probar("JMP +32",
               1, inst_j(20'd32),
               1, 0, 0, 32'd32, 0);

        probar("JMP -16",
               1, inst_j(20'hffff0),
               1, 0, 0, 32'hfffffff0, 0);

        probar("JMP cero",
               1, inst_j(20'd0),
               1, 0, 0, 32'd0, 0);

        probar("JMP positivo grande",
               1, inst_j(20'h7fff0),
               1, 0, 0, 32'h0007fff0, 0);

        probar("JMP negativo extremo",
               1, inst_j(20'h80000),
               1, 0, 0, 32'hfff80000, 0);

        // Saltos condicionales
        probar("BGE x2,x3,+16",
               1, inst_b(2, 2, 3, 12'd16),
               2, 2, 3, 32'd16, 0);

        probar("BLE x9,x10,-32",
               1, inst_b(3, 9, 10, 12'hfe0),
               3, 9, 10, 32'hffffffe0, 0);

        probar("BEQ x3,x4,+32",
               1, inst_b(4, 3, 4, 12'd32),
               4, 3, 4, 32'd32, 0);

        probar("BNE x3,x4,-16",
               1, inst_b(5, 3, 4, 12'hff0),
               5, 3, 4, 32'hfffffff0, 0);

        probar("BNE x15,x0,+16",
               1, inst_b(5, 15, 0, 12'd16),
               5, 15, 0, 32'd16, 0);

        // Opcodes reservados
        probar("Opcode reservado 110",
               1, 32'h00000006,
               0, 0, 0, 0, 1);

        probar("Opcode reservado 111",
               1, 32'h00000007,
               0, 0, 0, 0, 1);

        // Bits reservados incorrectos
        probar("Bits superiores en B",
               1,
               inst_b(4, 3, 4, 12'd32) | 32'h80000000,
               0, 0, 0, 0, 1);

        probar("Bits superiores en J",
               1,
               inst_j(20'd32) | 32'h40000000,
               0, 0, 0, 0, 1);

        // Volver a NOP
        probar("Vuelta a NOP",
               0, 32'h00000000,
               0, 0, 0, 0, 0);

        // El contrato indica que valid=1 no debe
        // acompañar a un opcode NOP.
        probar("NOP con valid=1 ilegal",
               1, 32'h00000000,
               0, 0, 0, 0, 1);

        probar("NOP datos extra valid=1",
               1, 32'h00000800,
               0, 0, 0, 0, 1);

        probar("Vuelta a JMP",
               1, inst_j(20'd16),
               1, 0, 0, 32'd16, 0);

        probar("Apagar valid al final",
               0, inst_j(20'd16),
               0, 0, 0, 0, 0);

        $display(
            "PASS: %0d pruebas del decoder BRU superadas.",
            pruebas
        );

        $finish;
    end

endmodule

`timescale 1ns/1ps
module tb_bru;
logic [2:0] opcode_i;
    logic [31:0] pc_i;
    logic [31:0] src1_value_i;
    logic [31:0] src2_value_i;
    logic [31:0] imm_i;
wire branch_taken_o;
    wire [31:0] branch_target_o;
    integer pruebas = 0;
bru dut (
        .opcode_i(opcode_i),
        .pc_i(pc_i),
        .src1_value_i(src1_value_i),
        .src2_value_i(src2_value_i),
        .imm_i(imm_i),
        .branch_taken_o(branch_taken_o),
        .branch_target_o(branch_target_o)
    );
task automatic probar(
        input string nombre,
        input logic [2:0] op,
        input logic [31:0] pc,
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] imm,
        input logic esperado_tomado,
        input logic [31:0] esperado_destino
    );
        begin
            opcode_i = op;
            pc_i = pc;
            src1_value_i = a;
            src2_value_i = b;
            imm_i = imm;
            #1;
if (branch_taken_o !== esperado_tomado ||
                branch_target_o !== esperado_destino) begin
                $display("FALLO: %s", nombre);
$display(
                    "Esperado: taken=%b target=%h",
                    esperado_tomado, esperado_destino
                );
$display(
                    "Obtenido: taken=%b target=%h",
                    branch_taken_o, branch_target_o
                );
$fatal(1, "Fallo en BRU EX");
            end
pruebas = pruebas + 1;
            $display("OK %0d: %s", pruebas, nombre);
        end
    endtask
    initial begin
$dumpfile("tb_bru.vcd");
        $dumpvars(0, tb_bru);
opcode_i = 0;
        pc_i = 0;
        src1_value_i = 0;
        src2_value_i = 0;
        imm_i = 0;
probar("NOP",
               0, 256, 0, 0, 32, 0, 0);
probar("JMP +32",
               1, 256, 0, 0, 32, 1, 288);
probar("JMP -16",
               1, 256, 0, 0, 32'hfffffff0, 1, 240);
probar("JMP +0",
               1, 256, 0, 0, 0, 1, 256);
probar("BEQ iguales",
               4, 256, 10, 10, 32, 1, 288);
probar("BEQ distintos",
               4, 256, 10, 20, 32, 0, 0);
probar("BNE distintos",
               5, 256, 10, 20, 32, 1, 288);
probar("BNE iguales",
               5, 256, 10, 10, 32, 0, 0);
probar("BGE mayor",
               2, 256, 7, 3, 16, 1, 272);
probar("BGE menor",
               2, 256, 3, 7, 16, 0, 0);
probar("BGE -1 >= -5",
               2, 256,
               32'hffffffff, 32'hfffffffb,
               16, 1, 272);
probar("BGE -5 >= -1 falso",
               2, 256,
               32'hfffffffb, 32'hffffffff,
               16, 0, 0);
        probar("BLE -5 = 0 falso",
               2, 256, 32'hffffffff, 0,
               16, 0, 0);
probar("Opcode reservado 110",
               6, 256, 0, 0, 16, 0, 0);
probar("Opcode reservado 111",
               7, 256, 0, 0, 16, 0, 0);
probar("JMP overflow 32bit",
               1, 32'hfffffff0, 0, 0,
               32, 1, 32'h00000010);
probar("BEQ offset -32",
               4, 256, 5, 5,
               32'hffffffe0, 1, 224);
probar("BNE offset -16",
               5, 256, 5, 3,
               32'hfffffff0, 1, 240);
$display(
            "PASS: %0d pruebas de BRU EX superadas.",
            pruebas
        );
$finish;
    end
endmodule
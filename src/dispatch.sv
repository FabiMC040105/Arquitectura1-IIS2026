`timescale 1ns/1ps

module dispatch (
    // Entradas provenientes de Fetch.
    input logic [127:0] bundle_i,
    input logic [31:0]  pc_i,
    input logic         valid_i,

    // Instrucciones completas que recibe cada decoder.
    output logic [31:0] instr_alu_o,
    output logic [31:0] instr_lsu_o,
    output logic [31:0] instr_bru_o,
    output logic [31:0] instr_feist_o,

    // PC que se envia a la siguiente etapa.
    output logic [31:0] pc_o,

    // Indican si cada slot contiene una instruccion valida.
    output logic valid_alu_o,
    output logic valid_lsu_o,
    output logic valid_bru_o,
    output logic valid_feist_o,

    // Validez general del bundle para la siguiente etapa.
    output logic valid_o
);

    // Este modulo es combinacional: su funcion es separar el bundle y pasar las instrucciones completas a los decoders correspondientes.
    logic [31:0] bundle_slice_1;
    logic [31:0] bundle_slice_2;
    logic [31:0] bundle_slice_3;
    logic [31:0] bundle_slice_4;

    logic [3:0] opcode_alu;
    logic [1:0] opcode_lsu;
    logic [2:0] opcode_bru;
    logic [2:0] opcode_feist;

    assign bundle_slice_1 = bundle_i[31:0]; 
    assign bundle_slice_2 = bundle_i[63:32]; 
    assign bundle_slice_3 = bundle_i[95:64]; 
    assign bundle_slice_4 = bundle_i[127:96]; 
    assign opcode_alu = bundle_slice_1[3:0];
    assign opcode_lsu = bundle_slice_2[1:0];
    assign opcode_bru = bundle_slice_3[2:0];
    assign opcode_feist = bundle_slice_4[2:0];

    always_comb begin

        // Valores iniciales de las salidas.
        instr_alu_o   = 32'b0;
        instr_lsu_o   = 32'b0;
        instr_bru_o   = 32'b0;
        instr_feist_o = 32'b0;

        pc_o = 32'b0;

        valid_alu_o   = 1'b0;
        valid_lsu_o   = 1'b0;
        valid_bru_o   = 1'b0;
        valid_feist_o = 1'b0;
        valid_o       = 1'b0;

        // Solo se procesa el bundle si Fetch indica que es valido.
        if (valid_i) begin

            // Se separan los slots sin extraer sus campos internos.
            instr_alu_o   = bundle_slice_1;
            instr_lsu_o   = bundle_slice_2;
            instr_bru_o   = bundle_slice_3;
            instr_feist_o = bundle_slice_4;

            // Se conserva el PC del bundle.
            pc_o = pc_i;

            // Se indica que el bundle recibido es valido.
            valid_o = 1'b1;

            // Un opcode en cero representa NOP.
            // Cada unidad tiene su propio ancho de opcode.
            valid_alu_o =
                (opcode_alu != 4'b0000);

            valid_lsu_o =
                (opcode_lsu != 2'b00);

            valid_bru_o =
                (opcode_bru != 3'b000);

            valid_feist_o =
                (opcode_feist != 3'b000);

        end
    end

endmodule
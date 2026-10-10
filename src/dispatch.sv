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
            instr_alu_o   = bundle_i[31:0];
            instr_lsu_o   = bundle_i[63:32];
            instr_bru_o   = bundle_i[95:64];
            instr_feist_o = bundle_i[127:96];

            // Se conserva el PC del bundle.
            pc_o = pc_i;

            // Se indica que el bundle recibido es valido.
            valid_o = 1'b1;

            // Un opcode en cero representa NOP.
            // Cada unidad tiene su propio ancho de opcode.
            valid_alu_o =
                (instr_alu_o[3:0] != 4'b0000);

            valid_lsu_o =
                (instr_lsu_o[1:0] != 2'b00);

            valid_bru_o =
                (instr_bru_o[2:0] != 3'b000);

            valid_feist_o =
                (instr_feist_o[2:0] != 3'b000);

        end
    end

endmodule
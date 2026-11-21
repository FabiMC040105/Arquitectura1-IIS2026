`timescale 1ns/1ps

module bru_decoder (
    input  logic        valid_i,
    input  logic [31:0] instr_i,

    output logic [2:0]  opcode_o,
    output logic [3:0]  rs1_o,
    output logic [3:0]  rs2_o,
    output logic [31:0] offset_o,
    output logic        illegal_o
);

    // Opcodes del ISA BRU
    localparam [2:0] OP_NOP = 3'b000;
    localparam [2:0] OP_JMP = 3'b001;
    localparam [2:0] OP_BGE = 3'b010;
    localparam [2:0] OP_BLE = 3'b011;
    localparam [2:0] OP_BEQ = 3'b100;
    localparam [2:0] OP_BNE = 3'b101;

    always @(*) begin

        // Valores por defecto
        opcode_o  = 3'b000;
        rs1_o     = 4'd0;
        rs2_o     = 4'd0;
        offset_o  = 32'd0;
        illegal_o = 1'b0;

        if (valid_i) begin
            // Los bits reservados deben ser cero
            if (instr_i[31:23] != 9'd0) begin
                illegal_o = 1'b1;
            end

            else begin
                case (instr_i[2:0])
                    // JMP: offset de 20 bits
                    OP_JMP: begin
                        opcode_o = OP_JMP;
                        offset_o = { {12{instr_i[22]}}, instr_i[22:3] };
                    end

                    // Saltos condicionales
                    OP_BGE, OP_BLE, OP_BEQ, OP_BNE: begin
                        opcode_o = instr_i[2:0];
                        rs1_o = instr_i[6:3];
                        rs2_o = instr_i[10:7];
                        offset_o = { {20{instr_i[22]}}, instr_i[22:11] };
                    end

                    default: begin
                        illegal_o = 1'b1;
                    end
                endcase
            end
        end
    end

endmodule

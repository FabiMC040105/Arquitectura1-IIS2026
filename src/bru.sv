
`timescale 1ns/1ps

module bru (
    input  logic [2:0]  opcode_i,
    input  logic [31:0] pc_i,
    input  logic [31:0] src1_value_i,
    input  logic [31:0] src2_value_i,
    input  logic [31:0] imm_i,

    output logic        branch_taken_o,
    output logic [31:0] branch_target_o
);

    // Opcodes del ISA BRU
    localparam [2:0] OP_NOP = 3'b000;
    localparam [2:0] OP_JMP = 3'b001;
    localparam [2:0] OP_BGE = 3'b010;
    localparam [2:0] OP_BLE = 3'b011;
    localparam [2:0] OP_BEQ = 3'b100;
    localparam [2:0] OP_BNE = 3'b101;

    // Logica combinacional de saltos
    always @(*) begin

        // Valores por defecto
        branch_taken_o  = 1'b0;
        branch_target_o = 32'd0;

        case (opcode_i)

            OP_NOP: begin
                // No realiza salto
            end

            OP_JMP: begin
                branch_taken_o = 1'b1;
            end

            OP_BGE: begin
                branch_taken_o =
                    ($signed(src1_value_i) >=
                     $signed(src2_value_i));
            end

            OP_BLE: begin
                branch_taken_o =
                    ($signed(src1_value_i) <=
                     $signed(src2_value_i));
            end

            OP_BEQ: begin
                branch_taken_o =
                    (src1_value_i == src2_value_i);
            end

            OP_BNE: begin
                branch_taken_o =
                    (src1_value_i != src2_value_i);
            end

            default: begin
                // Opcode no reconocido: no salta
            end

        endcase

        // Destino = PC original + offset
        if (branch_taken_o) begin
            branch_target_o = pc_i + imm_i;
        end

    end

endmodule

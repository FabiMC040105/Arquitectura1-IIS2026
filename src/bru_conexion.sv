`timescale 1ns/1ps

module bru_conexion (
    input  logic        valid_i,
    input  logic [31:0] instr_i,
    input  logic [31:0] pc_i,
    input  logic [31:0] src1_value_i,
    input  logic [31:0] src2_value_i,

    output logic [3:0]  rs1_o,
    output logic [3:0]  rs2_o,
    output logic        illegal_o,
    output logic        branch_taken_o,
    output logic [31:0] branch_target_o
);

    // Cables internos
    logic [2:0]  opcode;
    logic [31:0] offset;

    // ID: Decoder BRU
    bru_decoder decoder_inst (
        .valid_i   (valid_i),
        .instr_i   (instr_i),

        .opcode_o  (opcode),
        .rs1_o     (rs1_o),
        .rs2_o     (rs2_o),
        .offset_o  (offset),
        .illegal_o (illegal_o)
    );

    // EX: Unidad BRU
    bru bru_inst (
        .opcode_i        (opcode),
        .pc_i            (pc_i),
        .src1_value_i    (src1_value_i),
        .src2_value_i    (src2_value_i),
        .imm_i           (offset),

        .branch_taken_o  (branch_taken_o),
        .branch_target_o (branch_target_o)
    );

endmodule

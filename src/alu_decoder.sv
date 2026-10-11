`timescale 1ns/1ps

module alu_decoder #(parameter WIDTH = 32) (
  input  logic [WIDTH-1:0] instr_alu_o,

  output logic [3:0]  rd,
  output logic [3:0]  rs1,
  output logic [3:0]  rs2,
  output logic [2:0]  opcode,
  output logic        imm_op,
  output logic [11:0] imm
);

//Evita errores por sensibilidad de bits en compilacion
  logic [2:0] instr_slice_1;
  logic instr_slice_2;
  logic [3:0] instr_slice_3;
  logic [3:0] instr_slice_4;
  logic [3:0] instr_slice_rs2;
  logic [11:0] instr_slice_imm;
  
  assign instr_slice_1 = instr_alu_o[2:0];
  assign instr_slice_2 = instr_alu_o[3];
  assign instr_slice_3 = instr_alu_o[7:4];
  assign instr_slice_4 = instr_alu_o[11:8];
  assign instr_slice_rs2 = instr_alu_o[15:12];
  assign instr_slice_imm = instr_alu_o[23:12];

  assign opcode  = instr_slice_1;
  assign imm_op  = instr_slice_2;
  assign rd      = instr_slice_3;
  assign rs1     = instr_slice_4;

  always_comb begin
    rs2 = '0;
    imm = '0;

    case (imm_op)
      1'b0: rs2 = instr_slice_rs2; 
      1'b1: imm = instr_slice_imm;
    endcase
  end

endmodule
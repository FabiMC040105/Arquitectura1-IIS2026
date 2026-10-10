module alu_decoder #(parameter WIDTH = 32) (
  input  logic [WIDTH-1:0] instr_alu_o,

  output logic [3:0]  rd,
  output logic [3:0]  rs1,
  output logic [3:0]  rs2,
  output logic [2:0]  opcode,
  output logic        imm_op,
  output logic [11:0] imm
);

  assign opcode  = instr_alu_o[2:0];
  assign imm_op  = instr_alu_o[3];
  assign rd      = instr_alu_o[7:4];
  assign rs1     = instr_alu_o[11:8];

  always_comb begin
    rs2 = '0;
    imm = '0;

    case (imm_op)
      1'b0: rs2 = instr_alu_o[15:12]; 
      1'b1: imm = instr_alu_o[23:12];
    endcase
  end

endmodule
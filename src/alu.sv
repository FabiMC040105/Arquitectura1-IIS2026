module alu #(parameter WIDTH = 32) (
  input  logic [WIDTH-1:0] op1, 
  input  logic [WIDTH-1:0] op2,
  input  logic [11:0]      imm,
  input  logic [2:0]       opcode,
  input  logic             imm_op,

  output logic [WIDTH-1:0] data_out,
  output logic             zero
);

  localparam ADD  = 3'b001;
  localparam SUB  = 3'b010;
  localparam OR   = 3'b011;
  localparam XOR  = 3'b100;
  localparam AND  = 3'b101;
  localparam SLT  = 3'b110;
  localparam ADDI = 3'b001;
  localparam SRLI = 3'b010;
  localparam SLLI = 3'b011;

  always_comb begin
    data_out = '0;
    case (imm_op)
      1'b0: begin
        case (opcode)
          ADD:  data_out = $signed(op1) + $signed(op2);
          SUB:  data_out = $signed(op1) - $signed(op2);
          OR:   data_out = op1 | op2;
          XOR:  data_out = op1 ^ op2;
          AND:  data_out = op1 & op2;
          SLT:  data_out = ($signed(op1) < $signed(op2)) ?
                             {{(WIDTH-1){1'b0}}, 1'b1} : '0;
          default: data_out = '0;
        endcase
      end
      1'b1: begin
        case (opcode)
          ADDI: data_out = $signed(op1) + $signed({{20{imm[11]}}, imm});
          SRLI: data_out = op1 >> imm;
          SLLI: data_out = op1 << imm;
          default: data_out = '0;
        endcase
      end
      default: data_out = '0;
    endcase
  end

  assign zero = (data_out == '0);

endmodule
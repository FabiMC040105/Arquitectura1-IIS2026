`timescale 1ns/1ps

module flop_sync (
  input  logic clk_dst, rst, d,
  output logic q
);
  logic m;
  always_ff @(posedge clk_dst or posedge rst)
    if (rst) {q, m} <= 2'b00;
    else     {q, m} <= {m, d};
endmodule
module register_file #(
  parameter WIDTH       = 32,
  parameter DEPTH       = 16,
  parameter N_RD        = 8, // puertos de lectura
  parameter N_WR        = 4 // puertos de escritura
)(
  input  logic                       clk,
  input  logic                       rst,

  input  logic [3:0] rd_addr [N_RD],
  output logic [WIDTH-1:0] rd_data [N_RD],

  input  logic wr_en [N_WR],
  input  logic [3:0]  wr_addr [N_WR],
  input  logic [WIDTH-1:0] wr_data [N_WR]
);
  logic [WIDTH-1:0] regs [DEPTH];

  // x0 esta cableado a cero: leerlo siempre entrega 0 sin importar
  // lo que contenga el arreglo de registros.
  always_comb
    for (int i = 0; i < N_RD; i++)
      rd_data[i] = (rd_addr[i] == 4'd0) ? '0 : regs[rd_addr[i]];

  // Escrituras suceden en flanco positivo
  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      for (int i = 0; i < DEPTH; i++) regs[i] <= '0;
    else
      for (int i = 0; i < N_WR; i++)
        // Las escrituras a x0 se descartan para que nunca cambie de valor.
        if (wr_en[i] && wr_addr[i] != 4'd0) regs[wr_addr[i]] <= wr_data[i];
  end
endmodule
`timescale 1ns/1ps

module register_file #(
    parameter WIDTH = 32,
    parameter DEPTH = 16,
    parameter N_RD = 8,
    parameter N_WR = 4
)(
    input logic clk,
    input logic rst,

    // Puertos de lectura
    input logic [N_RD-1:0][3:0] rd_addr,
    output wire [N_RD-1:0][WIDTH-1:0] rd_data,

    // Puertos de escritura
    input logic [N_WR-1:0] wr_en,
    input logic [N_WR-1:0][3:0] wr_addr,
    input logic [N_WR-1:0][WIDTH-1:0] wr_data
);
    logic [WIDTH-1:0] regs [0:DEPTH-1]; // Los 16 registros del procesador, cada uno de 32 bits

    // Lectura combinacional de los registros
    genvar r;
    generate
        for (r = 0; r < N_RD; r = r + 1) begin : gen_read
            assign rd_data[r] = (rd_addr[r] == 4'd0) ? {WIDTH{1'b0}} : regs[rd_addr[r]];
        end
    endgenerate

    // Escritura de registros en el flanco del reloj positivo y reinicio de todos los registros
    integer i;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < DEPTH; i = i + 1)
                regs[i] <= '0;
        end
        else begin
            for (i = 0; i < N_WR; i = i + 1) begin
                // No se permite modificar x0
                if (wr_en[i] && wr_addr[i] != 4'd0)
                    regs[wr_addr[i]] <= wr_data[i];
            end
        end
    end

endmodule

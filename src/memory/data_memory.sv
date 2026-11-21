`timescale 1ns/1ps

`ifndef DATA_FILE
  `define DATA_FILE "input.mem"
`endif

module data_memory #(
    parameter int MEM_BYTES = 65536, // 65536 bytes = 64 KB por defecto.
    parameter DATA_FILE = `DATA_FILE //Para cargar archivos
)(
    input  logic        clk,
    input  logic        rst,

    input  logic        mem_read,
    input  logic        mem_write,

    input  logic [31:0] addr,
    input  logic [31:0] write_data,

    output logic [31:0] read_data,
    output logic        access_error
);

    // Memoria direccionable por bytes.
    logic [7:0] memory [0:MEM_BYTES-1];

    logic [1:0] byte_direccionable;
    assign byte_direccionable = addr[1:0];

    integer i;

    // Inicialización de memoria
    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1) begin
            memory[i] = 8'h00;
        end

        if (DATA_FILE != "") begin
            $display("Cargando archivo de datos: %s", DATA_FILE);
            $readmemh(DATA_FILE, memory);
        end
    end

    // Escritura en little endian
    always_ff @(posedge clk) begin
        if (rst) begin
            // No es necesario borrar los 64 KB durante cada reset.
        end
        else if (mem_write && !access_error) begin
            memory[addr]     <= write_data[7:0];
            memory[addr + 1] <= write_data[15:8];
            memory[addr + 2] <= write_data[23:16];
            memory[addr + 3] <= write_data[31:24];
        end
    end

    // Lectura (combinacional)
    always_comb begin

        read_data = 32'h00000000;

        if (mem_read && !access_error) begin
            read_data = {
                memory[addr + 3],
                memory[addr + 2],
                memory[addr + 1],
                memory[addr]
            };
        end

    end

    // Verificación de acceso
    always_comb begin
        access_error = 1'b0;

        if (mem_read || mem_write) begin
            // addr no puede apuntar a una posición mayor que MEM_BYTES - 4.
            if ((addr > (MEM_BYTES - 4)) || (byte_direccionable != 2'b00)) begin
                access_error = 1'b1;
            end
        end
    end
endmodule
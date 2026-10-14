`timescale 1ns/1ps

module fetch #(
    parameter integer IMEM_WORDS = 16384, // 16384 palabras * 4 bytes = 65536 bytes = 64 KiB.
    parameter PROGRAM_FILE = "program_test.mem"
) (
    input logic [31:0] pc_i,
    output logic [127:0] bundle_o,
    output logic valid_o,// Indica si la dirección permite leer un bundle válido.
    output logic access_error_o // Indica si la dirección solicitada es inválida.
);

    localparam integer MEM_BYTES = IMEM_WORDS * 4;

    logic access_error;

    // Memoria de instrucciones.
    instruction_memory #(
        .MEM_BYTES(MEM_BYTES),
        .PROGRAM_FILE(PROGRAM_FILE)
    ) instruction_memory_inst (
        .addr(pc_i),
        .bundle_out(bundle_o),
        .access_error(access_error)
    );

    // La memoria determina si la dirección es válida.
    // Un bundle compuesto solamente por NOP también es válido.
    always_comb begin
        access_error_o = access_error;
        valid_o = !access_error;
    end

endmodule
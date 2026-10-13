`timescale 1ns/1ps

module fetch #(
    // Capacidad de la memoria expresada en palabras de 32 bits.
    // 16384 palabras * 4 bytes = 65536 bytes = 64 KiB.
    parameter integer IMEM_WORDS = 16384,

    // Archivo que contiene los bundles de instrucciones.
    parameter PROGRAM_FILE = "program_test.mem"
) (
    // PC controlado por pipeline_control.
    input logic [31:0] pc_i,

    // Bundle leído desde la memoria de instrucciones.
    output logic [127:0] bundle_o,

    // Indica si la dirección permite leer un bundle válido.
    output logic valid_o,

    // Indica si la dirección solicitada es inválida.
    output logic access_error_o
);

    // Capacidad total de la memoria en bytes.
    localparam integer MEM_BYTES = IMEM_WORDS * 4;

    // Error interno de acceso a memoria.
    logic access_error;

    // Memoria de instrucciones.
    // Cada bundle contiene cuatro slots de 32 bits:
    // [127:96] = CRYPTO
    // [95:64]  = BRU
    // [63:32]  = LSU
    // [31:0]   = ALU

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
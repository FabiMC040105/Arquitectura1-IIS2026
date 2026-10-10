`timescale 1ns/1ps

module fetch #(
    // Capacidad de la memoria expresada en palabras de 32 bits.
    // 16384 palabras * 4 bytes = 65536 bytes = 64 KiB.
    parameter integer IMEM_WORDS = 16384,

    // Archivo que contiene los bundles de instrucciones.
    parameter PROGRAM_FILE = "program.mem"
) (
    // Dirección del bundle a leer.
    // El PC lo mantiene pipeline_control, no Fetch, para que
    // exista un unico registro de PC en todo el procesador.
    input  logic [31:0]  pc_i,

    // Bundle leído y su validez.
    output logic [127:0] bundle_o,
    output logic         valid_o
);

    // Capacidad total de la memoria en bytes.
    localparam integer MEM_BYTES = IMEM_WORDS * 4;

    // Indica si la dirección solicitada es inválida.
    logic access_error;

    // ============================================================
    // Memoria de instrucciones
    // ============================================================

    // Cada bundle contiene:
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

    // El bundle es válido si la dirección está alineada y se encuentra dentro del rango de la memoria.
 
    // Un bundle que contiene únicamente instrucciones NOP también puede ser válido.
    always_comb begin
        valid_o = !access_error;
    end

endmodule
`timescale 1ns/1ps

module fetch #(
    // Capacidad de la memoria expresada en palabras de 32 bits.
    // 16384 palabras * 4 bytes = 65536 bytes = 64 KiB.
    parameter integer IMEM_WORDS = 16384,

    // Dirección donde comienza la ejecución.
    parameter logic [31:0] RESET_PC = 32'h00000000,

    // Archivo que contiene los bundles de instrucciones.
    parameter PROGRAM_FILE = "program.mem"
) (
    input  logic         clk_i,
    input  logic         rst_i,
    input  logic         stall_i,

    // Señales para cambiar el PC cuando ocurre un salto.
    input  logic         redirect_i,
    input  logic [31:0]  redirect_pc_i,

    // Dirección del bundle actual y bundle leído.
    output logic [31:0]  pc_o,
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
        .addr(pc_o),
        .bundle_out(bundle_o),
        .access_error(access_error)
    );

    // El bundle es válido si la dirección está alineada y se encuentra dentro del rango de la memoria.
 
    // Un bundle que contiene únicamente instrucciones NOP también puede ser válido.
    always_comb begin
        valid_o = !access_error;
    end

    // ============================================================
    // Actualización del contador de programa (PC)
    // ============================================================

    always_ff @(posedge clk_i) begin

        // Al reiniciar, volvemos a la dirección inicial.
        if (rst_i) begin
            pc_o <= RESET_PC;
        end

        // Los saltos tienen prioridad sobre stall.
        else if (redirect_i) begin
            pc_o <= redirect_pc_i;
        end

        // Cada bundle ocupa 16 bytes.
        else if (!stall_i) begin
            pc_o <= pc_o + 32'd16;
        end

        // Si stall_i es 1 y no hay salto, el PC conserva su valor anterior.
    end

endmodule
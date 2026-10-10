`timescale 1ns/1ps

module fetch #(
    // Cantidad de palabras de 32 bits que tiene la memoria.
    // 16384 palabras * 4 bytes = 64 KiB.
    parameter integer IMEM_WORDS = 16384,

    // Direccion donde empieza la ejecucion.
    // El PC trabaja con direcciones en bytes.
    parameter logic [31:0] RESET_PC = 32'h00000000
) (
    input  logic         clk_i,          // Reloj
    input  logic         rst_i,          // Reinicio
    input  logic         stall_i,        // Detener el avance del PC

    // Señales para cambiar el PC cuando ocurre un salto.
    input  logic         redirect_i,
    input  logic [31:0]  redirect_pc_i,

    // Direccion del bundle actual y bundle leido.
    output logic [31:0]  pc_o,
    output logic [127:0] bundle_o,
    output logic         valid_o
);

    // Memoria de instrucciones.
    // Cada posicion guarda una palabra de 32 bits.
    logic [31:0] imem [0:IMEM_WORDS-1];

    // Indice de la primera palabra que corresponde al PC actual.
    integer word_index;

    // Carga inicial de instrucciones desde un archivo hexadecimal.
    // La primera linea se guarda en imem[0], la segunda en imem[1], etc.
    initial begin
        $readmemh("instructions.hex", imem);
    end

    // Parte combinacional: leer la memoria y formar el bundle.
    // No necesita esperar a un flanco de reloj.
    always_comb begin
        // Valores por defecto para evitar valores sin definir.
        bundle_o  = 128'b0;
        valid_o   = 1'b0;
        word_index = 0;

        // El PC debe estar alineado a 16 bytes,
        // porque cada bundle ocupa 16 bytes.
        if (pc_o[3:0] == 4'b0000) begin

            // Convertimos la direccion en un indice de palabra.
            // Restamos RESET_PC porque la memoria comienza en esa base.
            // Dividir entre 4 equivale a desplazar dos bits a la derecha.
            if (pc_o >= RESET_PC) begin
                word_index = (pc_o - RESET_PC) >> 2;

                // Verificamos que existan las cuatro palabras del bundle.
                if ((word_index >= 0) &&
                    (word_index + 3 < IMEM_WORDS)) begin

                    // Unimos cuatro palabras de 32 bits.
                    // La palabra de menor direccion va en los bits bajos.
                    bundle_o = {
                        imem[word_index + 3], // Slot Crypto
                        imem[word_index + 2], // Slot BRU
                        imem[word_index + 1], // Slot LSU
                        imem[word_index]      // Slot ALU
                    };

                    // La memoria contiene las cuatro palabras necesarias.
                    valid_o = 1'b1;
                end
            end
        end
    end

    // Parte secuencial: actualizar el PC usando el reloj.
    always_ff @(posedge clk_i) begin

        // Al reiniciar, volvemos a la direccion inicial.
        if (rst_i) begin
            pc_o <= RESET_PC;
        end

        // Si hay un salto, usamos la direccion nueva.
        // La redireccion tiene prioridad sobre stall.
        else if (redirect_i) begin
            pc_o <= redirect_pc_i;
        end

        // Si no hay salto ni stall, avanzamos al siguiente bundle.
        else if (!stall_i) begin
            pc_o <= pc_o + 32'd16;
        end

        // Si stall_i es 1, no asignamos un valor nuevo al PC.
        // Por lo tanto, conserva su valor anterior.
    end

endmodule
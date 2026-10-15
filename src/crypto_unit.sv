`timescale 1ns/1ps

module crypto_unit (
    // Control de la operación
    input logic fround_en,
    input logic mode_decrypt,  // 0 = cifrar, 1 = descifrar

    // Datos de entrada: las dos mitades del mensaje
    input logic [31:0] l_in,
    input logic [31:0] r_in,
    input logic [31:0] subkey_in, // Subllave recibida internamente desde key_vault
    input logic subkey_valid,  // Indica si la bóveda autorizó su uso

    // Resultados de la ronda Feistel
    output logic [31:0] l_out,
    output logic [31:0] r_out,

    // Señales de resultado
    output logic result_valid, 
    output logic access_error
);
    // Variables internas para los cálculos de Feistel
    logic [31:0] feistel_input;
    logic [31:0] rot5;
    logic [31:0] rot13;
    logic [31:0] f_result;

    // calcula una ronda Feistel
    always_comb begin
        // Seleccionar qué mitad se utiliza en la función F
        if (mode_decrypt)
            feistel_input = l_in;
        else
            feistel_input = r_in;
        
        rot5 = (feistel_input << 5) | (feistel_input >> 27); // Rotar 5 bits hacia la izquierda
        rot13 = (feistel_input << 13) | (feistel_input >> 19); // Rotar 13 bits hacia la izquierda
        f_result = (rot5 + subkey_in) ^ rot13; // Suma modular de 32 bits y operación XOR

        // Valores por defecto de las salidas
        l_out = 32'b0;
        r_out = 32'b0;
        result_valid = 1'b0;
        access_error = 1'b0;

        // Ejecutar únicamente si existe autorización
        if (fround_en) begin
            if (subkey_valid) begin

                result_valid = 1'b1;

                // Modo cifrado
                if (!mode_decrypt) begin
                    l_out = r_in;
                    r_out = l_in ^ f_result;
                end

                // Modo descifrado
                else begin
                    l_out = r_in ^ f_result;
                    r_out = l_in;
                end
            end
            else begin
                // No realizar la ronda sin autorización
                access_error = 1'b1;
            end

        end
    end

endmodule

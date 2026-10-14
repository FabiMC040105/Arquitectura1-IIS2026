`timescale 1ns/1ps

module key_vault (
    input logic clk,
    input logic reset,

    // Señales que indican qué operación queremos realizar
    input logic auth_en,   // Solicita autenticación (AUTH)
    input logic logout_en, // Cierra la autorización (LOGOUT)
    input logic kstore_en, // Solicita guardar una subllave (KSTORE)
    input logic fround_en, // Solicita utilizar una subllave (FROUND)

    // Datos utilizados para comprobar la autenticación
    input logic [31:0] auth_rs1,
    input logic [31:0] auth_rs2,

    // Datos necesarios para seleccionar una subllave
    input logic [1:0] key_sel,
    input logic [1:0] round_sel,
    input logic [31:0] subkey_in,

    // Estado de la bóveda
    output logic authorized,
    output logic access_error,

    // Conexión interna hacia la unidad criptográfica
    output logic [31:0] subkey_out, 
    output logic subkey_valid // Indica si puede utilizarse
);

    // Credenciales provisionales para probar la autenticación
    localparam logic [31:0] AUTH_ID = 32'hC0DE1234;
    localparam logic [31:0] AUTH_PASS = 32'hABCD5678;

    // Almacenamiento de 4 llaves de 128 bits. Cada llave tiene 4 subllaves de 32 bits
    logic [31:0] subkeys [0:3][0:3];

    integer i, j;

    // Solo permite entregar una subllave a FROUND cuando la bóveda está autorizada.
    assign subkey_valid = fround_en && authorized && !auth_en && !logout_en && !kstore_en;

    // Entregar la subllave seleccionada o cero si no existe una solicitud válida y autorizada.
    assign subkey_out = subkey_valid ? subkeys[key_sel][round_sel] : 32'b0;


    always_ff @(posedge clk or posedge reset) begin 
        if (reset) begin
            authorized <= 1'b0;
            access_error <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin
                for (j = 0; j < 4; j = j + 1) begin
                    subkeys[i][j] <= 32'b0; //Recorren las 4 llaves y sus 4 subllaves
                end
            end
        end

        else begin

            access_error <= 1'b0;// Limpiamos el error al iniciar cada ciclo de reloj

            // LOGOUT: elimina la autorización actual
            if (logout_en) begin
                authorized <= 1'b0;
            end

            // AUTH: comprueba si las credenciales son correctas
            else if (auth_en) begin
                if (auth_rs1 == AUTH_ID && auth_rs2 == AUTH_PASS) begin
                    authorized <= 1'b1;
                end
                else begin
                    authorized <= 1'b0;
                    access_error <= 1'b1;
                end
            end

            // KSTORE: guarda una subllave en la bóveda
            else if (kstore_en) begin
                if (authorized) begin
                    subkeys[key_sel][round_sel] <= subkey_in;
                end
                else begin
                    access_error <= 1'b1;
                end
            end

            // FROUND sin autorización genera un error
            else if (fround_en && !authorized) begin
                access_error <= 1'b1;
            end
        end
    end

endmodule

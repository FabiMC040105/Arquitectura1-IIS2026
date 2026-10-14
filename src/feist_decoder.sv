`timescale 1ns/1ps

module feist_decoder (
    // Instrucción recibida del dispatcher general
    input logic [31:0] instr_feist_i,
    input logic valid_feist_i,

    // Señales para seleccionar la operación
    output logic auth_en,
    output logic logout_en,
    output logic kstore_en,
    output logic fround_en,

    // Indica si recibimos una instrucción desconocida
    output logic illegal_opcode,

    // Registros utilizados por AUTH
    output logic [3:0] auth_rs1_o,
    output logic [3:0] auth_rs2_o,

    // Registro fuente utilizado por KSTORE
    output logic [3:0] kstore_rs1_o,

    // Registros utilizados por FROUND
    output logic [3:0] rdL_o,
    output logic [3:0] rdR_o,
    output logic [3:0] rsL_o,
    output logic [3:0] rsR_o,

    // Selección de llave, ronda y modo
    output logic [1:0] key_o,
    output logic [1:0] round_o,
    output logic mode_o
);
    logic [2:0] opcode;

    assign opcode = instr_feist_i[2:0];

    // Opcodes del slot FEIST
    localparam logic [2:0] NOP   = 3'b000;
    localparam logic [2:0] AUTH  = 3'b001; // identificar registros de credenciales
    localparam logic [2:0] LOGOUT = 3'b010; // eliminar autorización
    localparam logic [2:0] KSTORE = 3'b011; // identificar qué subllave guardar
    localparam logic [2:0] FROUND = 3'b100; // extraer los operandos

    // Decodificar la instrucción recibida
    always @(*) begin

        // Por defecto no ejecutamos ninguna operación
        auth_en = 1'b0;
        logout_en = 1'b0;
        kstore_en = 1'b0;
        fround_en = 1'b0;
        illegal_opcode = 1'b0;

        // Inicializar los campos de los registros
        auth_rs1_o = 4'b0;
        auth_rs2_o = 4'b0;
        kstore_rs1_o = 4'b0;

        rdL_o = 4'b0;
        rdR_o = 4'b0;
        rsL_o = 4'b0;
        rsR_o = 4'b0;

        key_o = 2'b0;
        round_o = 2'b0;
        mode_o = 1'b0;

        // Solo procesar instrucciones válidas
        if (valid_feist_i) begin

            case (opcode)

                // NOP
                3'b000: begin
                end

                AUTH: begin
                    auth_en = 1'b1;
                    auth_rs1_o = instr_feist_i[6:3];
                    auth_rs2_o = instr_feist_i[10:7];
                end

                LOGOUT: begin
                    logout_en = 1'b1;
                end

                KSTORE: begin
                    kstore_en = 1'b1;
                    kstore_rs1_o = instr_feist_i[6:3];
                    round_o = instr_feist_i[8:7];
                    key_o = instr_feist_i[10:9];
                end

                FROUND: begin
                    fround_en = 1'b1;

                    rdL_o = instr_feist_i[23:20];
                    rdR_o = instr_feist_i[19:16];

                    rsL_o = instr_feist_i[15:12];
                    rsR_o = instr_feist_i[11:8];

                    key_o = instr_feist_i[7:6];
                    round_o = instr_feist_i[5:4];
                    mode_o = instr_feist_i[3];
                end

                // Instrucción desconocida
                default: begin
                    illegal_opcode = 1'b1;
                end

            endcase
        end
    end

endmodule

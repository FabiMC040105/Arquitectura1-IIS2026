`timescale 1ns/1ps

// Modulo principal del procesador.
// Por ahora integra solamente Fetch y Dispatch.
// Las demas unidades se conectaran cuando sus interfaces esten definidas.
module top #(
    parameter integer IMEM_WORDS = 16384,
    parameter logic [31:0] RESET_PC = 32'h00000000,
    parameter PROGRAM_FILE = "program.mem"
) (

    // ---------------------------------------------------------
    // ENTRADAS DE RELOJ Y CONTROL
    // ---------------------------------------------------------

    input logic clk_i,          // Reloj del procesador
    input logic rst_i,          // Reinicio del procesador
    input logic stall_i,        // Detiene el avance del PC en Fetch
    input logic redirect_i,     // Solicita redirigir la ejecucion
    input logic [31:0] redirect_pc_i, // Direccion destino de la redireccion

    // ---------------------------------------------------------
    // SALIDAS DE FETCH
    // ---------------------------------------------------------

    // Direccion del bundle que Dispatch recibe.
    // Proviene de la salida PC de Dispatch, conectada al PC de Fetch.
    output logic [31:0] pc_o,

    // Bundle completo de 128 bits que sale de Fetch.
    // Contiene cuatro slots de 32 bits.
    output logic [127:0] bundle_o,

    // Indica si Fetch esta entregando un bundle valido.
    output logic fetch_valid_o,

    // ---------------------------------------------------------
    // INSTRUCCIONES SEPARADAS POR DISPATCH
    // ---------------------------------------------------------

    // Instruccion de 32 bits destinada al slot ALU.
    output logic [31:0] instr_alu_o,

    // Instruccion destinada al slot de acceso a memoria.
    output logic [31:0] instr_lsu_o,

    // Instruccion destinada al slot de control de flujo.
    output logic [31:0] instr_bru_o,

    // Instruccion destinada al slot criptografico Feistel4.
    output logic [31:0] instr_feist_o,

    // ---------------------------------------------------------
    // INDICADORES DE VALIDEZ DE LOS SLOTS
    // ---------------------------------------------------------

    // Indica si el slot correspondiente contiene una operacion
    // distinta de NOP dentro de un bundle valido.
    output logic valid_alu_o,
    output logic valid_lsu_o,
    output logic valid_bru_o,
    output logic valid_feist_o,

    // Indica que Dispatch recibio un bundle valido.
    // Puede valer 1 aunque todos los slots sean NOP.
    output logic dispatch_valid_o
);

    // ---------------------------------------------------------
    // SENALES INTERNAS ENTRE FETCH Y DISPATCH
    // ---------------------------------------------------------

    // PC que mantiene Fetch.
    // Es interno porque no necesitamos exponer todas las
    // senales internas del modulo.
    logic [31:0] fetch_pc;

    // Bundle completo que Fetch obtiene de la memoria.
    logic [127:0] fetch_bundle;

    // Validez del bundle generado por Fetch.
    logic fetch_valid;


    // ---------------------------------------------------------
    // SENALES DEL REGISTER FILE
    // ---------------------------------------------------------

    // Puertos de lectura (8 total para soportar 4 unidades ejecutivas)
    logic [3:0] regfile_rd_addr [8];
    logic [31:0] regfile_rd_data [8];

    // Puertos de escritura (4 total, uno por unidad ejecutiva)
    logic [3:0] regfile_wr_addr [4];
    logic [31:0] regfile_wr_data [4];
    logic regfile_wr_en [4];


    // ---------------------------------------------------------
    // INSTANCIA DE FETCH
    // ---------------------------------------------------------

    // Crea una instancia del modulo definido en fetch.sv.
    // Los parametros se pasan desde top para permitir
    // configurar el tamano de memoria y la direccion inicial.
    fetch #(
        .IMEM_WORDS(IMEM_WORDS),
        .RESET_PC(RESET_PC),
        .PROGRAM_FILE(PROGRAM_FILE)
    ) fetch_inst (

        // Entradas de reloj y control.
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_i),
        .redirect_i(redirect_i),
        .redirect_pc_i(redirect_pc_i),

        // Salidas de Fetch conectadas a senales internas.
        .pc_o(fetch_pc),
        .bundle_o(fetch_bundle),
        .valid_o(fetch_valid)
    );


    // ---------------------------------------------------------
    // INSTANCIA DE DISPATCH
    // ---------------------------------------------------------

    // Recibe el bundle completo y lo separa en sus cuatro slots.
    // Dispatch no ejecuta las instrucciones: solamente las
    // separa y genera las senales de validez correspondientes.
    dispatch dispatch_inst (

        // Entradas provenientes de Fetch.
        .bundle_i(fetch_bundle),
        .pc_i(fetch_pc),
        .valid_i(fetch_valid),

        // Instrucciones completas, una por slot.
        .instr_alu_o(instr_alu_o),
        .instr_lsu_o(instr_lsu_o),
        .instr_bru_o(instr_bru_o),
        .instr_feist_o(instr_feist_o),

        // PC asociado al bundle recibido.
        .pc_o(pc_o),

        // Validez de cada slot y del bundle completo.
        .valid_alu_o(valid_alu_o),
        .valid_lsu_o(valid_lsu_o),
        .valid_bru_o(valid_bru_o),
        .valid_feist_o(valid_feist_o),
        .valid_o(dispatch_valid_o)
    );


    // ---------------------------------------------------------
    // INSTANCIA DEL REGISTER FILE
    // ---------------------------------------------------------

    register_file #(
        .WIDTH(32),
        .DEPTH(16),
        .N_RD(8),
        .N_WR(4)
    ) regfile_inst (
        .clk(clk_i),
        .rst(rst_i),

        // Puertos de lectura
        .rd_addr(regfile_rd_addr),
        .rd_data(regfile_rd_data),

        // Puertos de escritura
        .wr_en(regfile_wr_en),
        .wr_addr(regfile_wr_addr),
        .wr_data(regfile_wr_data)
    );


    // ---------------------------------------------------------
    // SALIDAS DE OBSERVACION
    // ---------------------------------------------------------

    // Permite observar desde el exterior el bundle que Fetch
    // esta entregando. No modifica el bundle.
    assign bundle_o = fetch_bundle;

    // Permite observar directamente la validez de Fetch.
    assign fetch_valid_o = fetch_valid;

endmodule
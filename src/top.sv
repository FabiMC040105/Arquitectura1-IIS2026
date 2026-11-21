`timescale 1ns/1ps

// Programa y datos por defecto. Se sobreescriben al compilar con
//   iverilog -DPROGRAM_FILE=\"salida_compilador.mem\" -DDATA_FILE=\"datos.mem\"
`ifndef PROGRAM_FILE
  `define PROGRAM_FILE "program_test.mem"
`endif
`ifndef DATA_FILE
  `define DATA_FILE "data.mem"
`endif

// Modulo principal del procesador VLIW. Integra el pipeline completo de cinco etapas:
//   IF  : Fetch lee el bundle apuntado por el PC.
//   ID  : Dispatch separa el bundle y los decoders extraen campos.
//   RR  : Lectura de operandos del register file.
//   EX  : ALU, LSU y BRU operan sobre los operandos.
//   WB  : Escritura de resultados al register file.
//
// El PC vive unicamente en pipeline_control, que tambien genera los enable y flush de los registros que separan cada etapa.
module top #(
    parameter integer IMEM_WORDS = 16384,
    parameter logic [31:0] RESET_PC = 32'h00000000,
    parameter PROGRAM_FILE = `PROGRAM_FILE,
    parameter DATA_FILE = `DATA_FILE,

    // 0: usa data_memory interna del Proyecto 1.
    // 1: el LSU utiliza una interfaz externa de cache de datos.
    parameter bit CACHE_IF_EN = 1'b0
) (
    input logic clk_i,          // Reloj del procesador
    input logic clk_mem_i,
    input logic rst_i,          // Reinicio del procesador
    input logic stall_i,        // Stall externo de prueba/control

    // Interfaz LSU <-> cache de datos. Solo se utiliza cuando
    // CACHE_IF_EN = 1. Coincide con la interfaz CPU de l1_data_system.
    input  logic        cache_ready_i,
    input  logic        cache_stall_i,
    input  logic [31:0] cache_read_data_i,

    output logic        cache_read_o,
    output logic        cache_write_o,
    output logic [31:0] cache_addr_o,
    output logic [31:0] cache_write_data_o,
    output logic        global_stall_o,

    output logic [31:0] pc_o, // Direccion del bundle que Fetch lee.
    output logic [127:0] bundle_o, // Bundle completo de 128 bits que sale de Fetch.
    output logic fetch_valid_o, // Indica si Fetch esta entregando un bundle valido.

    output logic [31:0] instr_alu_o,
    output logic [31:0] instr_lsu_o,
    output logic [31:0] instr_bru_o,
    output logic [31:0] instr_feist_o,

    // Indica si el slot correspondiente contiene una operacion distinta de NOP dentro de un bundle valido.
    output logic valid_alu_o,
    output logic valid_lsu_o,
    output logic valid_bru_o,
    output logic valid_feist_o,

    // Indica que Dispatch recibio un bundle valido. Puede valer 1 aunque todos los slots sean NOP.
    output logic dispatch_valid_o
);
    // =========================================================
    // ANCHOS DE LOS REGISTROS DE PIPELINE
    // =========================================================

    localparam integer W_IF_ID = 128 + 32; // IF/ID transporta el bundle completo y su PC.

    // ID/RR transporta los campos ya decodificados de las cuatro unidades, mas el PC y las validez de cada slot.
    //   PC                                      32
    //   ALU   : rd, rs1, rs2, opcode, imm_op, imm, valid
    //           4 + 4 + 4 + 3 + 1 + 12 + 1   =  29
    //   LSU   : base, data, offset, load, store, reg_write, valid
    //           4 + 4 + 12 + 1 + 1 + 1 + 1   =  24
    //   BRU   : opcode, rs1, rs2, offset, valid
    //           3 + 4 + 4 + 32 + 1           =  44
    //   FEIST : auth_en, logout_en, kstore_en, fround_en,
    //           auth_rs1, auth_rs2, kstore_rs1,
    //           rdL, rdR, rsL, rsR, key, round, mode, valid
    //           4 + 12 + 16 + 2 + 2 + 1 + 1  =  38
    localparam integer W_ID_RR = 32 + 29 + 24 + 44 + 38;

    // RR/EX transporta lo mismo que ID/RR salvo los indices de registro fuente, que se sustituyen por los valores leidos.
    //   PC                                      32
    //   ALU   : op1, op2, rd, opcode, imm_op, imm, valid
    //           32 + 32 + 4 + 3 + 1 + 12 + 1 =  85
    //   LSU   : base_addr, store_data, data_reg, offset,
    //           load, store, reg_write, valid
    //           32 + 32 + 4 + 12 + 1 + 1 + 1 + 1 = 84
    //   BRU   : opcode, src1, src2, offset, valid
    //           3 + 32 + 32 + 32 + 1         = 100
    //   FEIST : los indices de fuente se sustituyen por sus valores.
    //           auth_en, logout_en, kstore_en, fround_en,
    //           auth_val1, auth_val2, kstore_val, l_in, r_in,
    //           rdL, rdR, key, round, mode, valid
    //           4 + 160 + 8 + 2 + 2 + 1 + 1  = 178
    localparam integer W_RR_EX = 32 + 85 + 84 + 100 + 178;

    // EX/WB transporta los resultados a escribir.
    //   PC                                      32
    //   ALU   : resultado, rd, write_enable
    //           32 + 4 + 1                   =  37
    //   LSU   : dato leido, rd, write_enable
    //           32 + 4 + 1                   =  37
    //   FEIST : l_out, r_out, rdL, rdR, write_enable
    //           32 + 32 + 4 + 4 + 1          =  73
    localparam integer W_EX_WB = 32 + 37 + 37 + 73;

    localparam logic [3:0] PC_REG = 4'd1; // x1 es el PC. No se almacena en el register file: leerlo entrega el PC del bundle que lo lee y escribirlo redirige el PC.

    // =========================================================
    // ETAPA IF
    // =========================================================
    logic [31:0] if_pc; // PC que mantiene pipeline_control y que consume Fetch. Es el unico registro de PC del procesador.
    logic [127:0] if_bundle; // Bundle completo que Fetch obtiene de la memoria.
    logic if_valid; // Validez del bundle generado por Fetch.
    logic if_access_error; // Validez del error

    // ---------------------------------------------------------
    // SENALES DE PIPELINE CONTROL
    // ---------------------------------------------------------
    // Enables de los registros del pipeline.
    logic enable_if_id;
    logic enable_id_rr;
    logic enable_rr_ex;
    logic enable_ex_wb;

    // Flush de los registros del pipeline.
    logic flush_if_id;
    logic flush_id_rr;
    logic flush_rr_ex;
    logic flush_ex_wb;

    // Stall generado por la jerarquia de cache y stall efectivo
    // aplicado a todo el procesador.
    logic cache_stall;
    logic global_stall;


    // =========================================================
    // ETAPA ID
    // =========================================================
    // Contenido empaquetado que entra y sale del registro IF/ID.
    logic [W_IF_ID-1:0] if_id_data_in;
    logic [W_IF_ID-1:0] if_id_data_out;
    logic               if_id_valid_out;
    logic               valid_opcodes;

    // Campos desempaquetados a la entrada de ID.
    logic [127:0] id_bundle;
    logic [31:0]  id_pc;

    // Salidas de Dispatch.
    logic [31:0] id_instr_alu;
    logic [31:0] id_instr_lsu;
    logic [31:0] id_instr_bru;
    logic [31:0] id_instr_feist;
    logic        id_valid_alu;
    logic        id_valid_lsu;
    logic        id_valid_bru;
    logic        id_valid_feist;
    logic        id_valid;
    logic [31:0] id_dispatch_pc;

    // Campos extraidos por el decoder del ALU.
    logic [3:0]  id_alu_rd;
    logic [3:0]  id_alu_rs1;
    logic [3:0]  id_alu_rs2;
    logic [2:0]  id_alu_opcode;
    logic        id_alu_imm_op;
    logic [11:0] id_alu_imm;
    logic        id_alu_illegal_instr;

    // Campos extraidos por el decoder del LSU.
    logic [3:0]  id_lsu_base_reg_idx;
    logic [3:0]  id_lsu_data_reg_idx;
    logic [11:0] id_lsu_offset;
    logic        id_lsu_load_enable;
    logic        id_lsu_store_enable;
    logic        id_lsu_reg_write;
    logic        id_lsu_nop;
    logic        id_lsu_illegal_instr;

    // Campos extraidos por el decoder del BRU.
    logic [2:0]  id_bru_opcode;
    logic [3:0]  id_bru_rs1;
    logic [3:0]  id_bru_rs2;
    logic [31:0] id_bru_offset;
    logic        id_bru_illegal_instr;

    // Campos extraidos por el decoder de la unidad Feistel.
    logic        id_feist_auth_en;
    logic        id_feist_logout_en;
    logic        id_feist_kstore_en;
    logic        id_feist_fround_en;
    logic [3:0]  id_feist_auth_rs1;
    logic [3:0]  id_feist_auth_rs2;
    logic [3:0]  id_feist_kstore_rs1;
    logic [3:0]  id_feist_rdL;
    logic [3:0]  id_feist_rdR;
    logic [3:0]  id_feist_rsL;
    logic [3:0]  id_feist_rsR;
    logic [1:0]  id_feist_key;
    logic [1:0]  id_feist_round;
    logic        id_feist_mode;
    logic        id_feist_illegal_opcode;


    // =========================================================
    // ETAPA RR
    // =========================================================
    // Contenido empaquetado que entra y sale del registro ID/RR.
    logic [W_ID_RR-1:0] id_rr_data_in;
    logic [W_ID_RR-1:0] id_rr_data_out;
    logic               id_rr_valid_out;

    // Campos desempaquetados en RR.
    logic [31:0] rr_pc;

    logic [3:0]  rr_alu_rd;
    logic [3:0]  rr_alu_rs1;
    logic [3:0]  rr_alu_rs2;
    logic [2:0]  rr_alu_opcode;
    logic        rr_alu_imm_op;
    logic [11:0] rr_alu_imm;
    logic        rr_alu_valid;

    logic [3:0]  rr_lsu_base_reg_idx;
    logic [3:0]  rr_lsu_data_reg_idx;
    logic [11:0] rr_lsu_offset;
    logic        rr_lsu_load_enable;
    logic        rr_lsu_store_enable;
    logic        rr_lsu_reg_write;
    logic        rr_lsu_valid;

    logic [2:0]  rr_bru_opcode;
    logic [3:0]  rr_bru_rs1;
    logic [3:0]  rr_bru_rs2;
    logic [31:0] rr_bru_offset;
    logic        rr_bru_valid;

    logic        rr_feist_auth_en;
    logic        rr_feist_logout_en;
    logic        rr_feist_kstore_en;
    logic        rr_feist_fround_en;
    logic [3:0]  rr_feist_auth_rs1;
    logic [3:0]  rr_feist_auth_rs2;
    logic [3:0]  rr_feist_kstore_rs1;
    logic [3:0]  rr_feist_rdL;
    logic [3:0]  rr_feist_rdR;
    logic [3:0]  rr_feist_rsL;
    logic [3:0]  rr_feist_rsR;
    logic [1:0]  rr_feist_key;
    logic [1:0]  rr_feist_round;
    logic        rr_feist_mode;
    logic        rr_feist_valid;

    // Valores leidos del register file en esta etapa.
    logic [31:0] rr_alu_op1;
    logic [31:0] rr_alu_op2;
    logic [31:0] rr_lsu_base_addr;
    logic [31:0] rr_lsu_store_data;
    logic [31:0] rr_bru_src1_value;
    logic [31:0] rr_bru_src2_value;

    // Direcciones multiplexadas de los dos puertos de lectura que comparte la unidad Feistel: AUTH usa dos registros, KSTORE uno
    // y FROUND las dos mitades del bloque. Las operaciones son mutuamente excluyentes porque solo hay un slot Feistel.
    logic [3:0]  rr_feist_rd_addr_a;
    logic [3:0]  rr_feist_rd_addr_b;

    logic [31:0] rr_feist_auth_val1;
    logic [31:0] rr_feist_auth_val2;
    logic [31:0] rr_feist_kstore_val;
    logic [31:0] rr_feist_l_in;
    logic [31:0] rr_feist_r_in;

    // =========================================================
    // ETAPA EX
    // =========================================================
    // Contenido empaquetado que entra y sale del registro RR/EX.
    logic [W_RR_EX-1:0] rr_ex_data_in;
    logic [W_RR_EX-1:0] rr_ex_data_out;
    logic               rr_ex_valid_out;

    // Campos desempaquetados en EX.
    logic [31:0] ex_pc;

    logic [31:0] ex_alu_op1;
    logic [31:0] ex_alu_op2;
    logic [3:0]  ex_alu_rd;
    logic [2:0]  ex_alu_opcode;
    logic        ex_alu_imm_op;
    logic [11:0] ex_alu_imm;
    logic        ex_alu_valid;

    logic [31:0] ex_lsu_base_addr;
    logic [31:0] ex_lsu_store_data;
    logic [3:0]  ex_lsu_data_reg_idx;
    logic [11:0] ex_lsu_offset;
    logic        ex_lsu_load_enable;
    logic        ex_lsu_store_enable;
    logic        ex_lsu_reg_write;
    logic        ex_lsu_valid;

    logic [2:0]  ex_bru_opcode;
    logic [31:0] ex_bru_src1_value;
    logic [31:0] ex_bru_src2_value;
    logic [31:0] ex_bru_offset;
    logic        ex_bru_valid;

    logic        ex_feist_auth_en;
    logic        ex_feist_logout_en;
    logic        ex_feist_kstore_en;
    logic        ex_feist_fround_en;
    logic [31:0] ex_feist_auth_val1;
    logic [31:0] ex_feist_auth_val2;
    logic [31:0] ex_feist_kstore_val;
    logic [31:0] ex_feist_l_in;
    logic [31:0] ex_feist_r_in;
    logic [3:0]  ex_feist_rdL;
    logic [3:0]  ex_feist_rdR;
    logic [1:0]  ex_feist_key;
    logic [1:0]  ex_feist_round;
    logic        ex_feist_mode;
    logic        ex_feist_valid;

    // Enables de la unidad Feistel ya filtrados por la validez del bundle: un bundle invalidado no puede autenticar ni tocar la boveda de llaves.
    logic        ex_feist_active;
    logic        ex_feist_auth_req;
    logic        ex_feist_logout_req;
    logic        ex_feist_kstore_req;
    logic        ex_feist_fround_req;

    // Interfaz entre la boveda y la unidad criptografica.
    logic [31:0] ex_vault_subkey;
    logic        ex_vault_subkey_valid;
    logic        ex_vault_authorized;
    logic        ex_vault_access_error;

    logic [31:0] ex_feist_l_out;
    logic [31:0] ex_feist_r_out;
    logic        ex_feist_result_valid;
    logic        ex_feist_access_error;

    // Resultados de las unidades de ejecucion.
    logic [31:0] ex_alu_result;
    logic        ex_alu_zero;

    logic [31:0] ex_lsu_effective_addr;
    logic [31:0] ex_lsu_mem_write_data;
    logic        ex_lsu_mem_read;
    logic        ex_lsu_mem_write;
    logic [31:0] ex_lsu_read_data;
    logic        ex_lsu_access_error;
    logic        ex_lsu_addr_aligned;

    // Salidas de la memoria interna del Proyecto 1. Se mantienen
    // separadas para conservar data_memory_inst en el mismo nivel
    // jerarquico que esperaban los testbenches existentes.
    logic [31:0] legacy_lsu_read_data;
    logic        legacy_lsu_access_error;

    logic        ex_bru_branch_taken;
    logic [31:0] ex_bru_branch_target;

    logic        ex_branch_taken; // Un salto solo redirige el PC si su slot es valido.


    // =========================================================
    // ETAPA WB
    // =========================================================
    // Contenido empaquetado que entra y sale del registro EX/WB.
    logic [W_EX_WB-1:0] ex_wb_data_in;
    logic [W_EX_WB-1:0] ex_wb_data_out;
    logic               ex_wb_valid_out;

    // Campos desempaquetados en WB.
    logic [31:0] wb_pc;

    logic [31:0] wb_alu_result;
    logic [3:0]  wb_alu_rd;
    logic        wb_alu_write_enable;

    logic [31:0] wb_lsu_data;
    logic [3:0]  wb_lsu_rd;
    logic        wb_lsu_write_enable;

    logic [31:0] wb_feist_l;
    logic [31:0] wb_feist_r;
    logic [3:0]  wb_feist_rdL;
    logic [3:0]  wb_feist_rdR;
    logic        wb_feist_write_enable;

    // Escritura a x1 (el PC) detectada en WB.
    logic        wb_alu_writes_pc;
    logic        wb_lsu_writes_pc;
    logic        wb_pc_write;
    logic [31:0] wb_pc_write_data;


    // ---------------------------------------------------------
    // SENALES DEL REGISTER FILE
    // ---------------------------------------------------------
    // Puertos de lectura: 8 registros
    logic [7:0][3:0] regfile_rd_addr;
    logic [7:0][31:0] regfile_rd_data;

    // Puertos de escritura: 4 registros
    logic [3:0] regfile_wr_en;
    logic [3:0][3:0] regfile_wr_addr;
    logic [3:0][31:0] regfile_wr_data;

    // =========================================================
    // CONTROL DEL PIPELINE
    // =========================================================

    // Cuando CACHE_IF_EN = 0 se conserva el comportamiento del
    // Proyecto 1: solo stall_i puede detener el procesador.
    // Cuando CACHE_IF_EN = 1, un miss/backpressure de cache tambien
    // congela el PC y todos los registros del pipeline.
    assign cache_stall = CACHE_IF_EN ? cache_stall_i : 1'b0;
    assign global_stall = stall_i | cache_stall;
    assign global_stall_o = global_stall;

    // Mantiene el unico registro de PC del procesador y genera los enables y flush de los registros del pipeline. El salto del BRU llega desde 
    // EX y la escritura a x1 llega desde WB.

    pipeline_control #(
        .RESET_PC(RESET_PC)
    ) pipeline_control_inst (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .stall_i(global_stall),

        // Resultado del BRU en EX.
        .branch_taken_ex_i(ex_branch_taken),
        .branch_target_ex_i(ex_bru_branch_target),

        // Escritura especial a x1 desde WB.
        .pc_write_wb_i(wb_pc_write),
        .pc_write_data_wb_i(wb_pc_write_data),

        // PC que consume Fetch.
        .pc_o(if_pc),

        .enable_if_id_o(enable_if_id),
        .enable_id_rr_o(enable_id_rr),
        .enable_rr_ex_o(enable_rr_ex),
        .enable_ex_wb_o(enable_ex_wb),

        .flush_if_id_o(flush_if_id),
        .flush_id_rr_o(flush_id_rr),
        .flush_rr_ex_o(flush_rr_ex),
        .flush_ex_wb_o(flush_ex_wb)
    );

    // =========================================================
    // ETAPA IF: BUSQUEDA DE INSTRUCCIONES
    // =========================================================
    // Lee el pc de pipeline_control y solo lee la memoria de instrucciones.
    fetch #(
        .IMEM_WORDS(IMEM_WORDS),
        .PROGRAM_FILE(PROGRAM_FILE)
    ) fetch_inst (
        .pc_i(if_pc), // Direccion del bundle a leer.

        // Salidas de Fetch conectadas a senales internas.
        .bundle_o(if_bundle),
        .valid_o(if_valid),
        .access_error_o(if_access_error)
    );

    // ---------------------------------------------------------
    // REGISTRO IF/ID
    // ---------------------------------------------------------
    assign if_id_data_in = {if_bundle, if_pc};

    pipeline_reg #(
        .WIDTH(W_IF_ID)
    ) if_id_reg (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .enable_i(enable_if_id),
        .flush_i(flush_if_id),

        .valid_i(if_valid),
        .data_i(if_id_data_in),

        .valid_o(if_id_valid_out),
        .data_o(if_id_data_out)
    );

    assign {id_bundle, id_pc} = if_id_data_out;

    // =========================================================
    // ETAPA ID: SEPARACION Y DECODIFICACION
    // =========================================================
    // Recibe el bundle completo y lo separa en sus cuatro slots. Dispatch no ejecuta las instrucciones: solamente las separa y genera las senales de validez correspondientes.
    dispatch dispatch_inst (
        // Entradas provenientes del registro IF/ID.
        .bundle_i(id_bundle),
        .pc_i(id_pc),
        .valid_i(if_id_valid_out),

        // Instrucciones completas, una por slot.
        .instr_alu_o(id_instr_alu),
        .instr_lsu_o(id_instr_lsu),
        .instr_bru_o(id_instr_bru),
        .instr_feist_o(id_instr_feist),

        // PC asociado al bundle recibido.
        .pc_o(id_dispatch_pc),

        // Validez de cada slot y del bundle completo.
        .valid_alu_o(id_valid_alu),
        .valid_lsu_o(id_valid_lsu),
        .valid_bru_o(id_valid_bru),
        .valid_feist_o(id_valid_feist)
    );

    alu_decoder alu_decoder_inst (
        .instr_alu_o(id_instr_alu),

        // Campos extraidos
        .rd(id_alu_rd),
        .rs1(id_alu_rs1),
        .rs2(id_alu_rs2),
        .opcode(id_alu_opcode),
        .imm_op(id_alu_imm_op),
        .imm(id_alu_imm),
        .illegal_o(id_alu_illegal_instr)
    );

    lsu_decoder lsu_decoder_inst (
        .instr(id_instr_lsu),

        // Campos extraidos
        .base_reg_idx(id_lsu_base_reg_idx),
        .data_reg_idx(id_lsu_data_reg_idx),
        .offset(id_lsu_offset),

        // Senales de control
        .load_enable(id_lsu_load_enable),
        .store_enable(id_lsu_store_enable),
        .reg_write(id_lsu_reg_write),

        .nop(id_lsu_nop),
        .illegal_instr(id_lsu_illegal_instr)
    );

    bru_decoder bru_decoder_inst (
        .valid_i(id_valid_bru),
        .instr_i(id_instr_bru),

        // Campos extraidos
        .opcode_o(id_bru_opcode),
        .rs1_o(id_bru_rs1),
        .rs2_o(id_bru_rs2),
        .offset_o(id_bru_offset),
        .illegal_o(id_bru_illegal_instr)
    );

    feist_decoder feist_decoder_inst (
        .instr_feist_i(id_instr_feist),
        .valid_feist_i(id_valid_feist),

        // Operacion solicitada
        .auth_en(id_feist_auth_en),
        .logout_en(id_feist_logout_en),
        .kstore_en(id_feist_kstore_en),
        .fround_en(id_feist_fround_en),

        .illegal_opcode(id_feist_illegal_opcode),

        // Campos extraidos
        .auth_rs1_o(id_feist_auth_rs1),
        .auth_rs2_o(id_feist_auth_rs2),
        .kstore_rs1_o(id_feist_kstore_rs1),

        .rdL_o(id_feist_rdL),
        .rdR_o(id_feist_rdR),
        .rsL_o(id_feist_rsL),
        .rsR_o(id_feist_rsR),

        .key_o(id_feist_key),
        .round_o(id_feist_round),
        .mode_o(id_feist_mode)
    );

    // ---------------------------------------------------------
    // REGISTRO ID/RR
    // ---------------------------------------------------------
    assign id_rr_data_in = {
        id_dispatch_pc,

        // ALU
        id_alu_rd, id_alu_rs1, id_alu_rs2,
        id_alu_opcode, id_alu_imm_op, id_alu_imm,
        id_valid_alu,

        // LSU
        id_lsu_base_reg_idx, id_lsu_data_reg_idx, id_lsu_offset,
        id_lsu_load_enable, id_lsu_store_enable, id_lsu_reg_write,
        id_valid_lsu,

        // BRU
        id_bru_opcode, id_bru_rs1, id_bru_rs2, id_bru_offset,
        id_valid_bru,

        // FEISTEL
        id_feist_auth_en, id_feist_logout_en,
        id_feist_kstore_en, id_feist_fround_en,
        id_feist_auth_rs1, id_feist_auth_rs2, id_feist_kstore_rs1,
        id_feist_rdL, id_feist_rdR, id_feist_rsL, id_feist_rsR,
        id_feist_key, id_feist_round, id_feist_mode,
        id_valid_feist
    };

    always_comb begin 
        valid_opcodes = !id_feist_illegal_opcode && !id_bru_illegal_instr && !id_lsu_illegal_instr && !id_alu_illegal_instr;
        id_valid = if_id_valid_out && valid_opcodes;
    end

    pipeline_reg #(
        .WIDTH(W_ID_RR)
    ) id_rr_reg (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .enable_i(enable_id_rr),
        .flush_i(flush_id_rr),

        .valid_i(id_valid),
        .data_i(id_rr_data_in),

        .valid_o(id_rr_valid_out),
        .data_o(id_rr_data_out)
    );

    assign {
        rr_pc,

        rr_alu_rd, rr_alu_rs1, rr_alu_rs2,
        rr_alu_opcode, rr_alu_imm_op, rr_alu_imm,
        rr_alu_valid,

        rr_lsu_base_reg_idx, rr_lsu_data_reg_idx, rr_lsu_offset,
        rr_lsu_load_enable, rr_lsu_store_enable, rr_lsu_reg_write,
        rr_lsu_valid,

        rr_bru_opcode, rr_bru_rs1, rr_bru_rs2, rr_bru_offset,
        rr_bru_valid,

        rr_feist_auth_en, rr_feist_logout_en,
        rr_feist_kstore_en, rr_feist_fround_en,
        rr_feist_auth_rs1, rr_feist_auth_rs2, rr_feist_kstore_rs1,
        rr_feist_rdL, rr_feist_rdR, rr_feist_rsL, rr_feist_rsR,
        rr_feist_key, rr_feist_round, rr_feist_mode,
        rr_feist_valid
    } = id_rr_data_out;


    // =========================================================
    // ETAPA RR: LECTURA DEL REGISTER FILE
    // =========================================================
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

    // Leer x1 entrega el PC del bundle que esta en RR, no el contenido del register file, donde x1 nunca se escribe.
    // ===== LECTURAS DEL ALU (puertos 0 y 1) =====
    assign regfile_rd_addr[0] = rr_alu_rs1;
    assign regfile_rd_addr[1] = rr_alu_rs2;

    assign rr_alu_op1 = (rr_alu_rs1 == PC_REG) ? rr_pc : regfile_rd_data[0];
    assign rr_alu_op2 = (rr_alu_rs2 == PC_REG) ? rr_pc : regfile_rd_data[1];

    // ===== LECTURAS DEL LSU (puertos 2 y 3) =====
    assign regfile_rd_addr[2] = rr_lsu_base_reg_idx; // registro base para la direccion efectiva.
    assign regfile_rd_addr[3] = rr_lsu_data_reg_idx; // registro de datos a almacenar (para STORE).

    assign rr_lsu_base_addr  = (rr_lsu_base_reg_idx == PC_REG) ? rr_pc  : regfile_rd_data[2];
    assign rr_lsu_store_data = (rr_lsu_data_reg_idx == PC_REG) ? rr_pc : regfile_rd_data[3];

    // ===== LECTURAS DEL BRU (puertos 4 y 5) =====
    assign regfile_rd_addr[4] = rr_bru_rs1;
    assign regfile_rd_addr[5] = rr_bru_rs2;

    assign rr_bru_src1_value = (rr_bru_rs1 == PC_REG) ? rr_pc : regfile_rd_data[4];
    assign rr_bru_src2_value = (rr_bru_rs2 == PC_REG) ? rr_pc : regfile_rd_data[5];

    // ===== LECTURAS DE LA UNIDAD FEISTEL (puertos 6 y 7) =====
    // Las tres operaciones que leen registros son mutuamente excluyentes, asi que comparten el mismo par de puertos:
    //   AUTH   : rs1 -> puerto 6, rs2 -> puerto 7
    //   KSTORE : rs1 -> puerto 6
    //   FROUND : rsL -> puerto 6, rsR -> puerto 7
    always_comb begin
        rr_feist_rd_addr_a = 4'b0;
        rr_feist_rd_addr_b = 4'b0;

        if (rr_feist_auth_en) begin
            rr_feist_rd_addr_a = rr_feist_auth_rs1;
            rr_feist_rd_addr_b = rr_feist_auth_rs2;
        end
        else if (rr_feist_kstore_en) begin
            rr_feist_rd_addr_a = rr_feist_kstore_rs1;
        end
        else if (rr_feist_fround_en) begin
            rr_feist_rd_addr_a = rr_feist_rsL;
            rr_feist_rd_addr_b = rr_feist_rsR;
        end
    end

    assign regfile_rd_addr[6] = rr_feist_rd_addr_a;
    assign regfile_rd_addr[7] = rr_feist_rd_addr_b;

    // x1 se sustituye por el PC igual que en el resto de unidades.
    assign rr_feist_auth_val1 = (rr_feist_rd_addr_a == PC_REG) ? rr_pc : regfile_rd_data[6];
    assign rr_feist_auth_val2 = (rr_feist_rd_addr_b == PC_REG) ? rr_pc : regfile_rd_data[7];

    // KSTORE y FROUND reutilizan los mismos valores leidos.
    assign rr_feist_kstore_val = rr_feist_auth_val1;
    assign rr_feist_l_in       = rr_feist_auth_val1;
    assign rr_feist_r_in       = rr_feist_auth_val2;

    // ---------------------------------------------------------
    // REGISTRO RR/EX
    // ---------------------------------------------------------
    assign rr_ex_data_in = {
        rr_pc,

        // ALU: los indices de fuente se sustituyen por sus valores.
        rr_alu_op1, rr_alu_op2, rr_alu_rd,
        rr_alu_opcode, rr_alu_imm_op, rr_alu_imm,
        rr_alu_valid,

        // LSU
        rr_lsu_base_addr, rr_lsu_store_data, rr_lsu_data_reg_idx,
        rr_lsu_offset,
        rr_lsu_load_enable, rr_lsu_store_enable, rr_lsu_reg_write,
        rr_lsu_valid,

        // BRU
        rr_bru_opcode, rr_bru_src1_value, rr_bru_src2_value,
        rr_bru_offset,
        rr_bru_valid,

        // FEISTEL: los indices de fuente se sustituyen por sus valores.
        rr_feist_auth_en, rr_feist_logout_en,
        rr_feist_kstore_en, rr_feist_fround_en,
        rr_feist_auth_val1, rr_feist_auth_val2, rr_feist_kstore_val,
        rr_feist_l_in, rr_feist_r_in,
        rr_feist_rdL, rr_feist_rdR,
        rr_feist_key, rr_feist_round, rr_feist_mode,
        rr_feist_valid
    };

    pipeline_reg #(
        .WIDTH(W_RR_EX)
    ) rr_ex_reg (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .enable_i(enable_rr_ex),
        .flush_i(flush_rr_ex),

        .valid_i(id_rr_valid_out),
        .data_i(rr_ex_data_in),

        .valid_o(rr_ex_valid_out),
        .data_o(rr_ex_data_out)
    );

    assign {
        ex_pc,

        ex_alu_op1, ex_alu_op2, ex_alu_rd,
        ex_alu_opcode, ex_alu_imm_op, ex_alu_imm,
        ex_alu_valid,

        ex_lsu_base_addr, ex_lsu_store_data, ex_lsu_data_reg_idx,
        ex_lsu_offset,
        ex_lsu_load_enable, ex_lsu_store_enable, ex_lsu_reg_write,
        ex_lsu_valid,

        ex_bru_opcode, ex_bru_src1_value, ex_bru_src2_value,
        ex_bru_offset,
        ex_bru_valid,

        ex_feist_auth_en, ex_feist_logout_en,
        ex_feist_kstore_en, ex_feist_fround_en,
        ex_feist_auth_val1, ex_feist_auth_val2, ex_feist_kstore_val,
        ex_feist_l_in, ex_feist_r_in,
        ex_feist_rdL, ex_feist_rdR,
        ex_feist_key, ex_feist_round, ex_feist_mode,
        ex_feist_valid
    } = rr_ex_data_out;


    // =========================================================
    // ETAPA EX: EJECUCION
    // =========================================================

    alu alu_inst (
        .op1(ex_alu_op1),
        .op2(ex_alu_op2),
        .imm(ex_alu_imm),
        .opcode(ex_alu_opcode),
        .imm_op(ex_alu_imm_op),

        .data_out(ex_alu_result),
        .zero(ex_alu_zero)
    );

    lsu lsu_inst (
        .base_addr(ex_lsu_base_addr),
        .offset(ex_lsu_offset),

        .store_data(ex_lsu_store_data),

        // Una operacion de memoria solo se emite si el bundle que la contiene sigue siendo valido en esta etapa.
        .load_enable(ex_lsu_load_enable & ex_lsu_valid & rr_ex_valid_out),
        .store_enable(ex_lsu_store_enable & ex_lsu_valid & rr_ex_valid_out & ~stall_i),

        .effective_addr(ex_lsu_effective_addr),
        .mem_write_data(ex_lsu_mem_write_data),

        .mem_read(ex_lsu_mem_read),
        .mem_write(ex_lsu_mem_write)
    );


    // ---------------------------------------------------------
    // INTERFAZ LSU -> CACHE / MEMORIA LEGACY
    // ---------------------------------------------------------

    // l1_data_system trabaja con palabras de 32 bits alineadas.
    assign ex_lsu_addr_aligned =
        (ex_lsu_effective_addr[1:0] == 2'b00);

    // Durante un stall externo no se inicia una operacion nueva.
    // Durante cache_stall la solicitud debe permanecer activa hasta
    // que la cache la acepte, por eso NO se filtra con global_stall.
    assign cache_read_o =
        CACHE_IF_EN &&
        ex_lsu_mem_read &&
        ex_lsu_addr_aligned &&
        !stall_i;

    assign cache_write_o =
        CACHE_IF_EN &&
        ex_lsu_mem_write &&
        ex_lsu_addr_aligned &&
        !stall_i;

    assign cache_addr_o = ex_lsu_effective_addr;
    assign cache_write_data_o = ex_lsu_mem_write_data;

    // ---------------------------------------------------------
    // MEMORIA INTERNA LEGACY DEL PROYECTO 1
    // ---------------------------------------------------------

    // Se instancia SIEMPRE y se conserva el nombre data_memory_inst
    // en este mismo nivel jerarquico. Esto mantiene compatibles los
    // testbenches existentes que acceden, por ejemplo, a:
    //     dut.data_memory_inst.memory[...]
    //
    // Cuando CACHE_IF_EN = 1 sus enables quedan en cero y la memoria
    // interna no participa en la ejecucion.
    data_memory #(
        .DATA_FILE(DATA_FILE)
    ) data_memory_inst (
        .clk(clk_mem_i),
        .rst(rst_i),

        .mem_read(CACHE_IF_EN ? 1'b0 : ex_lsu_mem_read),
        .mem_write(CACHE_IF_EN ? 1'b0 : ex_lsu_mem_write),

        .addr(ex_lsu_effective_addr),
        .write_data(ex_lsu_mem_write_data),

        .read_data(legacy_lsu_read_data),
        .access_error(legacy_lsu_access_error)
    );

    // Seleccion de la fuente de datos/error segun el modo.
    // En modo cache, una direccion desalineada se rechaza localmente
    // y no se envia a L1, evitando esperar una respuesta imposible.
    assign ex_lsu_access_error =
        CACHE_IF_EN
            ? ((ex_lsu_mem_read || ex_lsu_mem_write) &&
               !ex_lsu_addr_aligned)
            : legacy_lsu_access_error;

    // En el ciclo en que cache_ready_i se activa, cache_stall_i debe
    // estar desactivado y EX/WB puede capturar el dato.
    assign ex_lsu_read_data =
        CACHE_IF_EN
            ? (cache_ready_i ? cache_read_data_i : 32'b0)
            : legacy_lsu_read_data;


    bru bru_inst (
        .opcode_i(ex_bru_opcode),
        .pc_i(ex_pc),

        .src1_value_i(ex_bru_src1_value),
        .src2_value_i(ex_bru_src2_value),
        .imm_i(ex_bru_offset),

        .branch_taken_o(ex_bru_branch_taken),
        .branch_target_o(ex_bru_branch_target)
    );

    // El salto solo redirige el PC si el slot BRU es valido y el  bundle no fue invalidado por un flush anterior.
    assign ex_branch_taken = ex_bru_branch_taken & ex_bru_valid & rr_ex_valid_out;

    // ---------------------------------------------------------
    // UNIDAD FEISTEL4
    // ---------------------------------------------------------

    // La boveda cambia de estado (autorizacion y llaves) en el flanco de reloj de esta etapa, asi que sus enables deben filtrarse por
    // la validez del bundle: un bundle descartado por un flush no puede autenticar ni escribir llaves.
    assign ex_feist_active = ex_feist_valid & rr_ex_valid_out & ~global_stall;

    assign ex_feist_auth_req   = ex_feist_auth_en   & ex_feist_active;
    assign ex_feist_logout_req = ex_feist_logout_en & ex_feist_active;
    assign ex_feist_kstore_req = ex_feist_kstore_en & ex_feist_active;
    assign ex_feist_fround_req = ex_feist_fround_en & ex_feist_active;

    // Raiz de confianza: guarda las cuatro llaves de 128 bits y mantiene el estado de autenticacion. Su unico puerto de lectura
    // va directo a crypto_unit, nunca al register file.
    key_vault key_vault_inst (
        .clk(clk_i),
        .reset(rst_i),

        .auth_en(ex_feist_auth_req),
        .logout_en(ex_feist_logout_req),
        .kstore_en(ex_feist_kstore_req),
        .fround_en(ex_feist_fround_req),

        // Credenciales presentadas por AUTH.
        .auth_rs1(ex_feist_auth_val1),
        .auth_rs2(ex_feist_auth_val2),

        // Seleccion de llave y subllave.
        .key_sel(ex_feist_key),
        .round_sel(ex_feist_round),

        // Valor que KSTORE guarda en la boveda.
        .subkey_in(ex_feist_kstore_val),

        .authorized(ex_vault_authorized),
        .access_error(ex_vault_access_error),

        // Conexion dedicada hacia la unidad criptografica.
        .subkey_out(ex_vault_subkey),
        .subkey_valid(ex_vault_subkey_valid)
    );

    crypto_unit crypto_unit_inst (
        .fround_en(ex_feist_fround_req),
        .mode_decrypt(ex_feist_mode),

        // Mitades del bloque leidas del register file.
        .l_in(ex_feist_l_in),
        .r_in(ex_feist_r_in),

        // Subllave entregada por la boveda.
        .subkey_in(ex_vault_subkey),
        .subkey_valid(ex_vault_subkey_valid),

        .l_out(ex_feist_l_out),
        .r_out(ex_feist_r_out),

        .result_valid(ex_feist_result_valid),
        .access_error(ex_feist_access_error)
    );

    // ---------------------------------------------------------
    // REGISTRO EX/WB
    // ---------------------------------------------------------
    assign ex_wb_data_in = {
        ex_pc,

        // ALU
        ex_alu_result, ex_alu_rd,
        ex_alu_valid,

        // LSU: solo los LOAD escriben al register file.
        ex_lsu_read_data, ex_lsu_data_reg_idx,
        ex_lsu_reg_write & ex_lsu_valid & ~ex_lsu_access_error,

        // FEISTEL: solo una ronda autorizada produce escritura.
        ex_feist_l_out, ex_feist_r_out,
        ex_feist_rdL, ex_feist_rdR,
        ex_feist_result_valid
    };

    pipeline_reg #(
        .WIDTH(W_EX_WB)
    ) ex_wb_reg (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .enable_i(enable_ex_wb),
        .flush_i(flush_ex_wb),

        .valid_i(rr_ex_valid_out),
        .data_i(ex_wb_data_in),

        .valid_o(ex_wb_valid_out),
        .data_o(ex_wb_data_out)
    );

    assign {
        wb_pc,

        wb_alu_result, wb_alu_rd,
        wb_alu_write_enable,

        wb_lsu_data, wb_lsu_rd,
        wb_lsu_write_enable,

        wb_feist_l, wb_feist_r,
        wb_feist_rdL, wb_feist_rdR,
        wb_feist_write_enable
    } = ex_wb_data_out;

    // =========================================================
    // ETAPA WB: ESCRITURA AL REGISTER FILE
    // =========================================================

    // x1 es el PC y no vive en el register file. Una escritura a x1 se desvia hacia pipeline_control, que redirige el PC y descarta
    // los bundles mas jovenes. El compilador garantiza que a lo sumo un slot escribe x1 por bundle.
    assign wb_alu_writes_pc = wb_alu_write_enable & ex_wb_valid_out & (wb_alu_rd == PC_REG);
    assign wb_lsu_writes_pc = wb_lsu_write_enable & ex_wb_valid_out & (wb_lsu_rd == PC_REG);

    assign wb_pc_write = wb_alu_writes_pc | wb_lsu_writes_pc;
    assign wb_pc_write_data = wb_alu_writes_pc ? wb_alu_result : wb_lsu_data;

    // Puerto de escritura 0: resultado del ALU.
    assign regfile_wr_addr[0] = wb_alu_rd;
    assign regfile_wr_data[0] = wb_alu_result;

    assign regfile_wr_en[0]   = wb_alu_write_enable & ex_wb_valid_out & ~wb_alu_writes_pc & ~global_stall;


    // Puerto de escritura 1: dato leido por el LSU.
    assign regfile_wr_addr[1] = wb_lsu_rd;
    assign regfile_wr_data[1] = wb_lsu_data;
    assign regfile_wr_en[1]   = wb_lsu_write_enable & ex_wb_valid_out & ~wb_lsu_writes_pc & ~global_stall;

    // Puertos de escritura 2 y 3: las dos mitades que produce una ronda Feistel. Nunca transportan material de llave: solo las
    // salidas de crypto_unit, jamas el contenido de la boveda. Una ronda Feistel no puede escribir x1: redirigir el PC con el
    // resultado de un cifrado no tiene sentido y el camino de escritura al PC solo admite un slot por bundle.
    assign regfile_wr_addr[2] = wb_feist_rdL;
    assign regfile_wr_data[2] = wb_feist_l;
    assign regfile_wr_en[2]   = wb_feist_write_enable & ex_wb_valid_out & (wb_feist_rdL != PC_REG) & ~global_stall;

    assign regfile_wr_addr[3] = wb_feist_rdR;
    assign regfile_wr_data[3] = wb_feist_r;
    assign regfile_wr_en[3]   = wb_feist_write_enable & ex_wb_valid_out & (wb_feist_rdR != PC_REG) & ~global_stall;

    // =========================================================
    // SALIDAS DE OBSERVACION
    // =========================================================

    // Etapa IF: PC y bundle que Fetch esta entregando.
    assign pc_o          = if_pc;
    assign bundle_o      = if_bundle;
    assign fetch_valid_o = if_valid;

    // Etapa ID: instrucciones separadas por Dispatch.
    assign instr_alu_o   = id_instr_alu;
    assign instr_lsu_o   = id_instr_lsu;
    assign instr_bru_o   = id_instr_bru;
    assign instr_feist_o = id_instr_feist;

    assign valid_alu_o   = id_valid_alu;
    assign valid_lsu_o   = id_valid_lsu;
    assign valid_bru_o   = id_valid_bru;
    assign valid_feist_o = id_valid_feist;

    assign dispatch_valid_o = id_valid;
endmodule

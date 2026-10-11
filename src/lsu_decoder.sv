`timescale 1ns/1ps

module lsu_decoder (
    input  logic [31:0] instr,

    // Campos extraídos
    output logic [3:0]  base_reg_idx,
    output logic [3:0]  data_reg_idx,
    output logic [11:0] offset,

    // Señales de control
    output logic        load_enable,
    output logic        store_enable,
    output logic        reg_write,

    output logic        nop,
    output logic        illegal_instr
);

    // ============================================================
    // Opcodes del slot LSU
    // ============================================================

    localparam logic [1:0] OP_NOP   = 2'b00;
    localparam logic [1:0] OP_LOAD  = 2'b01;
    localparam logic [1:0] OP_STORE = 2'b10;

    logic [1:0] opcode;

    assign opcode       = instr[1:0];
    assign data_reg_idx = instr[5:2];
    assign base_reg_idx = instr[9:6];
    assign offset       = instr[21:10];

    // ============================================================
    // Decodificación
    // ============================================================

    logic reserved_ok;
    assign reserved_ok = (instr[31:22] == 10'b0);


    always_comb begin

        // Valores por defecto
        load_enable  = 1'b0;
        store_enable = 1'b0;
        reg_write    = 1'b0;

        nop           = 1'b0;
        illegal_instr = 1'b0;


        // --------------------------------------------------------
        // Verificación de bits reservados
        // --------------------------------------------------------
        //
        // Los bits [31:22] deben ser cero.
        //

        if (!reserved_ok) begin

            illegal_instr = 1'b1;

        end
        else begin

            case (opcode)

                // ------------------------------------------------
                // NOP
                // ------------------------------------------------

                OP_NOP: begin
                    nop = 1'b1;
                end


                // ------------------------------------------------
                // LOAD
                // ------------------------------------------------
                //
                // LOAD rd, offset(rb)
                //
                // El dato leído de memoria se escribe posteriormente
                // en rd.
                //

                OP_LOAD: begin
                    load_enable = 1'b1;
                    reg_write   = 1'b1;
                end


                // ------------------------------------------------
                // STORE
                // ------------------------------------------------
                //
                // STORE rs1, offset(rb)
                //
                // rs1 contiene el dato que será almacenado.
                //

                OP_STORE: begin
                    store_enable = 1'b1;
                end


                // ------------------------------------------------
                // Opcode reservado
                // ------------------------------------------------

                default: begin
                    illegal_instr = 1'b1;
                end

            endcase

        end

    end

endmodule
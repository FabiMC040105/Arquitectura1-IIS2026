`timescale 1ns/1ps

module pipeline_control #(
    parameter [31:0] RESET_PC = 32'd0
)(
    input  logic        clk_i,
    input  logic        rst_i,

    // Stall estructural global
    input  logic        stall_i,

    // Resultado del BRU en EX
    input  logic        branch_taken_ex_i,
    input  logic [31:0] branch_target_ex_i,

    // Escritura especial a x1 desde WB
    input  logic        pc_write_wb_i,
    input  logic [31:0] pc_write_data_wb_i,

    // PC utilizado por Fetch
    output logic [31:0] pc_o,

    // Enable de registros del pipeline
    output logic enable_if_id_o,
    output logic enable_id_rr_o,
    output logic enable_rr_ex_o,
    output logic enable_ex_wb_o,

    // Flush de registros del pipeline
    output logic flush_if_id_o,
    output logic flush_id_rr_o,
    output logic flush_rr_ex_o,
    output logic flush_ex_wb_o
);
    logic [31:0] pc_next;
    logic pc_enable;

    // Control combinacional
    always @(*) begin

        // Por defecto: avanzar normalmente
        pc_next = pc_o + 32'd16;
        pc_enable = 1'b1;

        enable_if_id_o = 1'b1;
        enable_id_rr_o = 1'b1;
        enable_rr_ex_o = 1'b1;
        enable_ex_wb_o = 1'b1;

        flush_if_id_o = 1'b0;
        flush_id_rr_o = 1'b0;
        flush_rr_ex_o = 1'b0;
        flush_ex_wb_o = 1'b0;

        // Prioridad 1: Reset
        // Prioridad 2: Stall estructural
        if (rst_i || stall_i) begin
            pc_enable = 1'b0;

            enable_if_id_o = 1'b0;
            enable_id_rr_o = 1'b0;
            enable_rr_ex_o = 1'b0;
            enable_ex_wb_o = 1'b0;
        end

        // Prioridad 3: Escritura a x1 en WB
        else if (pc_write_wb_i) begin
            pc_next = pc_write_data_wb_i;

            // Invalidar todos los bundles mas recientes
            flush_if_id_o = 1'b1;
            flush_id_rr_o = 1'b1;
            flush_rr_ex_o = 1'b1;
            flush_ex_wb_o = 1'b1;
        end

        // Prioridad 4: Salto tomado por BRU en EX
        else if (branch_taken_ex_i) begin
            pc_next = branch_target_ex_i;

            // Invalidar los bundles mas recientes
            flush_if_id_o = 1'b1;
            flush_id_rr_o = 1'b1;
            flush_rr_ex_o = 1'b1;

            // El bundle en EX puede avanzar a WB
            flush_ex_wb_o = 1'b0;
        end

        // En otro caso: PC + 16 y avance normal
    end

    // Registro del PC: flanco positivo
    always @(posedge clk_i or posedge rst_i) begin

        if (rst_i) begin
            pc_o <= RESET_PC;
        end

        else if (pc_enable) begin
            pc_o <= pc_next;
        end

    end

endmodule
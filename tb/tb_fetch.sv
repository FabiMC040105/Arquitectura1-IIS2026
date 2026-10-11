`timescale 1ns/1ps

module tb_top;

    logic clk_i;
    logic rst_i;

    logic stall_i;
    logic branch_taken_ex_i;
    logic [31:0] branch_target_ex_i;
    logic pc_write_wb_i;
    logic [31:0] pc_write_data_wb_i;

    logic [31:0] pc_o;
    logic [127:0] bundle_o;
    logic fetch_valid_o;
    logic fetch_access_error_o;

    logic [127:0] bundle_if_id_o;
    logic [31:0] pc_if_id_o;
    logic valid_if_id_o;

    logic [31:0] instr_alu_o;
    logic [31:0] instr_lsu_o;
    logic [31:0] instr_bru_o;
    logic [31:0] instr_feist_o;
    logic [31:0] dispatch_pc_o;

    logic valid_alu_o;
    logic valid_lsu_o;
    logic valid_bru_o;
    logic valid_feist_o;
    logic dispatch_valid_o;

    logic enable_if_id_o;
    logic enable_id_rr_o;
    logic enable_rr_ex_o;
    logic enable_ex_wb_o;

    logic flush_if_id_o;
    logic flush_id_rr_o;
    logic flush_rr_ex_o;
    logic flush_ex_wb_o;

    top #(
        .IMEM_WORDS(16384),
        .RESET_PC(32'h00000000),
        .PROGRAM_FILE("program.mem")
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),

        .stall_i(stall_i),
        .branch_taken_ex_i(branch_taken_ex_i),
        .branch_target_ex_i(branch_target_ex_i),
        .pc_write_wb_i(pc_write_wb_i),
        .pc_write_data_wb_i(pc_write_data_wb_i),

        .pc_o(pc_o),
        .bundle_o(bundle_o),
        .fetch_valid_o(fetch_valid_o),
        .fetch_access_error_o(fetch_access_error_o),

        .bundle_if_id_o(bundle_if_id_o),
        .pc_if_id_o(pc_if_id_o),
        .valid_if_id_o(valid_if_id_o),

        .instr_alu_o(instr_alu_o),
        .instr_lsu_o(instr_lsu_o),
        .instr_bru_o(instr_bru_o),
        .instr_feist_o(instr_feist_o),
        .dispatch_pc_o(dispatch_pc_o),

        .valid_alu_o(valid_alu_o),
        .valid_lsu_o(valid_lsu_o),
        .valid_bru_o(valid_bru_o),
        .valid_feist_o(valid_feist_o),
        .dispatch_valid_o(dispatch_valid_o),

        .enable_if_id_o(enable_if_id_o),
        .enable_id_rr_o(enable_id_rr_o),
        .enable_rr_ex_o(enable_rr_ex_o),
        .enable_ex_wb_o(enable_ex_wb_o),

        .flush_if_id_o(flush_if_id_o),
        .flush_id_rr_o(flush_id_rr_o),
        .flush_rr_ex_o(flush_rr_ex_o),
        .flush_ex_wb_o(flush_ex_wb_o)
    );

    initial begin
        clk_i = 1'b0;
    end

    always #5 clk_i = ~clk_i;

    initial begin
        rst_i = 1'b1;

        stall_i = 1'b0;
        branch_taken_ex_i = 1'b0;
        branch_target_ex_i = 32'b0;
        pc_write_wb_i = 1'b0;
        pc_write_data_wb_i = 32'b0;

        $display("========================================");
        $display("Inicio de pruebas de TOP");
        $display("========================================");

        repeat (2) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        repeat (4) begin
            @(posedge clk_i);
            #1;

            $display(
                "PC=%h | IF/ID PC=%h | Fetch valid=%b | IF/ID valid=%b | Dispatch valid=%b",
                pc_o,
                pc_if_id_o,
                fetch_valid_o,
                valid_if_id_o,
                dispatch_valid_o
            );

            if (fetch_access_error_o !== 1'b0) begin
                $fatal(1, "ERROR: Fetch reporto un acceso invalido");
            end

            if (pc_o[3:0] !== 4'b0000) begin
                $fatal(1, "ERROR: PC desalineado");
            end

            if (valid_if_id_o && dispatch_pc_o !== pc_if_id_o) begin
                $fatal(1, "ERROR: el PC de Dispatch no coincide con IF/ID");
            end
        end

        $display("========================================");
        $display("Pruebas basicas de TOP finalizadas");
        $display("========================================");

        $finish;
    end

endmodule
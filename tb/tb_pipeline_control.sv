`timescale 1ns/1ps

module tb_pipeline_control;

    logic clk;
    logic rst;
    logic stall;

    logic branch_taken;
    logic [31:0] branch_target;

    logic pc_write;
    logic [31:0] pc_write_data;

    wire [31:0] pc;

    wire en_if_id;
    wire en_id_rr;
    wire en_rr_ex;
    wire en_ex_wb;

    wire fl_if_id;
    wire fl_id_rr;
    wire fl_rr_ex;
    wire fl_ex_wb;

    integer pruebas = 0;

    pipeline_control dut (
        .clk_i(clk),
        .rst_i(rst),
        .stall_i(stall),

        .branch_taken_ex_i(branch_taken),
        .branch_target_ex_i(branch_target),

        .pc_write_wb_i(pc_write),
        .pc_write_data_wb_i(pc_write_data),

        .pc_o(pc),

        .enable_if_id_o(en_if_id),
        .enable_id_rr_o(en_id_rr),
        .enable_rr_ex_o(en_rr_ex),
        .enable_ex_wb_o(en_ex_wb),

        .flush_if_id_o(fl_if_id),
        .flush_id_rr_o(fl_id_rr),
        .flush_rr_ex_o(fl_rr_ex),
        .flush_ex_wb_o(fl_ex_wb)
    );

    // Un ciclo de reloj
    task automatic ciclo;
        begin
            #1 clk = 1'b1;
            #1 clk = 1'b0;
            #1;
        end
    endtask

    // Orden de bits:
    // {IF/ID, ID/RR, RR/EX, EX/WB}
    task automatic verificar(
        input string nombre,
        input logic [31:0] esperado_pc,
        input logic [3:0] esperado_enable,
        input logic [3:0] esperado_flush
    );
        logic [3:0] enables;
        logic [3:0] flushes;

        begin
            enables = {
                en_if_id, en_id_rr,
                en_rr_ex, en_ex_wb
            };

            flushes = {
                fl_if_id, fl_id_rr,
                fl_rr_ex, fl_ex_wb
            };

            if (pc !== esperado_pc ||
                enables !== esperado_enable ||
                flushes !== esperado_flush) begin

                $display("FALLO: %s", nombre);

                $display(
                    "Esperado: PC=%0d enable=%b flush=%b",
                    esperado_pc,
                    esperado_enable,
                    esperado_flush
                );

                $display(
                    "Obtenido: PC=%0d enable=%b flush=%b",
                    pc,
                    enables,
                    flushes
                );

                $fatal(1, "Error en pipeline_control");
            end

            pruebas = pruebas + 1;
            $display("OK %0d: %s", pruebas, nombre);
        end
    endtask

    initial begin

        $dumpfile("pipeline_control.vcd");
        $dumpvars(0, tb_pipeline_control);

        // Inicializacion
        clk = 0;
        rst = 0;
        stall = 0;

        branch_taken = 0;
        branch_target = 0;

        pc_write = 0;
        pc_write_data = 0;

        // 1. Reset asincrono
        #1 rst = 1;
        #1;

        verificar("Reset inicial", 0, 4'b0000, 4'b0000);

        rst = 0;
        #1;

        verificar("Listo para avanzar", 0,
                 4'b1111, 4'b0000);

        // 2. Avance secuencial
        ciclo();
        verificar("PC +16", 16, 4'b1111, 4'b0000);

        ciclo();
        verificar("PC +16 otra vez", 32,
                 4'b1111, 4'b0000);

        // 3. Stall estructural
        stall = 1;
        #1;

        verificar("Stall activado", 32,
                 4'b0000, 4'b0000);

        ciclo();

        verificar("Stall conserva PC", 32,
                 4'b0000, 4'b0000);

        stall = 0;
        ciclo();

        verificar("Reanudar avance", 48,
                 4'b1111, 4'b0000);

        // 4. Salto tomado en EX
        branch_taken = 1;
        branch_target = 256;

        #1;
        verificar("Flush por salto EX", 48,
                 4'b1111, 4'b1110);

        ciclo();

        branch_taken = 0;
        #1;

        verificar("PC redirigido a 256", 256,
                 4'b1111, 4'b0000);

        // 5. Avance desde nuevo PC
        ciclo();

        verificar("Avance desde destino", 272,
                 4'b1111, 4'b0000);

        // 6. Escritura a x1 en WB
        pc_write = 1;
        pc_write_data = 512;

        // Simultaneamente EX pide saltar.
        // WB debe tener prioridad.
        branch_taken = 1;
        branch_target = 1024;

        #1;

        verificar("WB tiene prioridad sobre EX", 272,
                 4'b1111, 4'b1111);

        ciclo();

        pc_write = 0;
        branch_taken = 0;

        #1;

        verificar("PC escrito desde x1", 512,
                 4'b1111, 4'b0000);

        // 7. Stall retiene salto pendiente
        stall = 1;
        branch_taken = 1;
        branch_target = 1024;

        #1;

        verificar("Stall bloquea redireccion", 512,
                 4'b0000, 4'b0000);

        ciclo();

        verificar("PC retenido en stall", 512,
                 4'b0000, 4'b0000);

        // Al liberarse, se procesa el salto
        stall = 0;
        #1;

        verificar("Salto pendiente liberado", 512,
                 4'b1111, 4'b1110);

        ciclo();

        branch_taken = 0;
        #1;

        verificar("Destino tras stall", 1024,
                 4'b1111, 4'b0000);

        // 8. Reset desde un PC distinto de cero
        rst = 1;
        #1;

        verificar("Reset final", 0,
                 4'b0000, 4'b0000);

        $display(
            "PASS: %0d pruebas de pipeline_control superadas.",
            pruebas
        );

        $finish;

    end

endmodule
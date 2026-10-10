`timescale 1ns/1ps

module tb_pipeline_reg;

    // Señales de control
    logic clk;
    logic rst;
    logic enable;
    logic flush;

    // Entradas
    logic valid_in;
    logic [15:0] data_in;

    // Salidas
    wire valid_out;
    wire [15:0] data_out;

    integer pruebas = 0;

    // Instancia del módulo pipeline_reg
    pipeline_reg #(
        .WIDTH(16)
    ) dut (
        .clk_i    (clk),
        .rst_i    (rst),
        .enable_i (enable),
        .flush_i  (flush),

        .valid_i  (valid_in),
        .data_i   (data_in),

        .valid_o  (valid_out),
        .data_o   (data_out)
    );

    // Genera un ciclo completo de reloj
    task automatic ciclo;
        begin
            #1 clk = 1'b1;  // Flanco positivo
            #1 clk = 1'b0;  // Flanco negativo
            #1;
        end
    endtask

    // Comprueba si las salidas son correctas
    task automatic verificar(
        input string nombre,
        input logic esperado_valid,
        input logic [15:0] esperado_data
    );
        begin
            if (valid_out !== esperado_valid ||
                data_out !== esperado_data) begin

                $display("FALLO: %s", nombre);

                $display(
                    "Esperado: valid=%b data=%h",
                    esperado_valid,
                    esperado_data
                );

                $display(
                    "Obtenido: valid=%b data=%h",
                    valid_out,
                    data_out
                );

                $fatal(1, "Error en pipeline_reg");
            end

            pruebas = pruebas + 1;

            $display(
                "OK %0d: %s",
                pruebas,
                nombre
            );
        end
    endtask

    initial begin

        // Generar archivo de ondas
        $dumpfile("pipeline_reg.vcd");
        $dumpvars(0, tb_pipeline_reg);

        // Valores iniciales
        clk      = 1'b0;
        rst      = 1'b0;
        enable   = 1'b1;
        flush    = 1'b0;
        valid_in = 1'b0;
        data_in  = 16'h0000;

        // PRUEBA 1: RESET
        #1 rst = 1'b1;
        #1;

        verificar("Reset", 1'b0, 16'h0000);

        rst = 1'b0;

        // PRUEBA 2: GUARDAR DATOS
        valid_in = 1'b1;
        data_in  = 16'hAAAA;

        ciclo();

        verificar("Guardar A", 1'b1, 16'hAAAA);

        // PRUEBA 3: STALL
        enable  = 1'b0;
        data_in = 16'hBBBB;

        ciclo();

        // Debe mantener el dato anterior (AAAA)
        verificar("Stall mantiene A", 1'b1, 16'hAAAA);

        // PRUEBA 4: FLUSH DURANTE STALL
        flush = 1'b1;

        ciclo();

        // Flush tiene prioridad sobre enable
        verificar("Flush durante stall", 1'b0, 16'h0000);

        // PRUEBA 5: RECUPERACION
        flush    = 1'b0;
        enable   = 1'b1;
        valid_in = 1'b1;
        data_in  = 16'hCCCC;

        ciclo();

        verificar("Guardar C", 1'b1, 16'hCCCC);

        // PRUEBA 6: BURBUJA INVALIDA
        valid_in = 1'b0;
        data_in  = 16'hDDDD;

        ciclo();

        // Se almacenan los bits, pero valid_out = 0
        verificar("Burbuja invalida", 1'b0, 16'hDDDD);

        // PRUEBA 7: RESET ASINCRONO
        enable = 1'b0;
        rst    = 1'b1;

        #1;

        verificar("Reset asincrono", 1'b0, 16'h0000);

        $display(
            "PASS: %0d pruebas del pipeline_reg superadas.",
            pruebas
        );

        $finish;
    end

endmodule

`timescale 1ns/1ps

module tb_l1_miss_controller;

    // SEÑALES DEL TESTBENCH

    logic clk;
    logic rst;

    // Solicitud que genera L1 cuando ocurre un MISS
    logic miss_start;
    logic [31:0] miss_addr;

    // Comunicacion desde L1 hacia L2
    wire l2_req_valid;
    logic l2_req_ready;
    wire [31:0] l2_req_addr;

    // Respuesta simulada de L2
    logic l2_resp_valid;
    logic [255:0] l2_resp_data;

    // Datos que el controlador entrega a L1
    wire refill_valid;
    wire [31:0] refill_addr;
    wire [255:0] refill_data;

    // Indica si el controlador esta ocupado
    wire busy;

    // INSTANCIA DEL CONTROLADOR

    l1_miss_controller dut (
        .clk(clk),
        .rst(rst),

        .miss_start(miss_start),
        .miss_addr(miss_addr),

        .l2_req_valid(l2_req_valid),
        .l2_req_ready(l2_req_ready),
        .l2_req_addr(l2_req_addr),

        .l2_resp_valid(l2_resp_valid),
        .l2_resp_data(l2_resp_data),

        .refill_valid(refill_valid),
        .refill_addr(refill_addr),
        .refill_data(refill_data),

        .busy(busy)
    );

    // Reloj con periodo de 10 ns
    initial clk = 0;
    always #5 clk = ~clk;

    // PRUEBAS DEL CONTROLADOR

    initial begin

        // Inicializamos todas las entradas
        rst = 0;
        miss_start = 0;
        miss_addr = 0;

        l2_req_ready = 0;
        l2_resp_valid = 0;
        l2_resp_data = 0;

        $display("================================");
        $display(" PRUEBAS DEL CONTROLADOR MISS");
        $display("================================");

        // PRUEBA 1: Reiniciar el controlador
        // Debe comenzar sin solicitudes pendientes

        #2;
        rst = 1;
        #10;
        rst = 0;

        if (busy !== 1'b0 ||
            l2_req_valid !== 1'b0) begin

            $display("ERROR: reset incorrecto");
            $fatal(1);
        end

        $display("OK: controlador inicializado");

        // PRUEBA 2: Generar un MISS de lectura
        // El procesador solicita la direccion 0x28

        @(negedge clk);
        miss_addr = 32'h00000028;
        miss_start = 1'b1;

        @(posedge clk);
        #1;
        miss_start = 1'b0;

        // La linea comienza en 0x20 porque cada linea contiene 32 bytes
        if (l2_req_valid !== 1'b1 ||
            l2_req_addr !== 32'h00000020 ||
            busy !== 1'b1) begin

            $display("ERROR: solicitud incorrecta a L2");
            $fatal(1);
        end

        $display("OK: L1 solicita el bloque 00000020");

        // PRUEBA 3: L2 tarda en aceptar la solicitud
        // L1 debe mantenerla activa durante la espera
        repeat (2) @(posedge clk);
        #1;

        if (l2_req_valid !== 1'b1 ||
            l2_req_addr !== 32'h00000020) begin

            $display("ERROR: solicitud no se mantiene");
            $fatal(1);
        end

        $display("OK: L1 mantiene la solicitud");

        // PRUEBA 4: L2 acepta la solicitud
        @(negedge clk);
        l2_req_ready = 1'b1;

        @(posedge clk);
        #1;
        l2_req_ready = 1'b0;

        if (l2_req_valid !== 1'b0 ||
            busy !== 1'b1) begin

            $display("ERROR: no espera respuesta de L2");
            $fatal(1);
        end

        $display("OK: L2 acepto la solicitud");

        // PRUEBA 5: L2 tarda en devolver los datos. El controlador debe seguir ocupado
        repeat (3) @(posedge clk);
        #1;

        if (busy !== 1'b1 ||
            refill_valid !== 1'b0) begin

            $display("ERROR: respuesta prematura");
            $fatal(1);
        end

        $display("OK: L1 espera los datos de L2");

        // PRUEBA 6: L2 devuelve la linea completa
        // Repetimos el valor 123 ocho veces para formar los 256 bits de una linea
        @(negedge clk);
        l2_resp_data = {8{32'd123}};
        l2_resp_valid = 1'b1;

        @(posedge clk);
        #1;
        l2_resp_valid = 1'b0;

        // Verificamos que la direccion y los datos recibidos sean los que solicitamos
        if (refill_valid !== 1'b1 ||
            refill_addr !== 32'h00000020 ||
            refill_data !== {8{32'd123}}) begin

            $display("ERROR: relleno incorrecto");
            $fatal(1);
        end

        $display("OK: L1 recibe los 256 bits");
        $display("OK: direccion y datos correctos");

        // PRUEBA 7: Finalizar el relleno. El controlador debe regresar a IDLE
        @(posedge clk);
        #1;

        if (busy !== 1'b0 ||
            refill_valid !== 1'b0 ||
            l2_req_valid !== 1'b0) begin

            $display("ERROR: controlador no regreso a IDLE");
            $fatal(1);
        end

        $display("OK: controlador vuelve a IDLE");

        $display("================================");
        $display(" TODAS LAS PRUEBAS PASARON");
        $display("================================");

        $finish;
    end

endmodule

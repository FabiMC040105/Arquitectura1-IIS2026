
`timescale 1ns/1ps

module tb_l1_edge_cases;

    // RELOJ Y RESET

    logic clk;
    logic rst;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // INTERFAZ DEL PROCESADOR

    logic cpu_read;
    logic cpu_write;

    logic [31:0] cpu_addr;
    logic [31:0] cpu_write_data;

    wire [31:0] cpu_read_data;
    wire cpu_ready;
    wire cpu_stall;

    // INTERFAZ ENTRE L1 Y L2

    wire l2_req_valid;
    wire l2_req_ready;
    wire [31:0] l2_req_addr;

    wire l2_resp_valid;
    wire [255:0] l2_resp_data;

    wire l2_write_valid;
    wire l2_write_ready;
    wire [31:0] l2_write_addr;
    wire [31:0] l2_write_data;

    // Podemos bloquear las escrituras hacia L2 para llenar el write buffer de nuestra L1
    logic bloquear_escrituras;

    wire l2_write_ready_real;
    wire l2_write_valid_real;

    assign l2_write_ready =
        l2_write_ready_real && !bloquear_escrituras;

    assign l2_write_valid_real =
        l2_write_valid && !bloquear_escrituras;

    integer pruebas_ok;

    // INSTANCIA DE NUESTRA L1

    l1_data_system l1 (
        .clk(clk),
        .rst(rst),

        .cpu_read(cpu_read),
        .cpu_write(cpu_write),

        .cpu_addr(cpu_addr),
        .cpu_write_data(cpu_write_data),

        .cpu_read_data(cpu_read_data),
        .cpu_ready(cpu_ready),
        .cpu_stall(cpu_stall),

        .l2_req_valid(l2_req_valid),
        .l2_req_ready(l2_req_ready),
        .l2_req_addr(l2_req_addr),

        .l2_resp_valid(l2_resp_valid),
        .l2_resp_data(l2_resp_data),

        .l2_write_valid(l2_write_valid),
        .l2_write_ready(l2_write_ready),

        .l2_write_addr(l2_write_addr),
        .l2_write_data(l2_write_data)
    );

    // INSTANCIA DE L2 SIMULADA

    l2_memory_model #(
        .MEM_WORDS(4096),
        .READ_LATENCY(3)
    ) l2 (
        .clk(clk),
        .rst(rst),

        .l2_req_valid(l2_req_valid),
        .l2_req_ready(l2_req_ready),
        .l2_req_addr(l2_req_addr),

        .l2_resp_valid(l2_resp_valid),
        .l2_resp_data(l2_resp_data),

        .l2_write_valid(l2_write_valid_real),
        .l2_write_ready(l2_write_ready_real),

        .l2_write_addr(l2_write_addr),
        .l2_write_data(l2_write_data)
    );

    // TAREA PARA REALIZAR LOAD

    task realizar_load(
        input logic [31:0] direccion,
        input logic [31:0] esperado
    );
        integer ciclos;
        begin

            @(negedge clk);

            cpu_addr = direccion;
            cpu_read = 1'b1;
            cpu_write = 1'b0;

            ciclos = 0;
            #1;

            // Mantenemos la solicitud estable hasta que el procesador reciba el dato
            while (cpu_ready !== 1'b1 &&
                   ciclos < 100) begin

                @(negedge clk);
                ciclos = ciclos + 1;
            end

            if (cpu_ready !== 1'b1) begin
                $display(
                    "ERROR: LOAD no termino | addr=%h",
                    direccion
                );
                $fatal(1);
            end

            if (cpu_read_data !== esperado) begin
                $display(
                    "ERROR: LOAD incorrecto | addr=%h",
                    direccion
                );
                $display(
                    "Esperado=%0d | Recibido=%0d",
                    esperado, cpu_read_data
                );
                $fatal(1);
            end

            @(posedge clk);
            #1;

            cpu_read = 1'b0;

            $display(
                "OK: LOAD | addr=%h | dato=%0d | espera=%0d",
                direccion, esperado, ciclos
            );

        end
    endtask

    // TAREA PARA REALIZAR STORE

    task realizar_store(
        input logic [31:0] direccion,
        input logic [31:0] dato
    );
        integer ciclos;
        begin

            @(negedge clk);

            cpu_addr = direccion;
            cpu_write_data = dato;

            cpu_read = 1'b0;
            cpu_write = 1'b1;

            ciclos = 0;
            #1;

            while (cpu_ready !== 1'b1 &&
                   ciclos < 100) begin

                @(negedge clk);
                ciclos = ciclos + 1;
            end

            if (cpu_ready !== 1'b1) begin
                $display(
                    "ERROR: STORE no aceptado | addr=%h",
                    direccion
                );
                $fatal(1);
            end

            @(posedge clk);
            #1;

            cpu_write = 1'b0;

            $display(
                "OK: STORE | addr=%h | dato=%0d | espera=%0d",
                direccion, dato, ciclos
            );

        end
    endtask

    // ESPERAR A QUE LA FIFO QUEDE VACIA

    task esperar_fifo_vacia;
        integer ciclos;
        begin

            ciclos = 0;

            while (l1.buffer_empty !== 1'b1 &&
                   ciclos < 100) begin

                @(negedge clk);
                ciclos = ciclos + 1;
            end

            if (l1.buffer_empty !== 1'b1) begin
                $display("ERROR: FIFO no se vacio");
                $fatal(1);
            end

        end
    endtask

    // PRUEBAS DE CASOS EXTREMOS

    initial begin

        pruebas_ok = 0;

        rst = 1'b0;

        cpu_read = 1'b0;
        cpu_write = 1'b0;

        cpu_addr = 32'b0;
        cpu_write_data = 32'b0;

        bloquear_escrituras = 1'b0;

        $display("========================================");
        $display(" PRUEBAS DE CASOS EXTREMOS L1");
        $display("========================================");

        // PRUEBA 1: RESET INICIAL

        #2;
        rst = 1'b1;

        @(posedge clk);
        #1;
        rst = 1'b0;

        #1;

        if (l1.buffer_empty !== 1'b1 ||
            l2_req_ready !== 1'b1) begin

            $display("ERROR: reset inicial");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: reset inicial");

        // PRUEBA 2: LOAD DESALINEADO

        @(negedge clk);

        cpu_addr = 32'h00000023;
        cpu_read = 1'b1;

        #1;

        if (cpu_ready !== 1'b0 ||
            cpu_stall !== 1'b1 ||
            l2_req_valid !== 1'b0) begin

            $display("ERROR: LOAD desalineado");
            $fatal(1);
        end

        @(posedge clk);
        #1;
        cpu_read = 1'b0;

        pruebas_ok = pruebas_ok + 1;
        $display("OK: LOAD desalineado genera STALL");

        // PRUEBA 3: STORE DESALINEADO

        @(negedge clk);

        cpu_addr = 32'h00000025;
        cpu_write_data = 32'd777;
        cpu_write = 1'b1;

        #1;

        if (cpu_ready !== 1'b0 ||
            cpu_stall !== 1'b1 ||
            l1.buffer_count !== 0) begin

            $display("ERROR: STORE desalineado");
            $fatal(1);
        end

        @(posedge clk);
        #1;
        cpu_write = 1'b0;

        pruebas_ok = pruebas_ok + 1;
        $display("OK: STORE desalineado rechazado");

        // PRUEBA 4: LOAD Y STORE SIMULTANEOS

        @(negedge clk);

        cpu_addr = 32'h00000028;
        cpu_write_data = 32'd999;

        cpu_read = 1'b1;
        cpu_write = 1'b1;

        #1;

        if (cpu_ready !== 1'b0 ||
            cpu_stall !== 1'b1 ||
            l1.buffer_count !== 0 ||
            l2_req_valid !== 1'b0) begin

            $display("ERROR: LOAD y STORE simultaneos");
            $fatal(1);
        end

        @(posedge clk);
        #1;

        cpu_read = 1'b0;
        cpu_write = 1'b0;

        pruebas_ok = pruebas_ok + 1;
        $display("OK: LOAD y STORE simultaneos rechazados");

        // PRUEBA 5: LOAD MISS NORMAL

        realizar_load(32'h00000028, 32'd10);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: LOAD MISS y refill correctos");

        // PRUEBA 6: STORE HIT

        realizar_store(32'h00000028, 32'd888);

        esperar_fifo_vacia();

        if (l2.memory[10] !== 32'd888) begin

            $display("ERROR: STORE HIT no actualizo L2");
            $fatal(1);
        end

        realizar_load(32'h00000028, 32'd888);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: STORE HIT actualiza L1 y L2");

        // PRUEBA 7: RESET CON FIFO PENDIENTE

        bloquear_escrituras = 1'b1;

        realizar_store(32'h00000500, 32'd1234);
        realizar_store(32'h00000504, 32'd5678);

        if (l1.buffer_count !== 2) begin

            $display("ERROR: FIFO no contiene escrituras");
            $fatal(1);
        end

        @(negedge clk);
        rst = 1'b1;

        #1;

        if (l1.buffer_empty !== 1'b1 ||
            l1.buffer_count !== 0) begin

            $display("ERROR: reset no limpio FIFO");
            $fatal(1);
        end

        @(posedge clk);
        #1;

        rst = 1'b0;
        bloquear_escrituras = 1'b0;

        pruebas_ok = pruebas_ok + 1;
        $display("OK: reset limpia FIFO pendiente");

        // PRUEBA 8: RESET DURANTE MISS

        @(negedge clk);

        cpu_addr = 32'h00000600;
        cpu_read = 1'b1;

        // Esperamos a que el controlador comience la solicitud hacia L2
        wait (l2_req_valid === 1'b1);

        @(negedge clk);
        rst = 1'b1;
        cpu_read = 1'b0;

        #1;

        if (l2_resp_valid !== 1'b0 ||
            l1.miss_pending !== 1'b0) begin

            $display("ERROR: reset no cancelo MISS");
            $fatal(1);
        end

        @(posedge clk);
        #1;
        rst = 1'b0;

        pruebas_ok = pruebas_ok + 1;
        $display("OK: reset cancela MISS pendiente");

        // PRUEBA 9: FIFO LLENA

        bloquear_escrituras = 1'b1;

        realizar_store(32'h00000700, 32'd100);
        realizar_store(32'h00000704, 32'd200);
        realizar_store(32'h00000708, 32'd300);
        realizar_store(32'h0000070C, 32'd400);

        @(negedge clk);

        cpu_addr = 32'h00000710;
        cpu_write_data = 32'd500;
        cpu_write = 1'b1;

        #1;

        if (l1.buffer_full !== 1'b1 ||
            cpu_ready !== 1'b0 ||
            cpu_stall !== 1'b1) begin

            $display("ERROR: FIFO llena no genera STALL");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: FIFO llena genera STALL");

        // PRUEBA 10: RECUPERACION DE FIFO

        bloquear_escrituras = 1'b0;

        // Mantenemos la escritura pendiente hasta que L1 pueda aceptarla
        wait (cpu_ready === 1'b1);

        @(posedge clk);
        #1;
        cpu_write = 1'b0;

        esperar_fifo_vacia();

        if (l2.memory[448] !== 32'd100 ||
            l2.memory[449] !== 32'd200 ||
            l2.memory[450] !== 32'd300 ||
            l2.memory[451] !== 32'd400 ||
            l2.memory[452] !== 32'd500) begin

            $display("ERROR: FIFO no recupero escrituras");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: FIFO recuperada");

        // PRUEBA 11: LOAD DESPUES DE ESCRITURAS

        realizar_load(32'h00000700, 32'd100);
        realizar_load(32'h00000704, 32'd200);
        realizar_load(32'h00000708, 32'd300);
        realizar_load(32'h0000070C, 32'd400);
        realizar_load(32'h00000710, 32'd500);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: lecturas devuelven datos actualizados");

        // PRUEBA 12: LOAD CONSECUTIVOS

        // El reset no borra la memoria de L2. Por eso conservamos el valor escrito anteriormente
        realizar_load(32'h00000028, 32'd888);
        realizar_load(32'h0000002C, 32'd11);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: LOAD consecutivos correctos");

        // RESULTADO FINAL

        $display("========================================");
        $display(
            " PRUEBAS APROBADAS: %0d / 12",
            pruebas_ok
        );
        $display("========================================");

        if (pruebas_ok !== 12) begin
            $display("ERROR: faltan pruebas");
            $fatal(1);
        end

        $display(" TODAS LAS PRUEBAS EDGE CASES PASARON");
        $finish;

    end

    // 10. PROTECCION CONTRA ESPERA INFINITA

    initial begin
        #5000;

        $display("ERROR: tiempo de espera agotado");
        $fatal(1);
    end

endmodule
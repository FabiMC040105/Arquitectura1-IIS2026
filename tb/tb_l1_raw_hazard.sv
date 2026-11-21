
`timescale 1ns/1ps

module tb_l1_raw_hazard;

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

    // CONEXION DE LECTURA ENTRE L1 Y L2

    wire l2_req_valid;
    wire l2_req_ready;
    wire [31:0] l2_req_addr;

    wire l2_resp_valid;
    wire [255:0] l2_resp_data;

    // CONEXION DE ESCRITURA ENTRE L1 Y L2

    wire l2_write_valid;
    wire l2_write_ready;
    wire [31:0] l2_write_addr;
    wire [31:0] l2_write_data;

    // Permite detener temporalmente las escrituras para comprobar el comportamiento de la FIFO
    logic bloquear_escrituras;

    wire l2_write_ready_real;

    assign l2_write_ready =
        l2_write_ready_real && !bloquear_escrituras;

    // La L2 tampoco debe recibir una escritura mientras estamos bloqueando el canal
    wire l2_write_valid_real;

    assign l2_write_valid_real =
        l2_write_valid && !bloquear_escrituras;

    // Contador de pruebas aprobadas
    integer pruebas_ok;

    // 5. INSTANCIA DE NUESTRA CACHE L1

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

    // INSTANCIA DE LA L2 SIMULADA

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

            // Presentamos la lectura antes de un flanco positivo del reloj
            @(negedge clk);

            cpu_addr = direccion;
            cpu_read = 1'b1;
            cpu_write = 1'b0;

            ciclos = 0;
            #1;

            // Esperamos mientras la cache o L2 todavia no pueden entregar el dato
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

            $display(
                "OK: LOAD | addr=%h | dato=%0d | espera=%0d",
                direccion, cpu_read_data, ciclos
            );

            // Mantenemos la solicitud hasta el flanco en el que el procesador puede recibir el dato
            @(posedge clk);
            #1;

            cpu_read = 1'b0;

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

            // Si la FIFO esta llena, esperamos hasta que vuelva a existir espacio
            while (cpu_ready !== 1'b1 &&
                   ciclos < 100) begin

                @(negedge clk);
                ciclos = ciclos + 1;

            end

            if (cpu_ready !== 1'b1) begin
                $display(
                    "ERROR: STORE no fue aceptado | addr=%h",
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

    // TAREA PARA ESPERAR FIFO VACIA

    task esperar_fifo_vacia;
        integer ciclos;
        begin

            ciclos = 0;

            // Esperamos a que L2 acepte todas las escrituras pendientes
            while (l1.buffer_empty !== 1'b1 &&
                   ciclos < 100) begin

                @(negedge clk);
                ciclos = ciclos + 1;

            end

            if (l1.buffer_empty !== 1'b1) begin
                $display("ERROR: FIFO no se vacio");
                $fatal(1);
            end

            $display("OK: write buffer quedo vacio");

        end
    endtask

    // PRUEBAS DE INTEGRACION

    initial begin

        pruebas_ok = 0;

        rst = 1'b0;

        cpu_read = 1'b0;
        cpu_write = 1'b0;
        cpu_addr = 32'b0;
        cpu_write_data = 32'b0;

        bloquear_escrituras = 1'b0;

        $display("========================================");
        $display(" INTEGRACION L1 + L2 SIMULADA");
        $display("========================================");

        // PRUEBA 1: RESET

        #2;
        rst = 1'b1;

        @(posedge clk);
        #1;
        rst = 1'b0;

        #1;

        if (l1.buffer_empty !== 1'b1 ||
            l2_req_ready !== 1'b1) begin

            $display("ERROR: reset incorrecto");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: reset L1 y L2");

        // PRUEBA 2: LOAD MISS

        // La memoria inicia con valores iguales al indice de cada palabra
        realizar_load(32'h00000028, 32'd10);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: LOAD MISS atendido por L2");

        // PRUEBA 3: LOAD HIT

        // La linea ya fue instalada en L1
        realizar_load(32'h0000002C, 32'd11);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: LOAD HIT desde L1");

        // PRUEBA 4: STORE HIT

        // Actualizamos una palabra que ya esta almacenada en nuestra cache
        realizar_store(32'h00000028, 32'd999);

        esperar_fifo_vacia();

        if (l2.memory[10] !== 32'd999) begin
            $display("ERROR: STORE HIT no llego a L2");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: STORE HIT actualizo L2");

        // PRUEBA 5: RAW DESPUES DE STORE HIT

        realizar_load(32'h00000028, 32'd999);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: RAW despues de STORE HIT");

        // PRUEBA 6: STORE MISS

        // Esta direccion todavia no esta en L1
        realizar_store(32'h00000300, 32'd555);

        esperar_fifo_vacia();

        if (l2.memory[192] !== 32'd555) begin
            $display("ERROR: STORE MISS no llego a L2");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: STORE MISS almacenado en L2");

        // PRUEBA 7: RAW DESPUES DE STORE MISS

        // Como usamos no-write-allocate, el LOAD debe solicitar la linea a L2
        realizar_load(32'h00000300, 32'd555);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: RAW despues de STORE MISS");

        // PRUEBA 8: ESCRITURAS CONSECUTIVAS

        // Detenemos temporalmente las escrituras para acumular entradas en el write buffer
        bloquear_escrituras = 1'b1;

        realizar_store(32'h00000400, 32'd100);
        realizar_store(32'h00000404, 32'd200);
        realizar_store(32'h00000408, 32'd300);
        realizar_store(32'h0000040C, 32'd400);

        if (l1.buffer_count !== 4) begin
            $display("ERROR: FIFO no contiene 4 escrituras");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: cuatro escrituras en FIFO");

        // PRUEBA 9: FIFO LLENA GENERA STALL

        @(negedge clk);

        cpu_addr = 32'h00000410;
        cpu_write_data = 32'd500;
        cpu_write = 1'b1;

        #1;

        if (cpu_ready !== 1'b0 ||
            cpu_stall !== 1'b1) begin

            $display("ERROR: FIFO llena no genero STALL");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: FIFO llena genera STALL");

        // PRUEBA 10: RECUPERACION DE LA FIFO

        // Permitimos que L2 vuelva a recibir escrituras. Mantenemos el STORE pendiente hasta que la FIFO pueda aceptarlo
        bloquear_escrituras = 1'b0;

        wait (cpu_ready === 1'b1);

        @(posedge clk);
        #1;

        cpu_write = 1'b0;

        esperar_fifo_vacia();

        // Comprobamos que todas las escrituras llegaron a la memoria simulada
        if (l2.memory[256] !== 32'd100 ||
            l2.memory[257] !== 32'd200 ||
            l2.memory[258] !== 32'd300 ||
            l2.memory[259] !== 32'd400 ||
            l2.memory[260] !== 32'd500) begin

            $display("ERROR: escrituras no llegaron en orden");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: FIFO recuperada y datos correctos");

        // RESULTADO FINAL

        $display("========================================");
        $display(
            " PRUEBAS APROBADAS: %0d / 10",
            pruebas_ok
        );
        $display("========================================");

        if (pruebas_ok !== 10) begin
            $display("ERROR: faltan pruebas");
            $fatal(1);
        end

        $display(" TODAS LAS PRUEBAS RAW PASARON");
        $finish;

    end

    // PROTECCION CONTRA ESPERA INFINITA

    initial begin
        #5000;

        $display("ERROR: tiempo de espera agotado");
        $fatal(1);
    end

endmodule

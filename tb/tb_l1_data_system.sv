
`timescale 1ns/1ps

module tb_l1_data_system;

    // SEÑALES DEL TESTBENCH

    logic clk;
    logic rst;

    // Solicitudes del procesador
    logic cpu_read;
    logic cpu_write;
    logic [31:0] cpu_addr;
    logic [31:0] cpu_write_data;

    // Respuesta hacia el procesador
    wire [31:0] cpu_read_data;
    wire cpu_ready;
    wire cpu_stall;

    // Solicitudes de lectura hacia L2
    wire l2_req_valid;
    logic l2_req_ready;
    wire [31:0] l2_req_addr;

    // Respuesta de L2 con una linea completa
    logic l2_resp_valid;
    logic [255:0] l2_resp_data;

    // Interfaz de escritura hacia L2
    wire l2_write_valid;
    logic l2_write_ready;
    wire [31:0] l2_write_addr;
    wire [31:0] l2_write_data;

    // INSTANCIA DEL SISTEMA L1

    l1_data_system dut (
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

    // GENERACION DEL RELOJ

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // TAREA PARA REALIZAR STORE

    task realizar_store(
        input logic [31:0] direccion,
        input logic [31:0] dato
    );
        begin
            // Preparamos la solicitud antes del flanco para que L1 pueda aceptarla correctamente
            @(negedge clk);

            cpu_read = 1'b0;
            cpu_write = 1'b1;
            cpu_addr = direccion;
            cpu_write_data = dato;

            #1;

            // Si hay espacio en la FIFO, la escritura debe poder aceptarse
            if (cpu_ready !== 1'b1 ||
                cpu_stall !== 1'b0) begin

                $display("ERROR: STORE no fue aceptado");
                $fatal(1);
            end

            @(posedge clk);
            #1;

            // Desactivamos la solicitud para evitar insertar la misma escritura dos veces
            cpu_write = 1'b0;

            $display(
                "OK: STORE aceptado | addr=%h | dato=%0d",
                direccion, dato
            );
        end
    endtask

    // TAREA PARA RETIRAR UNA ESCRITURA

    task aceptar_escritura_l2(
        input logic [31:0] direccion,
        input logic [31:0] dato
    );
        begin
            @(negedge clk);
            #1;

            // La FIFO debe presentar primero la escritura mas antigua
            if (l2_write_valid !== 1'b1 ||
                l2_write_addr !== direccion ||
                l2_write_data !== dato) begin

                $display("ERROR: escritura incorrecta hacia L2");
                $display(
                    "Esperado: %h | %0d",
                    direccion, dato
                );
                $display(
                    "Recibido: %h | %0d",
                    l2_write_addr, l2_write_data
                );
                $fatal(1);
            end

            // Simulamos que L2 acepta la escritura
            l2_write_ready = 1'b1;

            @(posedge clk);
            #1;

            l2_write_ready = 1'b0;

            $display(
                "OK: L2 acepto escritura %h | %0d",
                direccion, dato
            );
        end
    endtask

    // PRUEBAS DE INTEGRACION

    initial begin

        rst = 1'b0;

        cpu_read = 1'b0;
        cpu_write = 1'b0;
        cpu_addr = 32'b0;
        cpu_write_data = 32'b0;

        l2_req_ready = 1'b0;
        l2_resp_valid = 1'b0;
        l2_resp_data = 256'b0;

        l2_write_ready = 1'b0;

        $display("================================");
        $display(" INTEGRACION L1 + WRITE BUFFER");
        $display("================================");

        // PRUEBA 1: RESET

        #2;
        rst = 1'b1;
        #10;
        rst = 1'b0;
        #1;

        if (dut.buffer_count !== 0 ||
            dut.buffer_empty !== 1'b1) begin

            $display("ERROR: write buffer no inicializado");
            $fatal(1);
        end

        $display("OK: sistema y write buffer inicializados");

        // PRUEBA 2: LOAD MISS

        @(negedge clk);

        cpu_addr = 32'h00000028;
        cpu_read = 1'b1;

        #1;

        if (cpu_stall !== 1'b1 ||
            cpu_ready !== 1'b0) begin

            $display("ERROR: no se genero STALL por MISS");
            $fatal(1);
        end

        $display("OK: LOAD MISS genera STALL");

        // PRUEBA 3: SOLICITUD A L2

        wait (l2_req_valid === 1'b1);

        if (l2_req_addr !== 32'h00000020) begin

            $display("ERROR: direccion incorrecta hacia L2");
            $fatal(1);
        end

        $display("OK: L1 solicita bloque 00000020");

        @(negedge clk);
        l2_req_ready = 1'b1;

        @(posedge clk);
        #1;
        l2_req_ready = 1'b0;

        $display("OK: L2 acepto solicitud de lectura");

        // PRUEBA 4: RESPUESTA DE L2

        repeat (3) @(posedge clk);

        @(negedge clk);

        l2_resp_data = {
            32'd80, 32'd70, 32'd60, 32'd50,
            32'd40, 32'd30, 32'd20, 32'd10
        };

        l2_resp_valid = 1'b1;

        @(posedge clk);
        #1;
        l2_resp_valid = 1'b0;

        wait (cpu_ready === 1'b1);
        #1;

        if (cpu_read_data !== 32'd30 ||
            cpu_stall !== 1'b0) begin

            $display("ERROR: lectura despues de refill");
            $fatal(1);
        end

        $display("OK: LOAD MISS completado, dato = 30");

        @(negedge clk);
        cpu_read = 1'b0;

        // PRUEBA 5: LOAD HIT

        @(negedge clk);

        cpu_addr = 32'h0000002C;
        cpu_read = 1'b1;

        #1;

        if (cpu_ready !== 1'b1 ||
            cpu_read_data !== 32'd40 ||
            l2_req_valid !== 1'b0) begin

            $display("ERROR: LOAD HIT incorrecto");
            $fatal(1);
        end

        $display("OK: LOAD HIT sin consultar L2");

        @(negedge clk);
        cpu_read = 1'b0;

        // PRUEBA 6: STORE HIT

        // La direccion 0x28 ya esta en L1. Cambiamos su valor de 30 a 999
        realizar_store(32'h00000028, 32'd999);

        if (dut.buffer_count !== 1 ||
            dut.buffer_empty !== 1'b0) begin

            $display("ERROR: STORE no entro en la FIFO");
            $fatal(1);
        end

        $display("OK: STORE HIT agregado a la FIFO");

        // COMPROBAR QUE STORE HIT ACTUALIZO L1

        // Despues de aceptar el STORE, activamos una lectura para consultar la misma palabra
        // Como todavia existe una escritura pendiente en la FIFO, el procesador debe permanecer detenido. Sin embargo, podemos revisar internamente si la cache tiene el dato nuevo

        @(negedge clk);

        cpu_addr = 32'h00000028;
        cpu_read = 1'b1;
        cpu_write = 1'b0;

        #1;

        // Primero comprobamos que la linea sigue almacenada dentro de nuestra cache
        if (dut.hit !== 1'b1) begin

            $display("ERROR: la linea ya no esta en L1");
            $fatal(1);
        end

        // Mostramos el estado de las señales para identificar que ocurre con la lectura
        $display("================================");
        $display(" VERIFICACION DE STORE HIT");
        $display("================================");

        $display("CACHE HIT: %b", dut.hit);
        $display("CACHE READ VALID: %b", dut.read_valid);
        $display("CACHE READ DATA: %0d", dut.read_data);
        $display("CPU READY: %b", cpu_ready);
        $display("CPU STALL: %b", cpu_stall);
        $display("BUFFER COUNT: %0d", dut.buffer_count);

        // La escritura sigue pendiente en la FIFO. Por eso esperamos que el procesador espere
        if (cpu_ready !== 1'b0 ||
            cpu_stall !== 1'b1) begin

            $display("ERROR: LOAD no espero escritura pendiente");
            $fatal(1);
        end

        $display("OK: LOAD detenido por escritura pendiente");

        // Dejamos de solicitar la lectura
        cpu_read = 1'b0;

        // PRUEBA 7: LOAD ESPERA POR FIFO PENDIENTE

        cpu_read = 1'b1;
        #1;

        if (cpu_ready !== 1'b0 ||
            cpu_stall !== 1'b1) begin

            $display("ERROR: LOAD no espero escritura pendiente");
            $fatal(1);
        end

        $display("OK: LOAD espera mientras hay STORE pendiente");

        // Cancelamos la lectura para comprobar primero la salida de la escritura
        cpu_read = 1'b0;

        // PRUEBA 8: L2 ACEPTA STORE HIT

        aceptar_escritura_l2(
            32'h00000028,
            32'd999
        );

        if (dut.buffer_empty !== 1'b1 ||
            dut.buffer_count !== 0) begin

            $display("ERROR: FIFO no quedo vacia");
            $fatal(1);
        end

        $display("OK: FIFO vacia despues de aceptar STORE");

        // PRUEBA 9: LEER VALOR ACTUALIZADO

        @(negedge clk);

        cpu_addr = 32'h00000028;
        cpu_read = 1'b1;

        #1;

        if (cpu_ready !== 1'b1 ||
            cpu_read_data !== 32'd999) begin

            $display("ERROR: LOAD no obtuvo dato actualizado");
            $fatal(1);
        end

        $display("OK: LOAD devuelve valor actualizado 999");

        @(negedge clk);
        cpu_read = 1'b0;

        // PRUEBA 10: STORE MISS

        // Esta direccion no fue instalada en L1
        realizar_store(32'h00000300, 32'd555);

        if (dut.buffer_count !== 1) begin

            $display("ERROR: STORE MISS no entro en FIFO");
            $fatal(1);
        end

        @(negedge clk);

        cpu_addr = 32'h00000300;
        #1;

        if (dut.hit !== 1'b0 ||
            dut.miss !== 1'b1) begin

            $display("ERROR: STORE MISS instalo una linea");
            $fatal(1);
        end

        $display("OK: STORE MISS no instala linea en L1");

        aceptar_escritura_l2(
            32'h00000300,
            32'd555
        );

        // PRUEBA 11: LLENAR LA FIFO

        // Mantenemos L2 ocupada para acumular cuatro escrituras pendientes
        l2_write_ready = 1'b0;

        realizar_store(32'h00000400, 32'd10);
        realizar_store(32'h00000404, 32'd20);
        realizar_store(32'h00000408, 32'd30);
        realizar_store(32'h0000040C, 32'd40);

        if (dut.buffer_full !== 1'b1 ||
            dut.buffer_count !== 4) begin

            $display("ERROR: FIFO no se lleno");
            $fatal(1);
        end

        $display("OK: FIFO llena con cuatro escrituras");

        // PRUEBA 12: STALL POR FIFO LLENA

        @(negedge clk);

        cpu_addr = 32'h00000410;
        cpu_write_data = 32'd50;
        cpu_write = 1'b1;

        #1;

        if (cpu_ready !== 1'b0 ||
            cpu_stall !== 1'b1) begin

            $display("ERROR: no se genero STALL por FIFO llena");
            $fatal(1);
        end

        $display("OK: STORE detenido porque FIFO esta llena");

        // PRUEBA 13: PUSH Y POP SIMULTANEOS

        // L2 acepta la escritura mas antigua. Al mismo tiempo, L1 puede guardar la nueva escritura del procesador
        l2_write_ready = 1'b1;

        #1;

        if (cpu_ready !== 1'b1 ||
            cpu_stall !== 1'b0 ||
            l2_write_valid !== 1'b1 ||
            l2_write_addr !== 32'h00000400 ||
            l2_write_data !== 32'd10) begin

            $display("ERROR: PUSH/POP simultaneos no disponibles");
            $fatal(1);
        end

        @(posedge clk);
        #1;

        cpu_write = 1'b0;
        l2_write_ready = 1'b0;

        if (dut.buffer_count !== 4 ||
            dut.buffer_full !== 1'b1) begin

            $display("ERROR: cantidad incorrecta tras PUSH/POP");
            $fatal(1);
        end

        $display("OK: PUSH y POP simultaneos con FIFO llena");

        // PRUEBA 14: COMPROBAR ORDEN FIFO

        aceptar_escritura_l2(32'h00000404, 32'd20);
        aceptar_escritura_l2(32'h00000408, 32'd30);
        aceptar_escritura_l2(32'h0000040C, 32'd40);
        aceptar_escritura_l2(32'h00000410, 32'd50);

        if (dut.buffer_empty !== 1'b1 ||
            dut.buffer_count !== 0) begin

            $display("ERROR: FIFO no termino vacia");
            $fatal(1);
        end

        $display("OK: orden FIFO conservado");

        $display("================================");
        $display(" TODAS LAS PRUEBAS PASARON");
        $display("================================");

        $finish;
    end

    // 7. PROTECCION CONTRA ESPERA INFINITA

    initial begin
        #3000;
        $display("ERROR: tiempo de espera agotado");
        $fatal(1);
    end

endmodule

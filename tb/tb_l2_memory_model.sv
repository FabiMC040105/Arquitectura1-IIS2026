
`timescale 1ns/1ps

module tb_l2_memory_model;

    // SEÑALES DEL TESTBENCH

    logic clk;
    logic rst;

    // Solicitud de lectura desde L1
    logic l2_req_valid;
    wire l2_req_ready;
    logic [31:0] l2_req_addr;

    // Respuesta de lectura hacia L1
    wire l2_resp_valid;
    wire [255:0] l2_resp_data;

    // Solicitud de escritura desde L1
    logic l2_write_valid;
    wire l2_write_ready;
    logic [31:0] l2_write_addr;
    logic [31:0] l2_write_data;

    // Contador de pruebas aprobadas
    integer pruebas_ok;

    // INSTANCIA DE L2 SIMULADA

    l2_memory_model #(
        .MEM_WORDS(4096),
        .READ_LATENCY(3)
    ) dut (
        .clk(clk),
        .rst(rst),

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

    // Un ciclo completo dura 10 ns
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // TAREA PARA SOLICITAR UNA LECTURA

    task solicitar_lectura(
        input logic [31:0] direccion
    );
        begin

            // Preparamos la direccion antes del flanco en el que L2 acepta la solicitud
            @(negedge clk);

            l2_req_addr = direccion;
            l2_req_valid = 1'b1;

            #1;

            if (l2_req_ready !== 1'b1) begin
                $display("ERROR: L2 no estaba disponible");
                $fatal(1);
            end

            // L2 captura la solicitud en este flanco
            @(posedge clk);
            #1;

            l2_req_valid = 1'b0;

            $display(
                "OK: solicitud de lectura aceptada en %h",
                direccion
            );

        end
    endtask

    // TAREA PARA ESPERAR UNA RESPUESTA

    task esperar_respuesta;
        integer ciclos;
        begin

            ciclos = 0;

            // Esperamos en los flancos negativos para observar las salidas ya estables
            // Esperamos la respuesta de L2
            // Con READ_LATENCY = 3, esta tarea observa cuatro flancos negativos antes de recibirla
            while (l2_resp_valid !== 1'b1 &&
                   ciclos < 10) begin

                @(negedge clk);
                ciclos = ciclos + 1;

            end

            if (l2_resp_valid !== 1'b1) begin
                $display("ERROR: L2 no devolvio respuesta");
                $fatal(1);
            end

            // Contamos cuatro flancos negativos desde que la solicitud fue aceptada
            // El primero corresponde al intervalo posterior a la aceptacion. Los siguientes tres corresponden al procesamiento de L2

            if (ciclos !== 4) begin

                $display(
                    "ERROR: latencia incorrecta, ciclos=%0d",
                    ciclos
                );

                $fatal(1);
            end

            $display(
                "OK: respuesta recibida despues de %0d ciclos",
                ciclos
            );

        end
    endtask

    // TAREA PARA REALIZAR UNA ESCRITURA

    task realizar_escritura(
        input logic [31:0] direccion,
        input logic [31:0] dato
    );
        begin

            @(negedge clk);

            l2_write_addr = direccion;
            l2_write_data = dato;
            l2_write_valid = 1'b1;

            #1;

            if (l2_write_ready !== 1'b1) begin
                $display("ERROR: L2 no acepto escritura");
                $fatal(1);
            end

            // La memoria se actualiza en este flanco
            @(posedge clk);
            #1;

            l2_write_valid = 1'b0;

            $display(
                "OK: escritura aceptada | addr=%h | dato=%0d",
                direccion, dato
            );

        end
    endtask

    // TAREA PARA COMPROBAR UNA PALABRA

    task comprobar_palabra(
        input integer posicion,
        input logic [31:0] esperado
    );
        logic [31:0] recibido;
        begin

            // Extraemos una palabra de 32 bits de la linea de 256 bits recibida
            recibido = l2_resp_data[posicion*32 +: 32];

            if (recibido !== esperado) begin

                $display(
                    "ERROR: palabra %0d | esperado=%0d | recibido=%0d",
                    posicion, esperado, recibido
                );

                $fatal(1);
            end

        end
    endtask

    // PRUEBAS

    initial begin

        pruebas_ok = 0;

        rst = 1'b0;

        l2_req_valid = 1'b0;
        l2_req_addr = 32'b0;

        l2_write_valid = 1'b0;
        l2_write_addr = 32'b0;
        l2_write_data = 32'b0;

        $display("========================================");
        $display(" PRUEBAS DE L2 MEMORY MODEL");
        $display("========================================");

        // PRUEBA 1: RESET

        #2;
        rst = 1'b1;

        @(posedge clk);
        #1;

        rst = 1'b0;
        #1;

        if (l2_req_ready !== 1'b1 ||
            l2_write_ready !== 1'b1 ||
            l2_resp_valid !== 1'b0) begin

            $display("ERROR: reset incorrecto");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: reset correcto");

        // PRUEBA 2: SOLICITUD DE LECTURA

        solicitar_lectura(32'h00000020);

        if (l2_req_ready !== 1'b0 ||
            l2_write_ready !== 1'b0) begin

            $display("ERROR: L2 no entro en estado ocupado");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: L2 queda ocupada durante lectura");

        // PRUEBA 3: LATENCIA DE LECTURA

        esperar_respuesta();

        pruebas_ok = pruebas_ok + 1;
        $display("OK: latencia de lectura correcta");

        // PRUEBA 4: CONTENIDO DE LA LINEA

        // La linea que comienza en 0x20 contiene las posiciones de memoria 8 hasta 15
        comprobar_palabra(0, 32'd8);
        comprobar_palabra(1, 32'd9);
        comprobar_palabra(2, 32'd10);
        comprobar_palabra(3, 32'd11);
        comprobar_palabra(4, 32'd12);
        comprobar_palabra(5, 32'd13);
        comprobar_palabra(6, 32'd14);
        comprobar_palabra(7, 32'd15);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: linea de 256 bits correcta");

        // PRUEBA 5: ESCRITURA EN MEMORIA

        realizar_escritura(
            32'h00000300,
            32'd555
        );

        // Comprobamos que la palabra se guardo en la posicion correspondiente
        if (dut.memory[192] !== 32'd555) begin

            $display("ERROR: escritura no guardada");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: escritura almacenada en memoria");

        // PRUEBA 6: RAW (STORE SEGUIDO DE LOAD)

        solicitar_lectura(32'h00000300);
        esperar_respuesta();

        // La primera palabra de esta linea debe contener el valor que acabamos de guardar
        comprobar_palabra(0, 32'd555);

        // Las otras palabras conservan sus valores
        comprobar_palabra(1, 32'd193);
        comprobar_palabra(2, 32'd194);
        comprobar_palabra(3, 32'd195);
        comprobar_palabra(4, 32'd196);
        comprobar_palabra(5, 32'd197);
        comprobar_palabra(6, 32'd198);
        comprobar_palabra(7, 32'd199);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: RAW devuelve el dato actualizado");

        // PRUEBA 7: NO ACEPTAR OPERACIONES OCUPADA

        solicitar_lectura(32'h00000040);

        // Intentamos presentar otra lectura mientras la primera sigue pendiente
        @(negedge clk);

        l2_req_addr = 32'h00000080;
        l2_req_valid = 1'b1;

        l2_write_addr = 32'h00000084;
        l2_write_data = 32'd999;
        l2_write_valid = 1'b1;

        #1;

        if (l2_req_ready !== 1'b0 ||
            l2_write_ready !== 1'b0) begin

            $display("ERROR: L2 acepto operaciones estando ocupada");
            $fatal(1);
        end

        $display("OK: L2 bloquea solicitudes mientras esta ocupada");

        // Retiramos las solicitudes no aceptadas
        l2_req_valid = 1'b0;
        l2_write_valid = 1'b0;

        // Dejamos que termine la lectura pendiente
        wait (l2_resp_valid === 1'b1);
        @(negedge clk);

        pruebas_ok = pruebas_ok + 1;

        // PRUEBA 8: DIRECCION FUERA DE RANGO

        solicitar_lectura(32'h00010000);
        esperar_respuesta();

        for (integer k = 0; k < 8; k = k + 1) begin
            comprobar_palabra(k, 32'd0);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: direccion fuera de rango devuelve ceros");

        // PRUEBA 9: RESET DURANTE LECTURA

        solicitar_lectura(32'h00000060);

        @(negedge clk);
        rst = 1'b1;

        #1;

        if (l2_resp_valid !== 1'b0 ||
            dut.read_busy !== 1'b0) begin

            $display("ERROR: reset no cancelo lectura");
            $fatal(1);
        end

        @(posedge clk);
        #1;
        rst = 1'b0;

        #1;

        if (l2_req_ready !== 1'b1) begin
            $display("ERROR: L2 no quedo disponible");
            $fatal(1);
        end

        pruebas_ok = pruebas_ok + 1;
        $display("OK: reset cancela lectura pendiente");

        // PRUEBA 10: NUEVA LECTURA DESPUES DE RESET

        solicitar_lectura(32'h00000020);
        esperar_respuesta();

        comprobar_palabra(0, 32'd8);
        comprobar_palabra(1, 32'd9);
        comprobar_palabra(2, 32'd10);
        comprobar_palabra(3, 32'd11);
        comprobar_palabra(4, 32'd12);
        comprobar_palabra(5, 32'd13);
        comprobar_palabra(6, 32'd14);
        comprobar_palabra(7, 32'd15);

        pruebas_ok = pruebas_ok + 1;
        $display("OK: L2 acepta nueva lectura despues del reset");

        // RESULTADO FINAL

        $display("========================================");
        $display(" PRUEBAS APROBADAS: %0d / 10", pruebas_ok);
        $display("========================================");

        if (pruebas_ok !== 10) begin
            $display("ERROR: faltan pruebas por aprobar");
            $fatal(1);
        end

        $display(" TODAS LAS PRUEBAS DE L2 PASARON");
        $finish;

    end

    // 9. PROTECCION CONTRA ESPERA INFINITA

    initial begin
        #3000;
        $display("ERROR: tiempo de espera agotado");
        $fatal(1);
    end

endmodule
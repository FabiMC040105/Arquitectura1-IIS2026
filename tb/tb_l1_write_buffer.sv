
`timescale 1ns/1ps

module tb_l1_write_buffer;

    // SEÑALES DEL TESTBENCH

    logic clk;
    logic rst;

    // Señales para guardar una nueva escritura
    logic push;
    logic [31:0] push_addr;
    logic [31:0] push_data;

    // Señal para retirar una escritura
    logic pop;

    // Datos que entrega la FIFO hacia L2
    wire [31:0] out_addr;
    wire [31:0] out_data;
    wire out_valid;

    // Estado actual de la FIFO
    wire full;
    wire empty;
    wire [2:0] count;

    // INSTANCIA DEL WRITE BUFFER

    // Utilizamos cuatro entradas, igual que en la arquitectura de nuestra cache L1
    l1_write_buffer #(
        .DEPTH(4)
    ) dut (
        .clk(clk),
        .rst(rst),

        .push(push),
        .push_addr(push_addr),
        .push_data(push_data),

        .pop(pop),

        .out_addr(out_addr),
        .out_data(out_data),
        .out_valid(out_valid),

        .full(full),
        .empty(empty),
        .count(count)
    );

    // GENERACION DEL RELOJ

    // Cada ciclo completo dura 10 ns
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // TAREA PARA INSERTAR UNA ESCRITURA

    task guardar_escritura(
        input logic [31:0] direccion,
        input logic [31:0] dato
    );
        begin
            // Preparamos la escritura antes del siguiente flanco positivo del reloj
            @(negedge clk);

            push_addr = direccion;
            push_data = dato;
            push = 1'b1;
            pop = 1'b0;

            // La FIFO guarda los datos en este flanco
            @(posedge clk);
            #1;

            push = 1'b0;

            $display(
                "PUSH: direccion=%h | dato=%0d | count=%0d",
                direccion, dato, count
            );
        end
    endtask

    // TAREA PARA RETIRAR UNA ESCRITURA

    task retirar_escritura(
        input logic [31:0] direccion_esperada,
        input logic [31:0] dato_esperado
    );
        begin
            @(negedge clk);

            // Antes de retirar la escritura, comprobamos que sea la mas antigua
            #1;

            if (out_valid !== 1'b1 ||
                out_addr !== direccion_esperada ||
                out_data !== dato_esperado) begin

                $display("ERROR: escritura incorrecta en la salida");
                $display(
                    "Esperado: %h | %0d",
                    direccion_esperada, dato_esperado
                );
                $display(
                    "Recibido: %h | %0d",
                    out_addr, out_data
                );

                $fatal(1);
            end

            // Simulamos que L2 acepta esta escritura
            pop = 1'b1;
            push = 1'b0;

            @(posedge clk);
            #1;

            pop = 1'b0;

            $display(
                "POP: direccion=%h | dato=%0d | count=%0d",
                direccion_esperada, dato_esperado, count
            );
        end
    endtask

    // PRUEBAS DEL WRITE BUFFER

    initial begin

        // Inicializamos todas las entradas
        rst = 1'b0;
        push = 1'b0;
        pop = 1'b0;
        push_addr = 32'b0;
        push_data = 32'b0;

        $display("================================");
        $display(" PRUEBAS DEL WRITE BUFFER L1");
        $display("================================");

        // PRUEBA 1: RESET

        #2;
        rst = 1'b1;
        #10;
        rst = 1'b0;
        #1;

        if (empty !== 1'b1 ||
            full !== 1'b0 ||
            count !== 0 ||
            out_valid !== 1'b0) begin

            $display("ERROR: FIFO no inicializada");
            $fatal(1);
        end

        $display("OK: FIFO inicializada y vacia");

        // PRUEBA 2: GUARDAR UNA ESCRITURA

        guardar_escritura(32'h00000028, 32'd999);

        if (count !== 1 ||
            empty !== 1'b0 ||
            out_valid !== 1'b1 ||
            out_addr !== 32'h00000028 ||
            out_data !== 32'd999) begin

            $display("ERROR: primera escritura incorrecta");
            $fatal(1);
        end

        $display("OK: primera escritura almacenada");

        // PRUEBA 3: GUARDAR MAS ESCRITURAS

        guardar_escritura(32'h00000040, 32'd150);
        guardar_escritura(32'h00000084, 32'd200);

        if (count !== 3 ||
            out_addr !== 32'h00000028 ||
            out_data !== 32'd999) begin

            $display("ERROR: orden FIFO incorrecto");
            $fatal(1);
        end

        $display("OK: tres escrituras almacenadas");
        $display("OK: la primera sigue al frente");

        // PRUEBA 4: ORDEN DE SALIDA

        retirar_escritura(32'h00000028, 32'd999);
        retirar_escritura(32'h00000040, 32'd150);
        retirar_escritura(32'h00000084, 32'd200);

        if (empty !== 1'b1 ||
            count !== 0 ||
            out_valid !== 1'b0) begin

            $display("ERROR: FIFO no quedo vacia");
            $fatal(1);
        end

        $display("OK: escrituras retiradas en orden FIFO");

        // PRUEBA 5: LLENAR LAS CUATRO ENTRADAS

        guardar_escritura(32'h00000100, 32'd10);
        guardar_escritura(32'h00000104, 32'd20);
        guardar_escritura(32'h00000108, 32'd30);
        guardar_escritura(32'h0000010C, 32'd40);

        if (full !== 1'b1 ||
            empty !== 1'b0 ||
            count !== 4) begin

            $display("ERROR: FIFO no detecto estado lleno");
            $fatal(1);
        end

        $display("OK: FIFO llena con cuatro escrituras");

        // PRUEBA 6: PUSH CUANDO ESTA LLENA

        // Intentamos guardar una quinta escritura. Como no retiramos ninguna, debe rechazarse
        @(negedge clk);

        push = 1'b1;
        pop = 1'b0;
        push_addr = 32'h00000110;
        push_data = 32'd50;

        @(posedge clk);
        #1;

        push = 1'b0;

        if (count !== 4 ||
            full !== 1'b1 ||
            out_addr !== 32'h00000100 ||
            out_data !== 32'd10) begin

            $display("ERROR: escritura aceptada con FIFO llena");
            $fatal(1);
        end

        $display("OK: FIFO llena no sobrescribe datos");

        // PRUEBA 7: PUNTEROS CIRCULARES

        // Retiramos las cuatro escrituras. Esto tambien comprueba que la quinta escritura fue rechazada correctamente
        retirar_escritura(32'h00000100, 32'd10);
        retirar_escritura(32'h00000104, 32'd20);
        retirar_escritura(32'h00000108, 32'd30);
        retirar_escritura(32'h0000010C, 32'd40);

        // Despues de completar una vuelta, debemos poder volver a guardar datos
        guardar_escritura(32'h00000200, 32'd500);

        if (out_addr !== 32'h00000200 ||
            out_data !== 32'd500 ||
            count !== 1) begin

            $display("ERROR: punteros circulares incorrectos");
            $fatal(1);
        end

        $display("OK: punteros circulares funcionan");

        // PRUEBA 8: PUSH Y POP SIMULTANEOS

        // Tenemos una escritura pendiente: direccion 0x200 con dato 500
        // En el mismo ciclo retiraremos esa escritura e insertaremos una nueva
        @(negedge clk);

        push = 1'b1;
        push_addr = 32'h00000204;
        push_data = 32'd600;
        pop = 1'b1;

        @(posedge clk);
        #1;

        push = 1'b0;
        pop = 1'b0;

        // La cantidad debe seguir siendo uno, porque salió una escritura y entro otra
        if (count !== 1 ||
            out_valid !== 1'b1 ||
            out_addr !== 32'h00000204 ||
            out_data !== 32'd600) begin

            $display("ERROR: PUSH y POP simultaneos");
            $fatal(1);
        end

        $display("OK: PUSH y POP simultaneos");

        // Retiramos la ultima escritura
        retirar_escritura(32'h00000204, 32'd600);

        if (empty !== 1'b1 || count !== 0) begin
            $display("ERROR: FIFO no quedo vacia");
            $fatal(1);
        end

        $display("================================");
        $display(" TODAS LAS PRUEBAS FIFO PASARON");
        $display("================================");

        $finish;
    end

    // PROTECCION CONTRA ESPERA INFINITA

    // Si ocurre algun problema y la simulacion no termina, detenemos la prueba
    initial begin
        #2000;
        $display("ERROR: tiempo de espera agotado");
        $fatal(1);
    end

endmodule
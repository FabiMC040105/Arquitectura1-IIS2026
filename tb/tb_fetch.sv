`timescale 1ns/1ps

module tb_fetch;

    // Fetch ya no tiene PC propio: la direccion es una entrada.
    logic [31:0] pc_i;

    // Salidas del modulo Fetch.
    logic [127:0] bundle_o;
    logic valid_o;

    // Creamos Fetch con una memoria pequeña para las pruebas.
    // 16 palabras de 4 bytes = 64 bytes = 4 bundles.
    fetch #(
        .IMEM_WORDS(16)
    ) dut (
        .pc_i(pc_i),
        .bundle_o(bundle_o),
        .valid_o(valid_o)
    );

    initial begin
        pc_i = 32'h00000000;

        // Cargamos bundles conocidos en la memoria de instrucciones.
        // Cada posicion es un bundle completo de 128 bits.
        dut.instruction_memory_inst.memory[0] = {
            32'h00000044,
            32'h00000033,
            32'h00000022,
            32'h00000011
        };

        dut.instruction_memory_inst.memory[1] = {
            32'h00000088,
            32'h00000077,
            32'h00000066,
            32'h00000055
        };

        dut.instruction_memory_inst.memory[2] = {
            32'h000000A4,
            32'h000000A3,
            32'h000000A2,
            32'h000000A1
        };

        // 1. Lectura del bundle en la direccion 0x00.
        #1;

        if (valid_o !== 1'b1)
            $fatal(1, "ERROR: primer bundle invalido");

        if (bundle_o !== {
            32'h00000044,
            32'h00000033,
            32'h00000022,
            32'h00000011
        })
            $fatal(1, "ERROR: slots incorrectos en el primer bundle");

        $display("PASS: lectura y orden de los cuatro slots");

        // 2. El bundle leido sigue al PC que entra por pc_i.
        pc_i = 32'h00000010;
        #1;

        if (valid_o !== 1'b1)
            $fatal(1, "ERROR: bundle invalido en direccion 0x10");

        if (bundle_o !== {
            32'h00000088,
            32'h00000077,
            32'h00000066,
            32'h00000055
        })
            $fatal(1, "ERROR: bundle incorrecto en direccion 0x10");

        $display("PASS: el bundle sigue al PC de entrada");

        // 3. Una direccion posterior lee el bundle correspondiente.
        pc_i = 32'h00000020;
        #1;

        if (bundle_o !== {
            32'h000000A4,
            32'h000000A3,
            32'h000000A2,
            32'h000000A1
        })
            $fatal(1, "ERROR: bundle incorrecto en direccion 0x20");

        $display("PASS: lectura en direccion 0x20");

        // 4. Direccion no alineada a 16 bytes: debe marcarse invalida.
        pc_i = 32'h00000023;
        #1;

        if (valid_o !== 1'b0)
            $fatal(1, "ERROR: se acepto una direccion desalineada");

        $display("PASS: deteccion de direccion desalineada");

        // 5. Direccion fuera del rango de la memoria.
        pc_i = 32'h00001000;
        #1;

        if (valid_o !== 1'b0)
            $fatal(1, "ERROR: se acepto una direccion fuera de rango");

        $display("PASS: deteccion de direccion fuera de rango");

        $display("TODAS LAS PRUEBAS DE FETCH PASARON");
        $finish;
    end

endmodule

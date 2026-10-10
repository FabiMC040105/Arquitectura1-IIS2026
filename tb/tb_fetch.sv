`timescale 1ns/1ps

module tb_fetch;

    // Entradas del modulo Fetch.
    logic clk_i;
    logic rst_i;
    logic stall_i;
    logic redirect_i;
    logic [31:0] redirect_pc_i;

    // Salidas del modulo Fetch.
    logic [31:0] pc_o;
    logic [127:0] bundle_o;
    logic valid_o;

    // Creamos Fetch con una memoria pequeña para las pruebas.
    // 16 palabras de 4 bytes = 64 bytes.
    fetch #(
        .IMEM_WORDS(16),
        .RESET_PC(32'h00000000)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_i),
        .redirect_i(redirect_i),
        .redirect_pc_i(redirect_pc_i),
        .pc_o(pc_o),
        .bundle_o(bundle_o),
        .valid_o(valid_o)
    );

    // Generador del reloj: periodo de 10 ns.
    initial clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    initial begin
        // Estado inicial de las entradas.
        rst_i = 1'b1;
        stall_i = 1'b0;
        redirect_i = 1'b0;
        redirect_pc_i = 32'b0;

        // Cargamos datos conocidos en la memoria.
        // Estas asignaciones se hacen solo para la simulacion.
        dut.imem[0]  = 32'h00000011;
        dut.imem[1]  = 32'h00000022;
        dut.imem[2]  = 32'h00000033;
        dut.imem[3]  = 32'h00000044;

        dut.imem[4]  = 32'h00000055;
        dut.imem[5]  = 32'h00000066;
        dut.imem[6]  = 32'h00000077;
        dut.imem[7]  = 32'h00000088;

        dut.imem[8]  = 32'h000000A1;
        dut.imem[9]  = 32'h000000A2;
        dut.imem[10] = 32'h000000A3;
        dut.imem[11] = 32'h000000A4;

        // 1. Probamos el reinicio del PC.
        @(posedge clk_i);
        #1;

        if (pc_o !== 32'h00000000)
            $fatal(1, "ERROR: PC incorrecto despues del reset");

        // Quitamos el reset despues del flanco de reloj.
        @(negedge clk_i);
        rst_i = 1'b0;
        #1;

        // 2. Probamos la lectura del primer bundle.
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

        // 3. El PC debe avanzar de 0x00 a 0x10.
        @(posedge clk_i);
        #1;

        if (pc_o !== 32'h00000010)
            $fatal(1, "ERROR: el PC no avanzo 16 bytes");

        if (bundle_o !== {
            32'h00000088,
            32'h00000077,
            32'h00000066,
            32'h00000055
        })
            $fatal(1, "ERROR: bundle incorrecto en direccion 0x10");

        $display("PASS: avance secuencial de 16 bytes");

        // 4. Activamos stall y comprobamos que el PC no avance.
        @(negedge clk_i);
        stall_i = 1'b1;

        @(posedge clk_i);
        #1;

        if (pc_o !== 32'h00000010)
            $fatal(1, "ERROR: el PC avanzo durante stall");

        $display("PASS: stall mantiene el PC");

        // 5. Probamos un salto a la direccion 0x20.
        // El salto debe funcionar aunque stall siga activo.
        @(negedge clk_i);
        redirect_pc_i = 32'h00000020;
        redirect_i = 1'b1;

        @(posedge clk_i);
        #1;

        if (pc_o !== 32'h00000020)
            $fatal(1, "ERROR: la redireccion no cambio el PC");

        if (bundle_o !== {
            32'h000000A4,
            32'h000000A3,
            32'h000000A2,
            32'h000000A1
        })
            $fatal(1, "ERROR: bundle incorrecto despues del salto");

        $display("PASS: redireccion del PC");

        // Bajamos redirect para que no se repita el salto.
        @(negedge clk_i);
        redirect_i = 1'b0;

        // Quitamos stall para las siguientes pruebas.
        stall_i = 1'b0;

        // 6. Probamos una direccion que no esta alineada a 16 bytes.
        // 0x23 no es multiplo de 16.
        redirect_pc_i = 32'h00000023;
        redirect_i = 1'b1;

        @(posedge clk_i);
        #1;

        if (pc_o !== 32'h00000023)
            $fatal(1, "ERROR: no se cargo el PC de prueba");

        // Desactivamos la redireccion despues de comprobar el PC.
        @(negedge clk_i);
        redirect_i = 1'b0;
        #1;

        if (valid_o !== 1'b0)
            $fatal(1, "ERROR: se acepto una direccion desalineada");

        $display("PASS: deteccion de direccion desalineada");

        $display("TODAS LAS PRUEBAS DE FETCH PASARON");
        $finish;
    end

endmodule
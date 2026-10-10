`timescale 1ns/1ps

module lsu_tb;

    logic [31:0] base_addr;
    logic [11:0] offset;

    logic [31:0] store_data;

    logic load_enable;
    logic store_enable;

    logic [31:0] effective_addr;
    logic [31:0] mem_write_data;

    logic mem_read;
    logic mem_write;


    // ============================================================
    // DUT
    // ============================================================

    lsu dut (
        .base_addr(base_addr),
        .offset(offset),

        .store_data(store_data),

        .load_enable(load_enable),
        .store_enable(store_enable),

        .effective_addr(effective_addr),
        .mem_write_data(mem_write_data),

        .mem_read(mem_read),
        .mem_write(mem_write)
    );


    initial begin

        $dumpfile("lsu.vcd");
        $dumpvars(0, lsu_tb);


        // Valores iniciales
        base_addr    = 32'h00000000;
        offset       = 12'h000;
        store_data   = 32'h00000000;

        load_enable  = 0;
        store_enable = 0;

        #1;


        // --------------------------------------------------------
        // TEST 1
        // LOAD con offset positivo
        //
        // base = 100
        // offset = 20
        // resultado = 120
        // --------------------------------------------------------

        base_addr   = 32'd100;
        offset      = 12'd20;
        load_enable = 1;

        #1;

        if (
            effective_addr == 32'd120 &&
            mem_read == 1 &&
            mem_write == 0
        )
            $display("TEST 1 PASS - LOAD con offset positivo");
        else
            $display(
                "TEST 1 FAIL - addr=%0d read=%b write=%b",
                effective_addr,
                mem_read,
                mem_write
            );


        // --------------------------------------------------------
        // TEST 2
        // LOAD con offset negativo
        //
        // base = 100
        // offset = -4
        // resultado = 96
        // --------------------------------------------------------

        base_addr   = 32'd100;
        offset      = 12'hFFC;   // -4 en 12 bits

        #1;

        if (effective_addr == 32'd96)
            $display("TEST 2 PASS - Offset negativo correcto");
        else
            $display(
                "TEST 2 FAIL - Esperado 96, obtenido %0d",
                effective_addr
            );


        // --------------------------------------------------------
        // TEST 3
        // STORE
        // --------------------------------------------------------

        load_enable  = 0;
        store_enable = 1;

        base_addr  = 32'h00000100;
        offset     = 12'h008;
        store_data = 32'hCAFEBABE;

        #1;

        if (
            effective_addr == 32'h00000108 &&
            mem_write_data == 32'hCAFEBABE &&
            mem_write == 1 &&
            mem_read == 0
        )
            $display("TEST 3 PASS - STORE correcto");
        else
            $display("TEST 3 FAIL - Error en STORE");


        // --------------------------------------------------------
        // TEST 4
        // LSU inactiva
        // --------------------------------------------------------

        load_enable  = 0;
        store_enable = 0;

        #1;

        if (
            mem_read == 0 &&
            mem_write == 0
        )
            $display("TEST 4 PASS - LSU inactiva correctamente");
        else
            $display("TEST 4 FAIL - Señales incorrectas");


        // --------------------------------------------------------
        // TEST 5
        // Offset mínimo -2048
        // --------------------------------------------------------

        base_addr = 32'd4096;
        offset    = 12'h800;

        #1;

        if (effective_addr == 32'd2048)
            $display("TEST 5 PASS - Offset minimo -2048");
        else
            $display(
                "TEST 5 FAIL - Esperado 2048, obtenido %0d",
                effective_addr
            );


        // --------------------------------------------------------
        // TEST 6
        // Offset máximo +2047
        // --------------------------------------------------------

        base_addr = 32'd4096;
        offset    = 12'h7FF;

        #1;

        if (effective_addr == 32'd6143)
            $display("TEST 6 PASS - Offset maximo +2047");
        else
            $display(
                "TEST 6 FAIL - Esperado 6143, obtenido %0d",
                effective_addr
            );


        #10;

        $display("Fin del test de LSU");

        $finish;

    end

endmodule
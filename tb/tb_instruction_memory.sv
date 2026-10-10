`timescale 1ns/1ps

module instruction_memory_tb;

    logic [31:0]  addr;

    logic [127:0] bundle_out;
    logic         access_error;


    // ============================================================
    // DUT
    // ============================================================

    instruction_memory #(
        .MEM_BYTES(65536),
        .PROGRAM_FILE("tb/program_test.mem")
    ) dut (
        .addr(addr),

        .bundle_out(bundle_out),
        .access_error(access_error)
    );


    // ============================================================
    // Campos individuales del bundle
    // ============================================================

    logic [31:0] alu_slot;
    logic [31:0] lsu_slot;
    logic [31:0] bru_slot;
    logic [31:0] crypto_slot;


    always_comb begin

        alu_slot    = bundle_out[31:0];
        lsu_slot    = bundle_out[63:32];
        bru_slot    = bundle_out[95:64];
        crypto_slot = bundle_out[127:96];

    end


    // ============================================================
    // Test
    // ============================================================

    initial begin

        $dumpfile("instruction_memory.vcd");
        $dumpvars(0, instruction_memory_tb);


        // ========================================================
        // TEST 1
        //
        // PC = 0
        //
        // Bundle esperado:
        //
        // CRYPTO = 44444444
        // BRU    = 33333333
        // LSU    = 22222222
        // ALU    = 11111111
        //
        // ========================================================

        addr = 32'h00000000;

        #1;

        if (
            alu_slot    == 32'h11111111 &&
            lsu_slot    == 32'h22222222 &&
            bru_slot    == 32'h33333333 &&
            crypto_slot == 32'h44444444 &&
            access_error == 0
        )
            $display(
                "TEST 1 PASS - Bundle 0 leido correctamente"
            );
        else begin
            $display(
                "TEST 1 FAIL - Error leyendo bundle 0"
            );

            $display("ALU    = %h", alu_slot);
            $display("LSU    = %h", lsu_slot);
            $display("BRU    = %h", bru_slot);
            $display("CRYPTO = %h", crypto_slot);
        end


        // ========================================================
        // TEST 2
        //
        // PC = 16
        //
        // Bundle completamente NOP.
        //
        // ========================================================

        addr = 32'h00000010;

        #1;

        if (
            bundle_out == 128'b0 &&
            access_error == 0
        )
            $display(
                "TEST 2 PASS - Bundle NOP correcto"
            );
        else
            $display(
                "TEST 2 FAIL - Bundle NOP incorrecto"
            );


        // ========================================================
        // TEST 3
        //
        // PC = 32
        //
        // ========================================================

        addr = 32'h00000020;

        #1;

        if (
            alu_slot    == 32'hAAAAAAAA &&
            lsu_slot    == 32'hBBBBBBBB &&
            bru_slot    == 32'hCCCCCCCC &&
            crypto_slot == 32'hDDDDDDDD
        )
            $display(
                "TEST 3 PASS - Bundle 2 correcto"
            );
        else begin
            $display(
                "TEST 3 FAIL - Bundle 2 incorrecto"
            );

            $display("ALU    = %h", alu_slot);
            $display("LSU    = %h", lsu_slot);
            $display("BRU    = %h", bru_slot);
            $display("CRYPTO = %h", crypto_slot);
        end


        // ========================================================
        // TEST 4
        //
        // PC = 48
        //
        // Comprobar otra combinación.
        //
        // ========================================================

        addr = 32'h00000030;

        #1;

        if (
            alu_slot    == 32'h2468ACE0 &&
            lsu_slot    == 32'h13579BDF &&
            bru_slot    == 32'h89ABCDEF &&
            crypto_slot == 32'h01234567
        )
            $display(
                "TEST 4 PASS - Separacion de slots correcta"
            );
        else
            $display(
                "TEST 4 FAIL - Error separando slots"
            );


        // ========================================================
        // TEST 5
        //
        // Dirección desalineada.
        //
        // ========================================================

        addr = 32'h00000004;

        #1;

        if (access_error == 1)
            $display(
                "TEST 5 PASS - Direccion desalineada detectada"
            );
        else
            $display(
                "TEST 5 FAIL - No detecto direccion desalineada"
            );


        // ========================================================
        // TEST 6
        //
        // Dirección fuera de la memoria.
        //
        // 64 KB = 0x10000
        //
        // ========================================================

        addr = 32'h00010000;

        #1;

        if (access_error == 1)
            $display(
                "TEST 6 PASS - Direccion fuera de rango detectada"
            );
        else
            $display(
                "TEST 6 FAIL - No detecto acceso fuera de rango"
            );


        // ========================================================
        // TEST 7
        //
        // Última dirección válida.
        //
        // 65536 - 16 = 65520 = 0xFFF0
        //
        // Como no cargamos nada ahí, debe contener NOP.
        //
        // ========================================================

        addr = 32'h0000FFF0;

        #1;

        if (
            access_error == 0 &&
            bundle_out == 128'b0
        )
            $display(
                "TEST 7 PASS - Ultimo bundle valido accesible"
            );
        else
            $display(
                "TEST 7 FAIL - Error en limite superior"
            );


        #10;

        $display("============================================");
        $display("Fin del test de Instruction Memory");
        $display("============================================");

        $finish;

    end

endmodule
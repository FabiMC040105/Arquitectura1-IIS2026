`timescale 1ns/1ps

module data_memory_tb;

    logic clk;
    logic rst;

    logic mem_read;
    logic mem_write;

    logic [31:0] addr;
    logic [31:0] write_data;

    logic [31:0] read_data;
    logic access_error;


    // ============================================================
    // DUT
    // ============================================================

    data_memory #(
        .MEM_BYTES(65536)
    ) dut (
        .clk(clk),
        .rst(rst),

        .mem_read(mem_read),
        .mem_write(mem_write),

        .addr(addr),
        .write_data(write_data),

        .read_data(read_data),
        .access_error(access_error)
    );


    // ============================================================
    // Clock
    // ============================================================

    always #5 clk = ~clk;


    // ============================================================
    // Test
    // ============================================================

    initial begin

        $dumpfile("data_memory.vcd");
        $dumpvars(0, data_memory_tb);

        clk        = 0;
        rst        = 1;
        mem_read   = 0;
        mem_write  = 0;
        addr       = 0;
        write_data = 0;

        #10;

        rst = 0;


        // --------------------------------------------------------
        // TEST 1
        // STORE 0x12345678 en dirección 0
        // --------------------------------------------------------

        addr       = 32'h00000000;
        write_data = 32'h12345678;
        mem_write  = 1;

        #10;

        mem_write = 0;


        // --------------------------------------------------------
        // TEST 2
        // LOAD desde dirección 0
        // --------------------------------------------------------

        mem_read = 1;

        #1;

        if (read_data == 32'h12345678)
            $display("TEST 1 PASS - LOAD/STORE correcto");
        else
            $display(
                "TEST 1 FAIL - Esperado 12345678, obtenido %h",
                read_data
            );

        mem_read = 0;


        // --------------------------------------------------------
        // TEST 3
        // Comprobar little-endian internamente
        // --------------------------------------------------------

        if (
            dut.memory[0] == 8'h78 &&
            dut.memory[1] == 8'h56 &&
            dut.memory[2] == 8'h34 &&
            dut.memory[3] == 8'h12
        )
            $display("TEST 2 PASS - Little-endian correcto");
        else
            $display("TEST 2 FAIL - Error de endianness");


        // --------------------------------------------------------
        // TEST 4
        // Otra dirección
        // --------------------------------------------------------

        addr       = 32'h00000100;
        write_data = 32'hCAFEBABE;
        mem_write  = 1;

        #10;

        mem_write = 0;
        mem_read  = 1;

        #1;

        if (read_data == 32'hCAFEBABE)
            $display("TEST 3 PASS - Segunda escritura correcta");
        else
            $display(
                "TEST 3 FAIL - Esperado CAFEBABE, obtenido %h",
                read_data
            );

        mem_read = 0;


        // --------------------------------------------------------
        // TEST 5
        // Acceso fuera de rango
        // --------------------------------------------------------

        addr     = 32'h00010000;
        mem_read = 1;

        #1;

        if (access_error)
            $display("TEST 4 PASS - Acceso fuera de rango detectado");
        else
            $display("TEST 4 FAIL - No detectó acceso inválido");

        mem_read = 0;


        #10;

        $display("Fin del test de data_memory");

        $finish;

    end

endmodule
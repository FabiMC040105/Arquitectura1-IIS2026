
`timescale 1ns/1ps

module tb_cipher;

    logic clk_i = 0;
    logic rst_i = 1;
    logic stall_i = 0;

    integer ciclo;
    integer max_ciclos;
    integer bytes_salida;
    integer archivo;
    integer i;

    string nombre_salida;

    top dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_i)
    );

    always #5 clk_i = ~clk_i;

    initial begin
        max_ciclos = 1000000;
        bytes_salida = 8;
        nombre_salida = "salida_cifrada.bin";

        if (!$value$plusargs("MAX_CYCLES=%d", max_ciclos))
            max_ciclos = 1000000;

        if (!$value$plusargs("OUTPUT_BYTES=%d", bytes_salida))
            bytes_salida = 8;

        if (!$value$plusargs("OUTPUT_FILE=%s", nombre_salida))
            nombre_salida = "salida_cifrada.bin";

        if (bytes_salida < 1 || bytes_salida > 65536)
            $fatal(1, "Cantidad de bytes de salida fuera de rango");

        $display("========================================");
        $display(" PROCESAMIENTO EN HARDWARE VLIW/FEISTEL");
        $display(" Archivo de salida: %s", nombre_salida);
        $display(" Bytes solicitados: %0d", bytes_salida);
        $display(" Ciclos de ejecucion: %0d", max_ciclos);
        $display("========================================");

        repeat (4) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 0;

        for (ciclo = 0; ciclo < max_ciclos; ciclo = ciclo + 1)
            @(posedge clk_i);

        #1;

        archivo = $fopen(nombre_salida, "wb");

        if (archivo == 0)
            $fatal(1, "No se pudo crear el archivo de salida");

        for (i = 0; i < bytes_salida; i = i + 1)
            $fwrite(archivo, "%c", dut.data_memory_inst.memory[i]);

        $fclose(archivo);

        $display("Archivo escrito correctamente.");
        $display("Bytes escritos: %0d", bytes_salida);
        $finish;
    end

endmodule
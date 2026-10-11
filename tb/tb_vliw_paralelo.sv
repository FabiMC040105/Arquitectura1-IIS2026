
`timescale 1ns/1ps

module tb_vliw_paralelo;

    // Reloj y reset del procesador
    logic clk_i = 0;
    logic rst_i;
    logic stall_i;

    // Señales para observar el procesador
    wire [31:0] pc_o;
    wire [127:0] bundle_o;
    wire fetch_valid_o;

    // Instrucciones de prueba
    // ALU: ADDI x2, x0, 9
    localparam [31:0] INST_ALU = {
        8'b0, 12'd9, 4'd0, 4'd2, 1'b1, 3'b001
    };

    // LSU: LOAD x3, 0(x0)
    localparam [31:0] INST_LSU = {
        10'b0, 12'd0, 4'd0, 4'd3, 2'b01
    };

    integer i;

    // Instancia del procesador completo
    top #(
        .IMEM_WORDS(64),
        .PROGRAM_FILE("program_test.mem")
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_i),
        .pc_o(pc_o),
        .bundle_o(bundle_o),
        .fetch_valid_o(fetch_valid_o)
    );

    // Reloj de 10 nanosegundos
    always #5 clk_i = ~clk_i;

    initial begin
        rst_i = 1;
        stall_i = 0;

        // Esperar a que las memorias se inicialicen
        #1;

        // Limpiar el programa de prueba
        for (i = 0; i < 16; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 128'b0;

        // Bundle 0: ALU y LSU trabajan simultaneamente
        // Los slots BRU y FEIST se rellenan con ceros
        dut.fetch_inst.instruction_memory_inst.memory[0] = {
            64'b0,
            INST_LSU,
            INST_ALU
        };

        // Preparar el dato que LOAD debe leer
        // Memoria little-endian
        dut.data_memory_inst.memory[0] = 8'h44;
        dut.data_memory_inst.memory[1] = 8'h33;
        dut.data_memory_inst.memory[2] = 8'h22;
        dut.data_memory_inst.memory[3] = 8'h11;

        // Liberar reset
        @(negedge clk_i);
        rst_i = 0;

        // Esperar a que el bundle llegue a WB
        repeat (10) @(posedge clk_i);
        #1;

        // PRUEBA 1: Resultado ALU
        if (dut.regfile_inst.regs[2] !== 32'd9)
            $fatal(1, "ERROR: ALU no escribio 9 en x2");

        $display("PASS: ALU escribio x2 = 9");

        // PRUEBA 2: Resultado LSU
        if (dut.regfile_inst.regs[3] !== 32'h11223344)
            $fatal(1, "ERROR: LSU no escribio el dato correcto");

        $display("PASS: LSU escribio x3 = 11223344");

        // PRUEBA 3: x0 permanece en cero
        if (dut.regfile_inst.regs[0] !== 32'b0)
            $fatal(1, "ERROR: x0 fue modificado");

        $display("PASS: x0 permanece en cero");

        $display("--------------------------------");
        $display("PRUEBA VLIW PARALELA SUPERADA");
        $display("--------------------------------");

        $finish;
    end

endmodule

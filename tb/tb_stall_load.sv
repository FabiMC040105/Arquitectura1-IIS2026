
`timescale 1ns/1ps

module tb_stall_load;

    logic clk_i = 0;
    logic rst_i;
    logic stall_i;

    wire [31:0] pc_o;
    wire [127:0] bundle_o;
    wire fetch_valid_o;

    logic [31:0] pc_detenido;

    integer i;
    integer escrituras_x5 = 0;
    integer escrituras_x6 = 0;

    top #(
        .IMEM_WORDS(128),
        .PROGRAM_FILE("program_test.mem")
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_i),
        .pc_o(pc_o),
        .bundle_o(bundle_o),
        .fetch_valid_o(fetch_valid_o)
    );

    // Reloj de 10 ns
    always #5 clk_i = ~clk_i;

    // Instruccion LOAD: memoria -> registro
    function automatic [31:0] lsu_load(
        input [11:0] offset,
        input [3:0] base,
        input [3:0] rd
    );
        lsu_load = {
            10'b0, offset, base, rd, 2'b01
        };
    endfunction

    // Contar escrituras de LOAD en los registros
    always @(posedge clk_i) begin
        if (!rst_i && dut.regfile_wr_en[1]) begin
            if (dut.regfile_wr_addr[1] == 4'd5)
                escrituras_x5 = escrituras_x5 + 1;

            if (dut.regfile_wr_addr[1] == 4'd6)
                escrituras_x6 = escrituras_x6 + 1;
        end
    end

    initial begin
        $dumpfile("stall_load.vcd");
        $dumpvars(0, clk_i, rst_i, stall_i, pc_o);

        rst_i = 1;
        stall_i = 0;

        #1;

        // Limpiar instrucciones
        for (i = 0; i < 32; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 0;

        // Preparar un dato en memoria: A1B2C3D4
        dut.data_memory_inst.memory[32] = 8'hD4;
        dut.data_memory_inst.memory[33] = 8'hC3;
        dut.data_memory_inst.memory[34] = 8'hB2;
        dut.data_memory_inst.memory[35] = 8'hA1;

        // Segundo dato: 55667788
        dut.data_memory_inst.memory[36] = 8'h88;
        dut.data_memory_inst.memory[37] = 8'h77;
        dut.data_memory_inst.memory[38] = 8'h66;
        dut.data_memory_inst.memory[39] = 8'h55;

        // Primer LOAD: memoria[32] -> x5
        dut.fetch_inst.instruction_memory_inst.memory[0] = {
            64'b0,
            lsu_load(12'd32, 4'd0, 4'd5),
            32'b0
        };

        // Segundo LOAD: memoria[36] -> x6
        // Se deja separacion de bundles NOP
        dut.fetch_inst.instruction_memory_inst.memory[7] = {
            64'b0,
            lsu_load(12'd36, 4'd0, 4'd6),
            32'b0
        };

        // Liberar reset
        @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 0;

        // ========================================
        // PRUEBA 1: DETENER LOAD EN EX
        // ========================================

        wait (dut.ex_lsu_mem_read === 1'b1 &&
              dut.rr_ex_valid_out === 1'b1);

        @(negedge clk_i);
        stall_i = 1;
        pc_detenido = pc_o;

        $display("STALL activado durante LOAD");

        repeat (3) begin
            @(posedge clk_i);
            #1;

            // PC debe permanecer detenido
            if (pc_o !== pc_detenido)
                $fatal(1, "ERROR: PC avanzo durante stall");

            // El resultado todavia no debe llegar a x5
            if (dut.regfile_inst.regs[5] !== 32'd0)
                $fatal(1, "ERROR: LOAD escribio antes de reanudar");

            if (escrituras_x5 !== 0)
                $fatal(1, "ERROR: LOAD se escribio durante stall");
        end

        $display("PASS: LOAD espero durante stall");
        $display("PASS: PC permanecio detenido");

        // ========================================
        // PRUEBA 2: REANUDAR PIPELINE
        // ========================================

        @(negedge clk_i);
        stall_i = 0;

        $display("STALL desactivado");

        // Esperar que terminen ambos LOAD
        repeat (18) @(posedge clk_i);
        #1;

        // Comprobar primera lectura
        if (dut.regfile_inst.regs[5] !== 32'hA1B2C3D4)
            $fatal(1, "ERROR: LOAD no cargo x5 correctamente");

        $display("PASS: LOAD cargo A1B2C3D4 en x5");

        // Comprobar segunda lectura
        if (dut.regfile_inst.regs[6] !== 32'h55667788)
            $fatal(1, "ERROR: segundo LOAD fallo");

        $display("PASS: Segundo LOAD cargo 55667788 en x6");

        // Verificar que ambas instrucciones escribieron una vez
        if (escrituras_x5 !== 1 ||
            escrituras_x6 !== 1)
            $fatal(1,
                "ERROR: escrituras x5=%0d x6=%0d",
                escrituras_x5, escrituras_x6);

        $display("PASS: Cada LOAD escribio una sola vez");

        $display("--------------------------------");
        $display("PRUEBA LOAD + STALL SUPERADA");
        $display("--------------------------------");

        $finish;
    end

    // Limite de tiempo
    initial begin
        #1000;
        $fatal(1, "ERROR: tiempo de espera agotado");
    end

endmodule


`timescale 1ns/1ps

module tb_stall_store;

    // Reloj, reset y stall del procesador
    logic clk_i = 0;
    logic rst_i;
    logic stall_i;

    // Salidas de observacion
    wire [31:0] pc_o;
    wire [127:0] bundle_o;
    wire fetch_valid_o;

    logic [31:0] pc_antes;
    integer i;
    integer escrituras = 0;

    // Procesador completo
    top #(
        .IMEM_WORDS(256),
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

    // Construir instruccion STORE
    function automatic [31:0] lsu_store(
        input [11:0] offset,
        input [3:0] base,
        input [3:0] rs1
    );
        lsu_store = {
            10'b0, offset, base, rs1, 2'b10
        };
    endfunction

    // Contar las escrituras que solicita el procesador
    always @(posedge clk_i) begin
        if (!rst_i &&
            dut.ex_lsu_mem_write &&
            !dut.ex_lsu_access_error) begin

            escrituras = escrituras + 1;

            $display(
                "STORE observado: direccion=%0d dato=%h stall=%b",
                dut.ex_lsu_effective_addr,
                dut.ex_lsu_mem_write_data,
                stall_i
            );
        end
    end

    initial begin

        rst_i = 1;
        stall_i = 0;

        // Esperar inicializacion de la memoria
        #1;

        // Limpiar programa
        for (i = 0; i < 64; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 0;

        // Unicamente una instruccion STORE
        dut.fetch_inst.instruction_memory_inst.memory[0] = {
            64'b0,
            lsu_store(12'd0, 4'd0, 4'd2),
            32'b0
        };

        // Reiniciar y preparar x2
        @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 0;

        dut.regfile_inst.regs[2] = 32'hA1B2C3D4;

        // Esperar a que STORE llegue a EX
        wait (dut.ex_lsu_mem_write === 1'b1);

        // Detener el pipeline antes de la escritura
        @(negedge clk_i);
        stall_i = 1;
        pc_antes = pc_o;

        $display("STALL activado");

        // Mantener el stall durante tres ciclos
        repeat (3) @(posedge clk_i);
        #1;

        // Verificar que el PC no avanzo
        if (pc_o !== pc_antes)
            $fatal(1, "ERROR: PC avanzo durante stall");

        $display("PASS: PC detenido correctamente");

        // Reanudar la ejecucion
        @(negedge clk_i);
        stall_i = 0;

        $display("STALL desactivado");

        repeat (5) @(posedge clk_i);
        #1;

        // Comprobar el dato almacenado
        if ({
            dut.data_memory_inst.memory[3],
            dut.data_memory_inst.memory[2],
            dut.data_memory_inst.memory[1],
            dut.data_memory_inst.memory[0]
        } !== 32'hA1B2C3D4)
            $fatal(1, "ERROR: dato incorrecto en memoria");

        $display("PASS: dato almacenado correctamente");

        // Comprobar que STORE no se repitio
        $display("Escrituras observadas: %0d", escrituras);

        if (escrituras !== 1)
            $fatal(1,
                "ERROR: STORE se ejecuto %0d veces",
                escrituras);

        $display("PASS: STORE se ejecuto una sola vez");
        $display("PRUEBA STALL + STORE SUPERADA");

        $finish;
    end

    // Evitar que una falla deje la simulacion esperando
    initial begin
        #1000;
        $fatal(1, "ERROR: tiempo de espera agotado");
    end

endmodule

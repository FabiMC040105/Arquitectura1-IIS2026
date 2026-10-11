`timescale 1ns/1ps

module tb_bru_stall;

    // Reloj y control del procesador
    logic clk_i = 0;
    logic rst_i;
    logic stall_i;

    // Salidas del procesador
    wire [31:0] pc_o;
    wire [127:0] bundle_o;
    wire fetch_valid_o;

    // Indicadores de eventos observados
    logic vio_salto = 0;
    logic vio_destino = 0;
    logic vio_flush = 0;

    integer i;

    // Instancia del procesador completo
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

    // Reloj de 10 nanosegundos
    always #5 clk_i = ~clk_i;

    // Construir instruccion ADDI
    function automatic [31:0] alu_addi(
        input [11:0] imm,
        input [3:0] rs1,
        input [3:0] rd
    );
        alu_addi = {
            8'b0, imm, rs1, rd, 1'b1, 3'b001
        };
    endfunction

    // Construir instruccion JMP del slot BRU
    // Offset de 20 bits y opcode de 3 bits
    function automatic [31:0] bru_jmp(
        input [19:0] offset
    );
        bru_jmp = {9'b0, offset, 3'b001};
    endfunction

    // Observar el salto y las señales de flush
    always @(posedge clk_i) begin
        if (rst_i) begin
            vio_salto <= 0;
            vio_destino <= 0;
            vio_flush <= 0;
        end
        else if (dut.ex_branch_taken === 1'b1) begin
            vio_salto <= 1;

            // Comprobar el destino del salto
            if (dut.ex_bru_branch_target === 32'd128)
                vio_destino <= 1;

            // Comprobar el flush implementado
            // por el controlador del pipeline
            if (dut.flush_if_id === 1'b1 &&
                dut.flush_id_rr === 1'b1 &&
                dut.flush_rr_ex === 1'b1)
                vio_flush <= 1;
        end
    end

    initial begin

        rst_i = 1;
        stall_i = 0;

        // Esperar la inicializacion de las memorias
        #1;

        // Limpiar el programa de prueba
        for (i = 0; i < 32; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 0;

        // BUNDLE 0: x2 = 5
        dut.fetch_inst.instruction_memory_inst.memory[0] = {
            96'b0,
            alu_addi(12'd5, 4'd0, 4'd2)
        };

        // BUNDLE 1: NOP

        // BUNDLE 2: JMP +96
        // PC actual = 32
        // Destino = 32 + 96 = 128
        dut.fetch_inst.instruction_memory_inst.memory[2] = {
            32'b0,
            bru_jmp(20'd96),
            64'b0
        };

        // BUNDLES 3, 4 Y 5: NOP
        // Espacios reservados en la calendarizacion

        // BUNDLE 6: instruccion que debe saltarse
        dut.fetch_inst.instruction_memory_inst.memory[6] = {
            96'b0,
            alu_addi(12'd99, 4'd0, 4'd9)
        };

        // BUNDLE 7: otra instruccion que debe saltarse
        dut.fetch_inst.instruction_memory_inst.memory[7] = {
            96'b0,
            alu_addi(12'd88, 4'd0, 4'd10)
        };

        // BUNDLE 8: destino del salto
        // x4 = 21
        dut.fetch_inst.instruction_memory_inst.memory[8] = {
            96'b0,
            alu_addi(12'd21, 4'd0, 4'd4)
        };

        
        // Liberar reset
        @(negedge clk_i);
        rst_i = 0;

        // Esperar a que JMP llegue a la etapa EX
        wait (dut.ex_branch_taken === 1'b1);

        // Detener el pipeline antes de ejecutar el salto
        @(negedge clk_i);
        stall_i = 1;

        $display("STALL activado durante JMP");

        // Guardar el PC antes de detenernos
        begin
            logic [31:0] pc_detenido;
            pc_detenido = pc_o;

            // Mantener el stall por tres ciclos
            repeat (3) begin
                @(posedge clk_i);
                #1;

                if (pc_o !== pc_detenido)
                    $fatal(1, "ERROR: PC avanzo durante stall");

                if (dut.flush_if_id !== 1'b0)
                    $fatal(1, "ERROR: flush durante stall");
            end
        end

        $display("PASS: JMP espero durante stall");

        // Reanudar el pipeline
        @(negedge clk_i);
        stall_i = 0;

        @(posedge clk_i);
        #1;

        if (pc_o !== 32'd128)
            $fatal(1, "ERROR: JMP no salto al PC 128");

        $display("PASS: JMP salto al destino correcto");

        // Dejar que el programa termine
        repeat (18) @(posedge clk_i);
        #1;


        // PRUEBA 1: Comprobar JMP
        if (vio_salto !== 1'b1)
            $fatal(1, "ERROR: BRU no ejecuto JMP");

        $display("PASS: BRU ejecuto JMP");

        // PRUEBA 2: Destino correcto
        if (vio_destino !== 1'b1)
            $fatal(1, "ERROR: destino de salto incorrecto");

        $display("PASS: Salto dirigido al PC 128");

        // PRUEBA 3: Flush de instrucciones
        if (vio_flush !== 1'b1)
            $fatal(1, "ERROR: flush no se activo");

        $display("PASS: Flush generado correctamente");

        // PRUEBA 4: Instruccion previa
        if (dut.regfile_inst.regs[2] !== 32'd5)
            $fatal(1, "ERROR: x2 no contiene 5");

        $display("PASS: x2 = 5");

        // PRUEBA 5: Instrucciones omitidas
        if (dut.regfile_inst.regs[9] !== 32'b0 ||
            dut.regfile_inst.regs[10] !== 32'b0)
            $fatal(1, "ERROR: se ejecuto codigo omitido");

        $display("PASS: Instrucciones omitidas no ejecutadas");

        // PRUEBA 6: Instruccion destino
        if (dut.regfile_inst.regs[4] !== 32'd21)
            $fatal(1, "ERROR: destino no ejecuto ADDI");

        $display("PASS: Destino ejecuto x4 = 21");

        $display("--------------------------------");
        $display("PRUEBA BRU EN PIPELINE SUPERADA");
        $display("--------------------------------");

        $finish;
    end

endmodule

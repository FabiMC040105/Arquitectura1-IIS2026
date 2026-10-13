
`timescale 1ns/1ps

module tb_pc_write_stall;

    logic clk_i = 0;
    logic rst_i;
    logic stall_i;

    wire [31:0] pc_o;
    wire [127:0] bundle_o;
    wire fetch_valid_o;

    logic [31:0] pc_detenido;
    integer escrituras_pc = 0;
    logic vio_flush_pc = 0;
    integer i;

    // Procesador VLIW completo
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

    // Contar los cambios de PC realmente permitidos
    always @(posedge clk_i) begin
        if (rst_i) begin
            escrituras_pc = 0;
            vio_flush_pc = 0;
        end
        else if (!stall_i && dut.wb_pc_write === 1'b1) begin

            escrituras_pc = escrituras_pc + 1;

            $display(
                "Escritura a x1: nuevo PC=%0d",
                dut.wb_pc_write_data
            );

            if (dut.flush_if_id &&
                dut.flush_id_rr &&
                dut.flush_rr_ex &&
                dut.flush_ex_wb)
                vio_flush_pc = 1;
        end
    end

    initial begin

        // Archivo para observar ondas en GTKWave
        $dumpfile("pc_write_stall.vcd");
        $dumpvars(0, clk_i, rst_i, stall_i, pc_o);
        $dumpvars(0,
            dut.wb_pc_write,
            dut.wb_pc_write_data,
            dut.flush_if_id,
            dut.flush_ex_wb
        );

        rst_i = 1;
        stall_i = 0;

        #1;

        // Limpiar la memoria de instrucciones
        for (i = 0; i < 32; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 0;

        // BUNDLE 0: x2 = 5
        dut.fetch_inst.instruction_memory_inst.memory[0] = {
            96'b0,
            alu_addi(12'd5, 4'd0, 4'd2)
        };

        // BUNDLE 1: NOP

        // BUNDLE 2: escribir 128 en x1 (PC)
        dut.fetch_inst.instruction_memory_inst.memory[2] = {
            96'b0,
            alu_addi(12'd128, 4'd0, 4'd1)
        };

        // BUNDLES 3, 4 Y 5: NOP

        // BUNDLE 6: NO debe ejecutarse
        dut.fetch_inst.instruction_memory_inst.memory[6] = {
            96'b0,
            alu_addi(12'd99, 4'd0, 4'd9)
        };

        // BUNDLE 7: NO debe ejecutarse
        dut.fetch_inst.instruction_memory_inst.memory[7] = {
            96'b0,
            alu_addi(12'd88, 4'd0, 4'd10)
        };

        // BUNDLE 8: destino PC = 128
        dut.fetch_inst.instruction_memory_inst.memory[8] = {
            96'b0,
            alu_addi(12'd21, 4'd0, 4'd4)
        };

        // =========================================
        // ETAPA 1: LIBERAR RESET
        // =========================================

        @(negedge clk_i);
        rst_i = 0;

        // Esperar la escritura a x1 en WB
        wait (dut.wb_pc_write === 1'b1 &&
              dut.wb_pc_write_data === 32'd128);

        // =========================================
        // ETAPA 2: ACTIVAR STALL
        // =========================================

        @(negedge clk_i);
        stall_i = 1;

        pc_detenido = pc_o;

        $display("STALL activado durante escritura a x1");

        repeat (3) begin
            @(posedge clk_i);
            #1;

            // El PC debe quedarse congelado
            if (pc_o !== pc_detenido)
                $fatal(1, "ERROR: PC avanzo durante stall");

            // No debe producirse flush
            if (dut.flush_if_id !== 1'b0 ||
                dut.flush_id_rr !== 1'b0 ||
                dut.flush_rr_ex !== 1'b0 ||
                dut.flush_ex_wb !== 1'b0)
                $fatal(1, "ERROR: flush durante stall");

            // La escritura debe continuar pendiente
            if (dut.wb_pc_write !== 1'b1)
                $fatal(1, "ERROR: se perdio escritura a x1");

            // No debe haberse ejecutado
            if (escrituras_pc != 0)
                $fatal(1, "ERROR: escritura durante stall");
        end

        $display("PASS: escritura a x1 espero durante stall");

        // =========================================
        // ETAPA 3: REANUDAR
        // =========================================

        @(negedge clk_i);
        stall_i = 0;

        @(posedge clk_i);
        #1;

        if (pc_o !== 32'd128)
            $fatal(1, "ERROR: PC no cambio a 128");

        if (escrituras_pc != 1)
            $fatal(1, "ERROR: escritura a PC ocurrio %0d veces",
                   escrituras_pc);

        $display("PASS: PC actualizado a 128 una sola vez");

        // Esperar ejecucion del destino
        repeat (18) @(posedge clk_i);
        #1;

        // =========================================
        // ETAPA 4: COMPROBACIONES FINALES
        // =========================================

        // El flush debe descartar instrucciones jovenes
        if (vio_flush_pc !== 1'b1)
            $fatal(1, "ERROR: no se genero flush");

        $display("PASS: Flush generado correctamente");

        // La instruccion anterior debe completarse
        if (dut.regfile_inst.regs[2] !== 32'd5)
            $fatal(1, "ERROR: x2 no contiene 5");

        $display("PASS: x2 = 5");

        // Estas instrucciones no deben ejecutarse
        if (dut.regfile_inst.regs[9] !== 32'd0 ||
            dut.regfile_inst.regs[10] !== 32'd0)
            $fatal(1, "ERROR: se ejecuto codigo omitido");

        $display("PASS: Instrucciones omitidas no ejecutadas");

        // Comprobar que llegamos al destino
        if (dut.regfile_inst.regs[4] !== 32'd21)
            $fatal(1, "ERROR: destino no ejecuto ADDI");

        $display("PASS: Destino ejecuto x4 = 21");

        // Verificar que no se repitio el cambio de PC
        if (escrituras_pc != 1)
            $fatal(1, "ERROR: multiples escrituras a PC");

        $display("PASS: Una sola escritura a x1");

        $display("--------------------------------");
        $display("PRUEBA PC WRITE + STALL SUPERADA");
        $display("--------------------------------");

        $finish;
    end

    // Evitar simulaciones infinitas
    initial begin
        #1000;
        $fatal(1, "ERROR: tiempo de espera agotado");
    end

endmodule

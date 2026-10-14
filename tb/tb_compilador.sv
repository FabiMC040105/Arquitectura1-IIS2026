`timescale 1ns/1ps

module tb_compilador;

    logic clk_i;
    logic rst_i;
    logic stall_i;

    logic [31:0]  pc_o;
    logic [127:0] bundle_o;
    logic         fetch_valid_o;

    integer ciclo;
    integer i;
    integer puerto;
    integer addr;

    integer terminado;
    integer tiene_final_pc;

    logic [31:0] expected_final_pc;
    logic [31:0] final_pc;
    logic [31:0] palabra_mem;

    localparam integer MAX_CYCLES = 50000;

    top #(
        .PROGRAM_FILE("program.mem"),
        .DATA_FILE("")
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_i),

        .pc_o(pc_o),
        .bundle_o(bundle_o),
        .fetch_valid_o(fetch_valid_o)
    );

    always #5 clk_i = ~clk_i;

    initial begin

        $dumpfile("traza_compilador.vcd");

        // Solo señales importantes para no generar un VCD gigantesco.
        $dumpvars(
            0,
            clk_i,
            rst_i,
            pc_o,
            bundle_o,
            fetch_valid_o,
            dut.ex_pc,
            dut.ex_branch_taken,
            dut.ex_bru_branch_target
        );

        clk_i   = 1'b0;
        rst_i   = 1'b1;
        stall_i = 1'b0;

        terminado = 0;
        final_pc  = 32'b0;

        tiene_final_pc =
            $value$plusargs("FINAL_PC=%h", expected_final_pc);

        $display("==================================================");
        $display(" PROGRAMA GENERADO POR COMPILADORES CE1108");
        $display(" EJECUTADO EN PROCESADOR VLIW CE4301");
        $display("==================================================");

        if (tiene_final_pc) begin
            $display(
                "PC final esperado: 0x%08h",
                expected_final_pc
            );
        end

        // Reset.
        repeat (3) @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        // ==================================================
        // EJECUCION
        // ==================================================

        for (
            ciclo = 0;
            ciclo < MAX_CYCLES && !terminado;
            ciclo = ciclo + 1
        ) begin

            @(posedge clk_i);
            #1;

            if (fetch_valid_o) begin
                $display(
                    "TRACE ciclo=%0d PC=%08h BUNDLE=%032h",
                    ciclo,
                    pc_o,
                    bundle_o
                );
            end

            // Escrituras en registros.
            for (
                puerto = 0;
                puerto < 4;
                puerto = puerto + 1
            ) begin

                if (dut.regfile_wr_en[puerto]) begin
                    $display(
                        "  WB x%0d <= %08h (%0d)",
                        dut.regfile_wr_addr[puerto],
                        dut.regfile_wr_data[puerto],
                        $signed(dut.regfile_wr_data[puerto])
                    );
                end
            end

            // Stores.
            if (dut.ex_lsu_mem_write) begin
                $display(
                    "  STORE MEM[%08h] <= %08h (%0d)",
                    dut.ex_lsu_effective_addr,
                    dut.ex_lsu_mem_write_data,
                    $signed(dut.ex_lsu_mem_write_data)
                );
            end

            // Saltos tomados.
            if (dut.ex_branch_taken) begin
                $display(
                    "  BRANCH PC=%08h -> %08h",
                    dut.ex_pc,
                    dut.ex_bru_branch_target
                );

                // El compilador termina mediante JMP 0
                // sobre la etiqueta fin_programa.
                if (
                    dut.ex_bru_branch_target ==
                    dut.ex_pc
                ) begin

                    terminado = 1;
                    final_pc  = dut.ex_pc;

                    $display("");
                    $display(
                        "SELF_LOOP detectado en PC=0x%08h",
                        final_pc
                    );
                end
            end
        end

        // Vaciar pipeline.
        repeat (4) @(posedge clk_i);
        #1;

        $display("");
        $display("==================================================");
        $display(" RESULTADO DE EJECUCION");
        $display("==================================================");

        if (!terminado) begin

            $display(
                "FAIL: no se alcanzo fin_programa en %0d ciclos",
                MAX_CYCLES
            );

        end
        else if (tiene_final_pc) begin

            if (final_pc == expected_final_pc) begin

                $display(
                    "PASS: fin_programa alcanzado en 0x%08h",
                    final_pc
                );

            end
            else begin

                $display(
                    "FAIL: self-loop inesperado"
                );

                $display(
                    "Esperado: 0x%08h",
                    expected_final_pc
                );

                $display(
                    "Obtenido: 0x%08h",
                    final_pc
                );
            end
        end

        // ==================================================
        // REGISTROS FINALES
        // ==================================================

        $display("");
        $display("==================================================");
        $display(" REGISTROS FINALES");
        $display("==================================================");

        for (i = 0; i < 16; i = i + 1) begin

            $display(
                "x%0d = 0x%08h (%0d)",
                i,
                dut.regfile_inst.regs[i],
                $signed(dut.regfile_inst.regs[i])
            );

        end

        // ==================================================
        // MEMORIA FINAL DEL STACK
        // ==================================================

        $display("");
        $display("==================================================");
        $display(" MEMORIA NO CERO 0xFC00 - 0xFFFF");
        $display("==================================================");

        for (
            addr = 16'hFC00;
            addr < 65536;
            addr = addr + 4
        ) begin

            palabra_mem = {
                dut.data_memory_inst.memory[addr + 3],
                dut.data_memory_inst.memory[addr + 2],
                dut.data_memory_inst.memory[addr + 1],
                dut.data_memory_inst.memory[addr]
            };

            if (palabra_mem !== 32'b0) begin

                $display(
                    "MEM[%08h] = %08h (%0d)",
                    addr,
                    palabra_mem,
                    $signed(palabra_mem)
                );

            end
        end

        $display("");
        $display("==================================================");
        $display(" FIN DE SIMULACION");
        $display("==================================================");

        $finish;
    end

endmodule

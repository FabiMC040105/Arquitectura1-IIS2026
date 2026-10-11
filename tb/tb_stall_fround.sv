
`timescale 1ns/1ps

module tb_stall_fround;

    logic clk_i = 0;
    logic rst_i;
    logic stall_i;

    wire [31:0] pc_o;
    wire [127:0] bundle_o;
    wire fetch_valid_o;

    logic [31:0] pc_detenido;

    integer i;
    integer fround_veces = 0;
    integer resultados_validos = 0;
    integer escrituras_l = 0;
    integer escrituras_r = 0;

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

    // Instruccion AUTH
    function automatic [31:0] feist_auth(
        input [3:0] rs2,
        input [3:0] rs1
    );
        feist_auth = {21'b0, rs2, rs1, 3'b001};
    endfunction

    // Instruccion KSTORE
    function automatic [31:0] feist_kstore(
        input [1:0] key,
        input [1:0] round,
        input [3:0] rs1
    );
        feist_kstore = {21'b0, key, round, rs1, 3'b011};
    endfunction

    // Instruccion FROUND
    function automatic [31:0] feist_round(
        input [3:0] rdL,
        input [3:0] rdR,
        input [3:0] rsL,
        input [3:0] rsR,
        input [1:0] key,
        input [1:0] round,
        input mode
    );
        feist_round = {
            8'b0, rdL, rdR, rsL, rsR,
            key, round, mode, 3'b100
        };
    endfunction

    // Contar las ejecuciones y escrituras
    always @(posedge clk_i) begin
        if (!rst_i) begin

            // Solicitudes FROUND que llegan a EX
            if (dut.ex_feist_fround_req === 1'b1)
                fround_veces = fround_veces + 1;

            // Resultados validos de la unidad criptografica
            if (dut.ex_feist_result_valid === 1'b1)
                resultados_validos = resultados_validos + 1;

            // Escritura de la mitad izquierda en x7
            if (dut.regfile_wr_en[2] &&
                dut.regfile_wr_addr[2] == 4'd7)
                escrituras_l = escrituras_l + 1;

            // Escritura de la mitad derecha en x8
            if (dut.regfile_wr_en[3] &&
                dut.regfile_wr_addr[3] == 4'd8)
                escrituras_r = escrituras_r + 1;

        end
    end

    initial begin

        // Ondas para GTKWave
        $dumpfile("stall_fround.vcd");

        $dumpvars(0, clk_i, rst_i, stall_i, pc_o);

        $dumpvars(0,
            dut.ex_feist_fround_req,
            dut.ex_feist_result_valid,
            dut.ex_feist_l_out,
            dut.ex_feist_r_out
        );

        rst_i = 1;
        stall_i = 0;

        #1;

        // Limpiar memoria de instrucciones
        for (i = 0; i < 32; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 0;

        // ==========================================
        // PROGRAMA DE PRUEBA
        // ==========================================

        // BUNDLE 0: autenticarse
        dut.fetch_inst.instruction_memory_inst.memory[0] = {
            feist_auth(4'd3, 4'd2), 96'b0
        };

        // BUNDLES 1-5: NOP

        // BUNDLE 6: guardar la subllave 0
        dut.fetch_inst.instruction_memory_inst.memory[6] = {
            feist_kstore(0, 0, 4'd11), 96'b0
        };

        // BUNDLES 7-11: NOP

        // BUNDLE 12: ejecutar una ronda Feistel
        // Entradas: x5 = HOLA, x6 = 1234
        // Salidas: x7 = L', x8 = R'
        dut.fetch_inst.instruction_memory_inst.memory[12] = {
            feist_round(7, 8, 5, 6, 0, 0, 0),
            96'b0
        };

        // ==========================================
        // PREPARAR REGISTROS
        // ==========================================

        @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 0;

        // Credenciales AUTH
        dut.regfile_inst.regs[2] = 32'hC0DE1234;
        dut.regfile_inst.regs[3] = 32'hABCD5678;

        // Primera subllave
        dut.regfile_inst.regs[11] = 32'h12345678;

        // Mensaje HOLA1234
        dut.regfile_inst.regs[5] = 32'h484F4C41;
        dut.regfile_inst.regs[6] = 32'h31323334;

        // ==========================================
        // ETAPA 1: ESPERAR FROUND EN EX
        // ==========================================

        wait (dut.ex_feist_fround_en === 1'b1 &&
              dut.rr_ex_valid_out === 1'b1);

        // Comprobar preparacion de la boveda
        if (dut.key_vault_inst.authorized !== 1'b1)
            $fatal(1, "ERROR: boveda no autenticada");

        if (dut.key_vault_inst.subkeys[0][0] !== 32'h12345678)
            $fatal(1, "ERROR: subllave incorrecta");

        $display("PASS: Boveda lista para FROUND");

        // ==========================================
        // ETAPA 2: ACTIVAR STALL
        // ==========================================

        @(negedge clk_i);
        stall_i = 1;

        pc_detenido = pc_o;

        $display("STALL activado durante FROUND");

        repeat (3) begin
            @(posedge clk_i);
            #1;

            // PC permanece detenido
            if (pc_o !== pc_detenido)
                $fatal(1, "ERROR: PC avanzo durante stall");

            // FROUND no debe solicitar ejecucion
            if (dut.ex_feist_fround_req !== 1'b0)
                $fatal(1, "ERROR: FROUND activo durante stall");

            // No debe producir resultado valido
            if (dut.ex_feist_result_valid !== 1'b0)
                $fatal(1, "ERROR: resultado valido durante stall");

            // Los registros destino deben conservar su valor
            if (dut.regfile_inst.regs[7] !== 32'b0 ||
                dut.regfile_inst.regs[8] !== 32'b0)
                $fatal(1, "ERROR: FROUND escribio durante stall");

            // No debe haberse ejecutado ninguna ronda
            if (fround_veces != 0 ||
                resultados_validos != 0)
                $fatal(1, "ERROR: FROUND se ejecuto durante stall");
        end

        $display("PASS: FROUND espero durante stall");
        $display("PASS: PC permanecio detenido");

        // ==========================================
        // ETAPA 3: REANUDAR PIPELINE
        // ==========================================

        @(negedge clk_i);
        stall_i = 0;

        $display("STALL desactivado");

        // Permitir que FROUND llegue a WB
        repeat (6) @(posedge clk_i);
        #1;

        // ==========================================
        // ETAPA 4: COMPROBAR RESULTADO
        // ==========================================

        // Una ronda:
        // L' = 31323334
        // R' = 36537699

        if (dut.regfile_inst.regs[7] !== 32'h31323334)
            $fatal(1, "ERROR: mitad L incorrecta");

        if (dut.regfile_inst.regs[8] !== 32'h36537699)
            $fatal(1, "ERROR: mitad R incorrecta");

        $display("PASS: FROUND produjo resultado correcto");
        $display("L = %08h", dut.regfile_inst.regs[7]);
        $display("R = %08h", dut.regfile_inst.regs[8]);

        // FROUND debe ejecutarse una sola vez
        if (fround_veces !== 1 ||
            resultados_validos !== 1)
            $fatal(1,
                "ERROR: FROUND=%0d resultados=%0d",
                fround_veces, resultados_validos);

        $display("PASS: FROUND ejecutado una sola vez");

        // Debe escribir ambos registros una sola vez
        if (escrituras_l !== 1 ||
            escrituras_r !== 1)
            $fatal(1, "ERROR: escrituras repetidas en registros");

        $display("PASS: Registros x7 y x8 escritos una vez");

        $display("--------------------------------");
        $display("PRUEBA FROUND + STALL SUPERADA");
        $display("--------------------------------");

        $finish;
    end

    // Evitar simulaciones infinitas
    initial begin
        #1000;
        $fatal(1, "ERROR: tiempo de espera agotado");
    end

endmodule

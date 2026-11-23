`timescale 1ns/1ps

// Prueba de integracion: ejecuta el .bin de Compiladores en el CPU real.
// No modifica ningun modulo del procesador ni genera un VCD gigante.
module tb_matriz;
    logic clk = 0;
    logic clk_mem = 0;
    logic rst = 1;
    logic [31:0] pc;
    integer ciclos;
    integer drenaje;
    integer limite;
    integer detenido;
    integer direccion_fin;
    integer i, j, indice;
    integer fallos_a, fallos_b, fallos_resultado, fallos_esperado;
    integer real_a, real_b, real_c, real_esp, valor_esp, valor_b;

    // 64 KiB de ROM: 4096 bundles de 128 bits.
    // La entrada de RAM esta vacia: el propio .bin inicializa las globales.
    top #(
        .IMEM_WORDS(16384),
        .PROGRAM_FILE("pruebas-compilador/matriz.mem"),
        .DATA_FILE("")
    ) dut (
        .clk_i(clk),
        .clk_mem_i(clk_mem),
        .rst_i(rst),
        .stall_i(1'b0),
        .pc_o(pc)
    );

    always #5 clk = ~clk;
    always #20 clk_mem = ~clk_mem;


    // Lectura del valor visible en la jerarquia de memoria:
    // primero L1, despues L2 y finalmente RAM.
    function automatic [31:0] leer32(input integer direccion);
        integer conjunto1, conjunto2, palabra, via;
        reg encontrado;
        reg [31:0] valor;
        begin
            conjunto1 = (direccion >> 5) & 63;
            conjunto2 = (direccion >> 5) & 127;
            palabra = (direccion >> 2) & 7;
            encontrado = 0;
            valor = 0;

            for (via = 0; via < 2; via = via + 1) begin
                if (!encontrado &&
                    dut.l1_data_system_inst.cache.valid_array[via][conjunto1] === 1'b1 &&
                    dut.l1_data_system_inst.cache.tag_array[via][conjunto1] === (direccion >> 11)) begin
                    valor = dut.l1_data_system_inst.cache.data_array[via][conjunto1][palabra*32 +: 32];
                    encontrado = 1;
                end
            end

            if (!encontrado) begin
                for (via = 0; via < 4; via = via + 1) begin
                    if (!encontrado &&
                        dut.l2_data_system_inst.controller.cache_inst.valid_array[conjunto2][via] === 1'b1 &&
                        dut.l2_data_system_inst.controller.cache_inst.tag_array[conjunto2][via] === (direccion >> 12)) begin
                        valor = dut.l2_data_system_inst.controller.cache_inst.data_array[conjunto2][via][palabra*32 +: 32];
                        encontrado = 1;
                    end
                end
            end

            if (!encontrado)
                valor = {
                    dut.mem_subsystem_inst.u_ctrl.memory[direccion+3],
                    dut.mem_subsystem_inst.u_ctrl.memory[direccion+2],
                    dut.mem_subsystem_inst.u_ctrl.memory[direccion+1],
                    dut.mem_subsystem_inst.u_ctrl.memory[direccion]
                };

            leer32 = valor;
        end
    endfunction

    initial begin
        limite = 800000;
        if ($value$plusargs("MAX_CICLOS=%d", limite)) begin end
        ciclos = 0;
        detenido = 0;
        direccion_fin = -1;

        // Liberar reset de manera sincronizada, fuera del flanco positivo.
        repeat (4) @(negedge clk);
        rst = 0;

        // El compilador termina con JMP 0: salto a su propio PC.
        // Es mas fiable que contar NOP consecutivos.
        while (ciclos < limite && !detenido) begin
            @(negedge clk);
            ciclos = ciclos + 1;
            if (ciclos % 50000 == 0) begin
                $display("PROGRESO: ciclos=%0d PC=%08h", ciclos, pc);
                $fflush();
            end
            if ((dut.ex_pc == 32'h0000fad0 ||
                 dut.ex_pc == 32'h0000fae0) &&
                dut.ex_branch_taken === 1'b1 &&
                !dut.global_stall_o &&
                dut.ex_bru_branch_target === dut.ex_pc) begin
                detenido = 1;
                direccion_fin = dut.ex_pc;
            end
        end

        if (!detenido) begin
            $display("FAIL: el programa no llego al salto final tras %0d ciclos; PC=%08h", ciclos, pc);
            $fatal(1, "Revisar ciclos, saltos o bucles infinitos");
        end

        // Dejar que terminen las operaciones que ya estaban en el pipeline.
        // Esperar las escrituras pendientes antes de verificar.
        drenaje = 0;
        while ((!dut.l1_data_system_inst.buffer_empty ||
                dut.l2_data_system_inst.controller.state != 0 ||
                dut.l2_data_system_inst.mem_state != 0) &&
                drenaje < 10000) begin
            @(negedge clk);
            drenaje = drenaje + 1;
        end

        if (drenaje >= 10000)
            $fatal(1, "Escrituras pendientes sin completar");

        repeat (8) @(negedge clk);
        $display("FIN: ciclos=%0d, salto final PC=0x%08h", ciclos, direccion_fin);

        fallos_a = 0;
        fallos_b = 0;
        fallos_resultado = 0;
        fallos_esperado = 0;

        for (i = 0; i < 10; i = i + 1) begin
            for (j = 0; j < 10; j = j + 1) begin
                indice = i*10+j;
                real_a = leer32(32'h0000 + indice*4);
                real_b = leer32(32'h0190 + indice*4);
                real_c = leer32(32'h0320 + indice*4);
                real_esp = leer32(32'h04B0 + indice*4);
                valor_b = (j == i) ? 1 : ((j == (i+1)%10) ? 2 : 0);
                valor_esp = (j == 0) ? (30*i + 21) : (30*i + 3*j + 1);

                if (real_a !== indice + 1) begin
                    fallos_a = fallos_a + 1;
                    if (fallos_a <= 5)
                        $display("ERROR a[%0d][%0d]: %0d, esperado %0d", i,j,real_a,indice+1);
                end
                if (real_b !== valor_b) begin
                    fallos_b = fallos_b + 1;
                    if (fallos_b <= 5)
                        $display("ERROR b[%0d][%0d]: %0d, esperado %0d", i,j,real_b,valor_b);
                end
                if (real_esp !== valor_esp) begin
                    fallos_esperado = fallos_esperado + 1;
                    if (fallos_esperado <= 5)
                        $display("ERROR esperado[%0d][%0d]: %0d, esperado %0d", i,j,real_esp,valor_esp);
                end
                if (real_c !== valor_esp) begin
                    fallos_resultado = fallos_resultado + 1;
                    if (fallos_resultado <= 10)
                        $display("ERROR resultado[%0d][%0d]: %0d, esperado %0d", i,j,real_c,valor_esp);
                end
            end
        end

        $display("a: %0d errores; b: %0d errores", fallos_a, fallos_b);
        $display("esperado: %0d errores; resultado: %0d errores", fallos_esperado, fallos_resultado);
        $display("RAM[0x0320] resultado[0][0] = %0d (esperado 21)", leer32(32'h0320));
        $display("RAM[0x0640] errores = %0d (esperado 0)", leer32(32'h0640));
        $display("RAM[0x0644] prueba_correcta = %0d (esperado 1)", leer32(32'h0644));

    
        // MOSTRAR LOS 100 RESULTADOS CON SU DIRECCION REAL EN RAM

        $display("");
        $display("==============================================================");
        $display("       MATRIZ 10x10 ALMACENADA EN LA RAM DEL PROCESADOR");
        $display("==============================================================");
        $display("Posicion         Direccion RAM    Valor RAM    Esperado");
        $display("--------------------------------------------------------------");

        for (i = 0; i < 10; i = i + 1) begin
            for (j = 0; j < 10; j = j + 1) begin

                indice = i * 10 + j;

                valor_esp = (j == 0)
                    ? (30 * i + 21)
                    : (30 * i + 3 * j + 1);

                $display(
                    "resultado[%0d][%0d]   0x%04h           %0d          %0d",
                    i,
                    j,
                    32'h0320 + indice * 4,
                    leer32(32'h0320 + indice * 4),
                    valor_esp
                );

            end
        end

        $display("--------------------------------------------------------------");
        $display("RAM[0x0640] errores         = %0d", leer32(32'h0640));
        $display("RAM[0x0644] prueba_correcta = %0d", leer32(32'h0644));
        $display("==============================================================");

        if (fallos_a != 0 || fallos_b != 0 || fallos_esperado != 0 ||
            fallos_resultado != 0 || leer32(32'h0640) !== 32'd0 ||
            leer32(32'h0644) !== 32'd1)
            $fatal(1, "FAIL: diferencias en memoria; ver errores anteriores");

        $display("PASS: matrices 10x10 correctas en la jerarquia L1/L2/RAM");
        $finish;
    end
endmodule

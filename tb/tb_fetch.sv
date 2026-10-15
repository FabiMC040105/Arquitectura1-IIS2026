`timescale 1ns/1ps

module tb_fetch;

    // Memoria pequena para que el limite superior sea facil de alcanzar.
    // 64 palabras * 4 bytes = 256 bytes = 16 bundles.
    localparam integer IMEM_WORDS = 800;
    localparam integer MEM_BYTES  = IMEM_WORDS * 4;

    logic [31:0]  pc_i;
    logic [127:0] bundle_o;
    logic         valid_o;
    logic         access_error_o;

    integer errores = 0;

    fetch #(
        .IMEM_WORDS(IMEM_WORDS),
        .PROGRAM_FILE("program_test.mem")
    ) dut (
        .pc_i(pc_i),
        .bundle_o(bundle_o),
        .valid_o(valid_o),
        .access_error_o(access_error_o)
    );

    // Comprueba un acceso valido y el bundle esperado.
    task automatic revisar_bundle(
        input string          nombre,
        input logic [31:0]    pc,
        input logic [127:0]   bundle_esperado
    );
        begin
            pc_i = pc;
            #1;

            if (access_error_o !== 1'b0 || valid_o !== 1'b1) begin
                errores = errores + 1;
                $display("FALLO %s: PC=%h valid=%b access_error=%b (se esperaba acceso valido)",
                         nombre, pc, valid_o, access_error_o);
            end
            else if (bundle_o !== bundle_esperado) begin
                errores = errores + 1;
                $display("FALLO %s: PC=%h bundle=%h (se esperaba %h)",
                         nombre, pc, bundle_o, bundle_esperado);
            end
            else begin
                $display("PASS    %s: PC=%h bundle=%h", nombre, pc, bundle_o);
            end
        end
    endtask

    // Comprueba que un acceso sea rechazado.
    task automatic revisar_error(
        input string       nombre,
        input logic [31:0] pc
    );
        begin
            pc_i = pc;
            #1;

            if (access_error_o !== 1'b1 || valid_o !== 1'b0) begin
                errores = errores + 1;
                $display("FALLO %s: PC=%h valid=%b access_error=%b (se esperaba acceso invalido)",
                         nombre, pc, valid_o, access_error_o);
            end
            else begin
                $display("PASS   %s: PC=%h rechazado correctamente", nombre, pc);
            end
        end
    endtask

    initial begin
        pc_i = 32'b0;
        #1;

        $display("========================================");
        $display("Inicio de pruebas de FETCH");
        $display("========================================");

        // Los cuatro bundles cargados desde program_test.mem.
        revisar_bundle("bundle 0", 32'h00000000,
                       128'h000000000000000000000000000C0029);
        revisar_bundle("bundle 1 (NOP)", 32'h00000010,
                       128'h00000000000000000000000000000000);
        revisar_bundle("bundle 5", 32'h00000050,
                       128'h0000000000000000000000000000822B);
        revisar_bundle("bundle 90", 32'h00005A0,
                       128'h00000123000000000000000000000000);

        // Resto de la memoria inicializada en NOP.
        revisar_bundle("bundle 4 (sin cargar)", 32'h00000040, 128'b0);

        // Ultimo bundle valido de la memoria.
        revisar_bundle("ultimo bundle", MEM_BYTES - 16, 128'b0);

        // PC desalineado: un bundle ocupa 16 bytes.
        revisar_error("PC desalineado +4",  32'h00000004);
        revisar_error("PC desalineado +8",  32'h00000008);
        revisar_error("PC desalineado +1",  32'h00000021);

        // PC fuera del rango de la memoria.
        revisar_error("PC fuera de rango",  MEM_BYTES);
        revisar_error("PC muy fuera",       32'hFFFF0000);

        $display("========================================");
        if (errores == 0) begin
            $display("Pruebas de FETCH finalizadas: TODAS PASARON");
        end
        else begin
            $display("Pruebas de FETCH finalizadas: %0d FALLARON", errores);
        end
        $display("========================================");

        if (errores != 0) begin
            $fatal(1, "Hubo fallos en las pruebas de FETCH");
        end

        $finish;
    end

endmodule
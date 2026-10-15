
`timescale 1ns/1ps

module tb_crypto_integracion;

    // Reloj y reinicio
    logic clk = 0;
    logic reset;

    // Señales de control de la bóveda
    logic auth_en, logout_en, kstore_en, fround_en;

    // Datos para autenticación
    logic [31:0] auth_rs1, auth_rs2;

    // Selección de llave y subllave
    logic [1:0] key_sel, round_sel;
    logic [31:0] key_data_in;

    // Señales que devuelve la bóveda
    wire authorized, vault_access_error;
    wire [31:0] subkey_bus;
    wire subkey_valid;

    // Datos utilizados por Feistel
    logic mode_decrypt;
    logic [31:0] l_in, r_in;

    // Resultados del cifrado
    wire [31:0] l_out, r_out;
    wire result_valid, crypto_access_error;

    // Cuatro subllaves utilizadas en las pruebas
    logic [31:0] keys [0:3];

    // Variables auxiliares para las cuatro rondas
    logic [31:0] current_l, current_r;
    integer i;

    // Instancia de nuestra bóveda
    key_vault vault (
        .clk(clk),
        .reset(reset),
        .auth_en(auth_en),
        .logout_en(logout_en),
        .kstore_en(kstore_en),
        .fround_en(fround_en),
        .auth_rs1(auth_rs1),
        .auth_rs2(auth_rs2),
        .key_sel(key_sel),
        .round_sel(round_sel),
        .subkey_in(key_data_in),
        .authorized(authorized),
        .access_error(vault_access_error),
        .subkey_out(subkey_bus),
        .subkey_valid(subkey_valid)
    );

    // Instancia de nuestra unidad criptográfica
    crypto_unit crypto (
        .fround_en(fround_en),
        .mode_decrypt(mode_decrypt),
        .l_in(l_in),
        .r_in(r_in),

        // Conexión directa con la bóveda
        .subkey_in(subkey_bus),
        .subkey_valid(subkey_valid),

        .l_out(l_out),
        .r_out(r_out),
        .result_valid(result_valid),
        .access_error(crypto_access_error)
    );

    // El reloj cambia cada 5 nanosegundos
    always #5 clk = ~clk;

    initial begin

        // Archivo para visualizar señales de simulación
        $dumpfile("tb_crypto_integracion.vcd");
        $dumpvars(0, clk, reset, authorized,
                     fround_en, result_valid,
                     l_in, r_in, l_out, r_out);

        // Inicializar las señales
        reset = 0;
        auth_en = 0;
        logout_en = 0;
        kstore_en = 0;
        fround_en = 0;
        mode_decrypt = 0;

        auth_rs1 = 0;
        auth_rs2 = 0;
        key_sel = 0;
        round_sel = 0;
        key_data_in = 0;
        l_in = 0;
        r_in = 0;

        // Subllaves de nuestra llave de prueba
        keys[0] = 32'h12345678;
        keys[1] = 32'hABCDEF01;
        keys[2] = 32'h98765432;
        keys[3] = 32'hFEDCBA98;

        // PRUEBA 1: Reiniciar la bóveda
        #1 reset = 1;
        #2 reset = 0;

        // PRUEBA 2: Autenticación correcta
        @(negedge clk);
        auth_en = 1;
        auth_rs1 = 32'hC0DE1234;
        auth_rs2 = 32'hABCD5678;

        @(posedge clk);
        #1;

        if (authorized !== 1)
            $fatal(1, "ERROR: AUTH fallo");

        auth_en = 0;
        $display("PASS: Autenticacion correcta");

        // PRUEBA 3: Guardar las cuatro subllaves
        // Usamos la llave completa numero 0
        for (i = 0; i < 4; i = i + 1) begin

            @(negedge clk);
            kstore_en = 1;
            key_sel = 0;
            round_sel = i;
            key_data_in = keys[i];

            @(posedge clk);
            #1;
            kstore_en = 0;

            $display("KSTORE: subllave %0d guardada", i);
        end

        $display("PASS: Cuatro subllaves almacenadas");

        // PRUEBA 4: Cifrar HOLA1234
        current_l = 32'h484F4C41; // HOLA
        current_r = 32'h31323334; // 1234
        mode_decrypt = 0;

        // Ejecutar las cuatro rondas de cifrado
        for (i = 0; i < 4; i = i + 1) begin

            @(negedge clk);
            fround_en = 1;
            key_sel = 0;
            round_sel = i;

            l_in = current_l;
            r_in = current_r;

            @(posedge clk);
            #1;

            if (result_valid !== 1)
                $fatal(1, "ERROR: FROUND no valido");

            // Guardar resultados para la siguiente ronda
            current_l = l_out;
            current_r = r_out;

            fround_en = 0;

            $display("Cifrado ronda %0d completada", i);
        end

        // Comprobar contra el resultado esperado
        if (current_l !== 32'h58991CF5 ||
            current_r !== 32'h18432589)
            $fatal(1, "ERROR: cifrado incorrecto");

        $display("PASS: Cifrado completo correcto");

        // PRUEBA 5: Descifrar el mensaje
        mode_decrypt = 1;

        // Utilizar subllaves en orden inverso
        for (i = 3; i >= 0; i = i - 1) begin

            @(negedge clk);
            fround_en = 1;
            key_sel = 0;
            round_sel = i;

            l_in = current_l;
            r_in = current_r;

            @(posedge clk);
            #1;

            if (result_valid !== 1)
                $fatal(1, "ERROR: descifrado no valido");

            current_l = l_out;
            current_r = r_out;

            fround_en = 0;
        end

        // Verificar que recuperamos HOLA1234
        if (current_l !== 32'h484F4C41 ||
            current_r !== 32'h31323334)
            $fatal(1, "ERROR: descifrado incorrecto");

        $display("PASS: Mensaje recuperado correctamente");

        // PRUEBA 6: Cerrar autorización
        @(negedge clk);
        logout_en = 1;

        @(posedge clk);
        #1;
        logout_en = 0;

        if (authorized !== 0)
            $fatal(1, "ERROR: LOGOUT fallo");

        // PRUEBA 7: FROUND sin autorización
        @(negedge clk);
        fround_en = 1;
        round_sel = 0;
        l_in = current_l;
        r_in = current_r;

        @(posedge clk);
        #1;

        if (result_valid !== 0 ||
            subkey_valid !== 0 ||
            vault_access_error !== 1 ||
            crypto_access_error !== 1)
            $fatal(1, "ERROR: acceso ilegal permitido");

        $display("PASS: Acceso sin autorizacion rechazado");

        fround_en = 0;

        // Finalizar simulación
        $display("--------------------------------");
        $display("TODAS LAS PRUEBAS DE INTEGRACION PASARON");
        $display("--------------------------------");

        $finish;
    end

endmodule


`timescale 1ns/1ps

module tb_crypto_unit;

    // Señales para controlar la operación
    logic fround_en;
    logic mode_decrypt;

    // Las dos mitades del mensaje de 64 bits
    logic [31:0] l_in, r_in;

    // Subllave utilizada en la ronda
    logic [31:0] subkey_in;
    logic subkey_valid;

    // Resultados de la unidad criptográfica
    wire [31:0] l_out, r_out;
    wire result_valid, access_error;

    // Cuatro subllaves para nuestras pruebas
    logic [31:0] keys [0:3];

    // Variables auxiliares para guardar resultados
    logic [31:0] temp_l, temp_r;
    integer i;

    // Instancia de la unidad que queremos probar
    crypto_unit dut (
        .fround_en(fround_en),
        .mode_decrypt(mode_decrypt),
        .l_in(l_in),
        .r_in(r_in),
        .subkey_in(subkey_in),
        .subkey_valid(subkey_valid),
        .l_out(l_out),
        .r_out(r_out),
        .result_valid(result_valid),
        .access_error(access_error)
    );

    initial begin

        // Archivo para visualizar las señales
        $dumpfile("tb_crypto_unit.vcd");
        $dumpvars(0, tb_crypto_unit);

        // Inicializar las señales
        fround_en = 0;
        mode_decrypt = 0;
        subkey_valid = 0;
        subkey_in = 0;

        // Mensaje original: HOLA1234
        // Cada mitad contiene 32 bits en hexadecimal
        l_in = 32'h484F4C41; // HOLA
        r_in = 32'h31323334; // 1234

        // Subllaves de prueba: juntas forman 128 bits
        keys[0] = 32'h12345678;
        keys[1] = 32'hABCDEF01;
        keys[2] = 32'h98765432;
        keys[3] = 32'hFEDCBA98;

        // PRUEBA 1: No ejecutar sin autorización
        fround_en = 1;
        subkey_in = keys[0];
        subkey_valid = 0;

        #1;

        if (access_error !== 1 || result_valid !== 0)
            $fatal(1, "ERROR: FROUND permitio acceso ilegal");

        if (l_out !== 0 || r_out !== 0)
            $fatal(1, "ERROR: FROUND produjo datos sin permiso");

        $display("PASS: FROUND rechazado sin autorizacion");

        // PRUEBA 2: Primera ronda de cifrado
        subkey_valid = 1;
        mode_decrypt = 0;

        #1;

        if (l_out !== 32'h31323334 ||
            r_out !== 32'h36537699)
            $fatal(1, "ERROR: primera ronda incorrecta");

        $display("PASS: Primera ronda correcta");

        // PRUEBA 3: Cifrar las cuatro rondas
        l_in = 32'h484F4C41;
        r_in = 32'h31323334;

        for (i = 0; i < 4; i = i + 1) begin

            // Seleccionar la subllave de esta ronda
            subkey_in = keys[i];

            #1;

            if (result_valid !== 1)
                $fatal(1, "ERROR: ronda sin resultado valido");

            // Guardar las nuevas mitades
            temp_l = l_out;
            temp_r = r_out;

            // Utilizarlas como entrada de la siguiente ronda
            l_in = temp_l;
            r_in = temp_r;
        end

        // Comparar contra el resultado esperado
        if (l_in !== 32'h58991CF5 ||
            r_in !== 32'h18432589)
            $fatal(1, "ERROR: cifrado completo incorrecto");

        $display("PASS: Cifrado de cuatro rondas correcto");
        $display("Bloque cifrado: %h %h", l_in, r_in);

        // PRUEBA 4: Descifrar el bloque obtenido
        mode_decrypt = 1;

        // Las subllaves se utilizan en orden inverso
        for (i = 3; i >= 0; i = i - 1) begin

            subkey_in = keys[i];

            #1;

            if (result_valid !== 1)
                $fatal(1, "ERROR: descifrado sin resultado valido");

            temp_l = l_out;
            temp_r = r_out;

            l_in = temp_l;
            r_in = temp_r;
        end

        // Debemos recuperar exactamente HOLA1234
        if (l_in !== 32'h484F4C41 ||
            r_in !== 32'h31323334)
            $fatal(1, "ERROR: no se recupero el mensaje");

        $display("PASS: Descifrado correcto");
        $display("Mensaje recuperado: %h %h", l_in, r_in);

        $display("--------------------------------");
        $display("TODAS LAS PRUEBAS PASARON");
        $display("--------------------------------");

        $finish;
    end

endmodule

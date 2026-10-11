
`timescale 1ns/1ps

module tb_key_vault;

    // Reloj y reinicio
    logic clk = 0;
    logic reset;

    // Señales para solicitar operaciones
    logic auth_en, logout_en, kstore_en;
    logic fround_en; // Solicita una subllave para FROUND

    // Datos para autenticación y almacenamiento
    logic [31:0] auth_rs1, auth_rs2;
    logic [1:0] key_sel, round_sel;
    logic [31:0] subkey_in;

    // Resultados que devuelve la bóveda
    wire authorized, access_error;

    // Salidas internas para FROUND
    wire [31:0] subkey_out;
    wire subkey_valid;

    // Instancia del módulo que queremos probar
    key_vault dut (
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
        .subkey_in(subkey_in),
        .authorized(authorized),
        .access_error(access_error),
        .subkey_out(subkey_out),
        .subkey_valid(subkey_valid)
    );

    // El reloj cambia cada 5 ns
    always #5 clk = ~clk;

    initial begin
        $dumpfile("tb_key_vault.vcd");
        $dumpvars(0, tb_key_vault);

        // Inicializar las señales
        reset = 0;
        auth_en = 0;
        logout_en = 0;
        kstore_en = 0;
        fround_en = 0;

        auth_rs1 = 0;
        auth_rs2 = 0;
        key_sel = 0;
        round_sel = 0;
        subkey_in = 0;

        // PRUEBA 1: Reiniciar la bóveda
        #1 reset = 1;
        #2;

        if (authorized !== 0)
            $fatal(1, "ERROR: reset no elimino autorizacion");

        reset = 0;
        $display("PASS: RESET correcto");

        // PRUEBA 2: Guardar sin autorización
        @(negedge clk);
        kstore_en = 1;
        key_sel = 2;
        round_sel = 1;
        subkey_in = 32'h12345678;

        @(posedge clk);
        #1;

        if (access_error !== 1)
            $fatal(1, "ERROR: se permitio acceso sin AUTH");

        if (dut.subkeys[2][1] !== 32'b0)
            $fatal(1, "ERROR: se guardo sin autorizacion");

        $display("PASS: KSTORE rechazado sin AUTH");
        kstore_en = 0;

        // PRUEBA 3: Autenticación incorrecta
        @(negedge clk);
        auth_en = 1;
        auth_rs1 = 32'h00000000;
        auth_rs2 = 32'h00000000;

        @(posedge clk);
        #1;

        if (authorized !== 0 || access_error !== 1)
            $fatal(1, "ERROR: AUTH incorrecto fue aceptado");

        $display("PASS: AUTH incorrecto rechazado");
        auth_en = 0;

        // PRUEBA 4: Autenticación correcta
        @(negedge clk);
        auth_en = 1;
        auth_rs1 = 32'hC0DE1234;
        auth_rs2 = 32'hABCD5678;

        @(posedge clk);
        #1;

        if (authorized !== 1)
            $fatal(1, "ERROR: fallo la autenticacion");

        $display("PASS: AUTH correcto");
        auth_en = 0;

        // PRUEBA 5: Guardar con autorización
        @(negedge clk);
        kstore_en = 1;

        @(posedge clk);
        #1;

        if (dut.subkeys[2][1] !== 32'h12345678)
            $fatal(1, "ERROR: no se guardo la subllave");

        $display("PASS: KSTORE correcto");
        kstore_en = 0;

        // PRUEBA 6: FROUND solicita una subllave
        // Debe recibir la subllave guardada anteriormente
        @(negedge clk);
        fround_en = 1;

        #1;

        if (subkey_valid !== 1)
            $fatal(1, "ERROR: FROUND no tiene acceso autorizado");

        if (subkey_out !== 32'h12345678)
            $fatal(1, "ERROR: FROUND recibio una subllave incorrecta");

        $display("PASS: FROUND obtiene la subllave correcta");

        @(posedge clk);
        #1;
        fround_en = 0;

        // PRUEBA 7: Cerrar autorización
        @(negedge clk);
        logout_en = 1;

        @(posedge clk);
        #1;

        if (authorized !== 0)
            $fatal(1, "ERROR: LOGOUT fallo");

        $display("PASS: LOGOUT correcto");
        logout_en = 0;

        // PRUEBA 8: FROUND sin autorización
        // La bóveda no debe entregar la subllave
        @(negedge clk);
        fround_en = 1;

        #1;

        if (subkey_valid !== 0)
            $fatal(1, "ERROR: FROUND accedio sin autorizacion");

        if (subkey_out !== 32'b0)
            $fatal(1, "ERROR: se expuso una subllave protegida");

        @(posedge clk);
        #1;

        if (access_error !== 1)
            $fatal(1, "ERROR: no se detecto acceso ilegal");

        $display("PASS: FROUND rechazado sin AUTH");
        fround_en = 0;

        // PRUEBA 9: Reset elimina las subllaves
        @(negedge clk);
        reset = 1;

        #1;

        if (dut.subkeys[2][1] !== 32'b0)
            $fatal(1, "ERROR: reset no borro la subllave");

        if (authorized !== 0)
            $fatal(1, "ERROR: reset no elimino autorizacion");

        if (access_error !== 0)
            $fatal(1, "ERROR: reset no limpio el error");

        $display("PASS: RESET borra las subllaves");
        reset = 0;

        // Finalizar simulación
        $display("--------------------------------");
        $display("TODAS LAS PRUEBAS PASARON");
        $display("--------------------------------");

        $finish;
    end

endmodule

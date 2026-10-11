
`timescale 1ns/1ps

module tb_stall_boveda;

    logic clk_i = 0;
    logic rst_i;
    logic stall_i;

    wire [31:0] pc_o;
    wire [127:0] bundle_o;
    wire fetch_valid_o;

    integer i;
    integer auth_veces = 0;
    integer kstore_veces = 0;

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

    always #5 clk_i = ~clk_i;

    // Construir AUTH: mismos bits que la prueba anterior
    function automatic [31:0] feist_auth(
        input [3:0] rs2,
        input [3:0] rs1
    );
        feist_auth = {21'b0, rs2, rs1, 3'b001};
    endfunction

    // Construir KSTORE
    function automatic [31:0] feist_kstore(
        input [1:0] key,
        input [1:0] round,
        input [3:0] rs1
    );
        feist_kstore = {21'b0, key, round, rs1, 3'b011};
    endfunction

    // Contar las solicitudes que llegan a la boveda
    always @(posedge clk_i) begin
        if (!rst_i) begin
            if (dut.ex_feist_auth_req)
                auth_veces = auth_veces + 1;

            if (dut.ex_feist_kstore_req)
                kstore_veces = kstore_veces + 1;
        end
    end

    initial begin
        rst_i = 1;
        stall_i = 0;

        #1;

        // Programa vacio: los espacios son NOPs
        for (i = 0; i < 128; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 0;

        // Primera instruccion: AUTH
        dut.fetch_inst.instruction_memory_inst.memory[0] = {
            feist_auth(4'd3, 4'd2), 96'b0
        };

        // Segunda instruccion: KSTORE
        dut.fetch_inst.instruction_memory_inst.memory[8] = {
            feist_kstore(0, 0, 4'd11), 96'b0
        };

        // Preparar credenciales y subllave
        @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 0;

        dut.regfile_inst.regs[2] = 32'hC0DE1234;
        dut.regfile_inst.regs[3] = 32'hABCD5678;
        dut.regfile_inst.regs[11] = 32'h12345678;

        // ==================================
        // PRUEBA 1: AUTH DURANTE STALL
        // ==================================

        wait (dut.ex_feist_auth_en === 1'b1 &&
              dut.rr_ex_valid_out === 1'b1);

        @(negedge clk_i);
        stall_i = 1;

        $display("STALL activado durante AUTH");

        repeat (3) begin
            @(posedge clk_i);
            #1;

            if (dut.ex_feist_auth_req !== 1'b0 ||
                dut.key_vault_inst.authorized !== 1'b0 ||
                auth_veces != 0)
                $fatal(1, "ERROR: AUTH se ejecuto durante stall");
        end

        $display("PASS: AUTH espero durante stall");

        @(negedge clk_i);
        stall_i = 0;

        @(posedge clk_i);
        #1;

        if (dut.key_vault_inst.authorized !== 1'b1 ||
            auth_veces != 1)
            $fatal(1, "ERROR: AUTH no se ejecuto una sola vez");

        $display("PASS: AUTH ejecutado una sola vez");

        // ==================================
        // PRUEBA 2: KSTORE DURANTE STALL
        // ==================================

        wait (dut.ex_feist_kstore_en === 1'b1 &&
              dut.rr_ex_valid_out === 1'b1);

        @(negedge clk_i);
        stall_i = 1;

        $display("STALL activado durante KSTORE");

        repeat (3) begin
            @(posedge clk_i);
            #1;

            if (dut.ex_feist_kstore_req !== 1'b0 ||
                dut.key_vault_inst.subkeys[0][0] !== 32'b0 ||
                kstore_veces != 0)
                $fatal(1, "ERROR: KSTORE se ejecuto durante stall");
        end

        $display("PASS: KSTORE espero durante stall");

        @(negedge clk_i);
        stall_i = 0;

        @(posedge clk_i);
        #1;

        if (dut.key_vault_inst.subkeys[0][0] !== 32'h12345678 ||
            kstore_veces != 1)
            $fatal(1, "ERROR: KSTORE no guardo una sola vez");

        $display("PASS: KSTORE guardo la subllave una sola vez");

        $display("--------------------------------");
        $display("PRUEBA STALL + BOVEDA SUPERADA");
        $display("--------------------------------");

        $finish;
    end

    // Limite de tiempo por seguridad
    initial begin
        #1000;
        $fatal(1, "ERROR: tiempo de espera agotado");
    end

endmodule

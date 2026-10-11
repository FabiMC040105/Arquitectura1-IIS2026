`timescale 1ns/1ps

// Prueba de integracion de la unidad Feistel4 dentro del pipeline.
// Comprueba el camino completo AUTH -> KSTORE -> FROUND, la escritura
// de las dos mitades al register file y que la boveda rechace los
// accesos sin autenticacion.
module tb_feistel;

    logic clk_i;
    logic rst_i;
    logic stall_i;

    logic [31:0]  pc_o;
    logic [127:0] bundle_o;
    logic         fetch_valid_o;

    logic [31:0] instr_alu_o;
    logic [31:0] instr_lsu_o;
    logic [31:0] instr_bru_o;
    logic [31:0] instr_feist_o;

    logic valid_alu_o;
    logic valid_lsu_o;
    logic valid_bru_o;
    logic valid_feist_o;
    logic dispatch_valid_o;

    // IMEM_WORDS cuenta palabras de 32 bits: hacen falta cuatro por
    // bundle. El programa llega hasta el bundle 24, asi que 256
    // palabras (64 bundles) dejan margen de sobra.
    top #(
        .IMEM_WORDS(256)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .stall_i(stall_i),

        .pc_o(pc_o),
        .bundle_o(bundle_o),
        .fetch_valid_o(fetch_valid_o),

        .instr_alu_o(instr_alu_o),
        .instr_lsu_o(instr_lsu_o),
        .instr_bru_o(instr_bru_o),
        .instr_feist_o(instr_feist_o),

        .valid_alu_o(valid_alu_o),
        .valid_lsu_o(valid_lsu_o),
        .valid_bru_o(valid_bru_o),
        .valid_feist_o(valid_feist_o),
        .dispatch_valid_o(dispatch_valid_o)
    );

    // Reloj de 10 ns.
    initial clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    // ---------------------------------------------------------
    // CONSTRUCTORES DE INSTRUCCIONES
    // ---------------------------------------------------------

    // ALU tipo I: imm[23:12], rs1[11:8], rd[7:4], imm_op[3], opcode[2:0]
    function automatic [31:0] alu_i(
        input [11:0] imm,
        input [3:0]  rs1,
        input [3:0]  rd,
        input [2:0]  opcode
    );
        alu_i = {8'b0, imm, rs1, rd, 1'b1, opcode};
    endfunction

    // AUTH: rs2[10:7], rs1[6:3], opcode[2:0]
    function automatic [31:0] feist_auth(
        input [3:0] rs2,
        input [3:0] rs1
    );
        feist_auth = {21'b0, rs2, rs1, 3'b001};
    endfunction

    // LOGOUT: opcode[2:0]
    function automatic [31:0] feist_logout();
        feist_logout = {29'b0, 3'b010};
    endfunction

    // KSTORE: key[10:9], round[8:7], rs1[6:3], opcode[2:0]
    function automatic [31:0] feist_kstore(
        input [1:0] key,
        input [1:0] round,
        input [3:0] rs1
    );
        feist_kstore = {21'b0, key, round, rs1, 3'b011};
    endfunction

    // FROUND: rdL[23:20], rdR[19:16], rsL[15:12], rsR[11:8],
    //         key[7:6], round[5:4], mode[3], opcode[2:0]
    function automatic [31:0] feist_round(
        input [3:0] rdL,
        input [3:0] rdR,
        input [3:0] rsL,
        input [3:0] rsR,
        input [1:0] key,
        input [1:0] round,
        input       mode
    );
        feist_round = {8'b0, rdL, rdR, rsL, rsR, key, round, mode, 3'b100};
    endfunction

    // Coloca una instruccion Feistel en el slot 3 del bundle.
    function automatic [127:0] bundle_feist(input [31:0] instr);
        bundle_feist = {instr, 96'b0};
    endfunction

    // Coloca una instruccion ALU en el slot 0 del bundle.
    function automatic [127:0] bundle_alu(input [31:0] instr);
        bundle_alu = {96'b0, instr};
    endfunction

    localparam ADDI = 3'b001;

    // Credenciales cableadas en key_vault.
    localparam logic [31:0] AUTH_ID   = 32'hC0DE1234;
    localparam logic [31:0] AUTH_PASS = 32'hABCD5678;

    // ---------------------------------------------------------
    // MODELO DE REFERENCIA DE LA RONDA FEISTEL
    // ---------------------------------------------------------

    function automatic [31:0] rol32(input [31:0] x, input integer r);
        rol32 = (x << r) | (x >> (32 - r));
    endfunction

    function automatic [31:0] feistel_f(input [31:0] x, input [31:0] k);
        feistel_f = (rol32(x, 5) + k) ^ rol32(x, 13);
    endfunction

    // Una ronda de cifrado: L' = R, R' = L ^ F(R, k)
    task automatic ref_encrypt(
        input  [31:0] l, r, k,
        output [31:0] l_next, r_next
    );
        l_next = r;
        r_next = l ^ feistel_f(r, k);
    endtask

    integer ciclo;
    integer errores;

    logic [31:0] exp_l;
    logic [31:0] exp_r;

    // Valores de prueba.
    localparam logic [31:0] BLOCK_L = 32'h0123_4567;
    localparam logic [31:0] BLOCK_R = 32'h89AB_CDEF;
    localparam logic [31:0] SUBKEY  = 32'hDEAD_BEEF;

    // Espera a que el pipeline se vacie.
    task automatic drenar(input integer n);
        integer i;
        for (i = 0; i < n; i = i + 1) @(posedge clk_i);
    endtask

    // ---------------------------------------------------------
    // MONITOR
    // ---------------------------------------------------------
    //
    // Esperar un numero fijo de ciclos entre comprobaciones es
    // fragil: basta con desfasarse un ciclo para mirar el register
    // file antes o despues de la escritura. En su lugar, un monitor
    // continuo captura el estado en el instante exacto en que cada
    // evento ocurre y las aserciones se evaluan al final.

    // Estado capturado por el monitor.
    logic        visto_auth;          // la boveda llego a autorizar
    logic        visto_kstore;        // la subllave llego a la boveda
    logic        visto_logout;        // la autorizacion se revoco

    logic [31:0] cap_l_out;           // resultado de la ronda legitima
    logic [31:0] cap_r_out;
    logic        visto_fround_ok;     // la ronda legitima produjo salida

    logic        visto_fround_ilegal; // alguna ronda sin permiso escribio

    // El monitor sigue el orden del programa: la fase sin autenticar
    // ocurre antes del AUTH y el LOGOUT despues de la ronda legitima.
    always @(posedge clk_i) begin
        if (rst_i) begin
            visto_auth          <= 1'b0;
            visto_kstore        <= 1'b0;
            visto_logout        <= 1'b0;
            visto_fround_ok     <= 1'b0;
            visto_fround_ilegal <= 1'b0;
            cap_l_out           <= 32'b0;
            cap_r_out           <= 32'b0;
        end
        else begin
            // La boveda paso a autorizada en algun momento.
            if (dut.key_vault_inst.authorized)
                visto_auth <= 1'b1;

            // La subllave quedo guardada.
            if (dut.key_vault_inst.subkeys[0][0] == SUBKEY)
                visto_kstore <= 1'b1;

            // Tras haber estado autorizada, volvio a estar cerrada.
            if (visto_auth && !dut.key_vault_inst.authorized)
                visto_logout <= 1'b1;

            // Una ronda produjo un resultado valido. Capturamos las
            // mitades en el mismo ciclo en que la unidad las calcula.
            if (dut.ex_feist_result_valid) begin
                cap_l_out       <= dut.ex_feist_l_out;
                cap_r_out       <= dut.ex_feist_r_out;
                visto_fround_ok <= 1'b1;
            end

            // Una ronda solicitada sin autorizacion jamas debe
            // producir un resultado valido.
            if (dut.ex_feist_fround_req && !dut.key_vault_inst.authorized &&
                dut.ex_feist_result_valid)
                visto_fround_ilegal <= 1'b1;
        end
    end

    initial begin
        $display("========================================");
        $display("Inicio de pruebas de FEISTEL");
        $display("========================================");
        errores = 0;
        rst_i   = 1'b1;
        stall_i = 1'b0;

        // =====================================================
        // PROGRAMA DE PRUEBA
        // =====================================================
        //
        // Primero una fase sin autenticar para comprobar que la
        // boveda rechaza KSTORE y FROUND, y despues la secuencia
        // legitima AUTH -> KSTORE -> FROUND.

        // Cargar los operandos en registros con el slot ALU.
        //   x2 = AUTH_ID, x3 = AUTH_PASS se cargan por fuerza bruta
        //   mas abajo (el ADDI solo tiene 12 bits de inmediato).
        //   x4 = subllave, x5 = L, x6 = R
        dut.fetch_inst.instruction_memory_inst.memory[0] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[1] = 128'b0;

        // bundle 2: KSTORE sin autenticar -> debe fallar.
        dut.fetch_inst.instruction_memory_inst.memory[2] =
            bundle_feist(feist_kstore(2'd0, 2'd0, 4'd4));

        // bundle 3: FROUND sin autenticar -> debe fallar.
        dut.fetch_inst.instruction_memory_inst.memory[3] =
            bundle_feist(feist_round(4'd7, 4'd8, 4'd5, 4'd6,
                                     2'd0, 2'd0, 1'b0));

        dut.fetch_inst.instruction_memory_inst.memory[4] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[5] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[6] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[7] = 128'b0;

        // bundle 8: AUTH con las credenciales correctas.
        dut.fetch_inst.instruction_memory_inst.memory[8] =
            bundle_feist(feist_auth(4'd3, 4'd2));

        dut.fetch_inst.instruction_memory_inst.memory[9]  = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[10] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[11] = 128'b0;

        // bundle 12: KSTORE autenticado -> guarda x4 en key0/round0.
        dut.fetch_inst.instruction_memory_inst.memory[12] =
            bundle_feist(feist_kstore(2'd0, 2'd0, 4'd4));

        dut.fetch_inst.instruction_memory_inst.memory[13] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[14] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[15] = 128'b0;

        // bundle 16: FROUND autenticado, cifrado.
        //   x7 = L', x8 = R' a partir de x5 = L, x6 = R
        dut.fetch_inst.instruction_memory_inst.memory[16] =
            bundle_feist(feist_round(4'd7, 4'd8, 4'd5, 4'd6,
                                     2'd0, 2'd0, 1'b0));

        dut.fetch_inst.instruction_memory_inst.memory[17] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[18] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[19] = 128'b0;

        // bundle 20: LOGOUT.
        dut.fetch_inst.instruction_memory_inst.memory[20] =
            bundle_feist(feist_logout());

        dut.fetch_inst.instruction_memory_inst.memory[21] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[22] = 128'b0;
        dut.fetch_inst.instruction_memory_inst.memory[23] = 128'b0;

        // bundle 24: FROUND despues del LOGOUT -> debe fallar.
        //   escribe en x9 y x10, que deben quedar en cero.
        dut.fetch_inst.instruction_memory_inst.memory[24] =
            bundle_feist(feist_round(4'd9, 4'd10, 4'd5, 4'd6,
                                     2'd0, 2'd0, 1'b0));

        for (ciclo = 25; ciclo < 64; ciclo = ciclo + 1)
            dut.fetch_inst.instruction_memory_inst.memory[ciclo] = 128'b0;

        // Precargar los registros fuente directamente: el inmediato
        // del ADDI no alcanza para constantes de 32 bits.
        @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        dut.regfile_inst.regs[2] = AUTH_ID;
        dut.regfile_inst.regs[3] = AUTH_PASS;
        dut.regfile_inst.regs[4] = SUBKEY;
        dut.regfile_inst.regs[5] = BLOCK_L;
        dut.regfile_inst.regs[6] = BLOCK_R;

        // =====================================================
        // 1. La boveda arranca cerrada
        // =====================================================

        // Los bundles 2 y 3 intentan KSTORE y FROUND sin autenticar.
        // Se comprueban antes de que el AUTH del bundle 8 llegue a EX.
        drenar(10);
        #1;

        if (dut.key_vault_inst.authorized !== 1'b0) begin
            $display("ERROR: la boveda quedo autorizada sin AUTH");
            errores = errores + 1;
        end
        else
            $display("PASS: la boveda arranca sin autorizacion");

        if (dut.key_vault_inst.subkeys[0][0] !== 32'b0) begin
            $display("ERROR: KSTORE sin autenticar escribio la boveda");
            errores = errores + 1;
        end
        else
            $display("PASS: KSTORE sin autenticar no escribe la boveda");

        if (dut.regfile_inst.regs[7] !== 32'b0 ||
            dut.regfile_inst.regs[8] !== 32'b0) begin
            $display("ERROR: FROUND sin autenticar escribio x7/x8");
            errores = errores + 1;
        end
        else
            $display("PASS: FROUND sin autenticar no escribe el regfile");

        // =====================================================
        // 2. Ejecutar el resto del programa
        // =====================================================
        //
        // AUTH, KSTORE, FROUND y LOGOUT. El monitor captura cada
        // evento en el ciclo exacto en que ocurre, asi que basta con
        // dejar correr el pipeline hasta el final del programa.

        drenar(40);
        #1;

        // ----- AUTH -----
        if (!visto_auth) begin
            $display("ERROR: AUTH no autorizo la boveda");
            errores = errores + 1;
        end
        else
            $display("PASS: AUTH con credenciales correctas autoriza");

        // ----- KSTORE -----
        if (!visto_kstore) begin
            $display("ERROR: KSTORE no guardo la subllave (%h)",
                     dut.key_vault_inst.subkeys[0][0]);
            errores = errores + 1;
        end
        else
            $display("PASS: KSTORE autenticado guarda la subllave");

        // ----- FROUND -----
        ref_encrypt(BLOCK_L, BLOCK_R, SUBKEY, exp_l, exp_r);

        if (!visto_fround_ok) begin
            $display("ERROR: la ronda autorizada nunca produjo resultado");
            errores = errores + 1;
        end
        else begin
            if (cap_l_out !== exp_l) begin
                $display("ERROR: L' = %h, se esperaba %h", cap_l_out, exp_l);
                errores = errores + 1;
            end
            else
                $display("PASS: la ronda calcula L' = %h", exp_l);

            if (cap_r_out !== exp_r) begin
                $display("ERROR: R' = %h, se esperaba %h", cap_r_out, exp_r);
                errores = errores + 1;
            end
            else
                $display("PASS: la ronda calcula R' = %h", exp_r);
        end

        // Las mitades deben haber llegado al register file.
        if (dut.regfile_inst.regs[7] !== exp_l) begin
            $display("ERROR: x7 = %h, se esperaba L' = %h",
                     dut.regfile_inst.regs[7], exp_l);
            errores = errores + 1;
        end
        else
            $display("PASS: FROUND escribe L' en x7");

        if (dut.regfile_inst.regs[8] !== exp_r) begin
            $display("ERROR: x8 = %h, se esperaba R' = %h",
                     dut.regfile_inst.regs[8], exp_r);
            errores = errores + 1;
        end
        else
            $display("PASS: FROUND escribe R' en x8");

        // ----- LOGOUT -----
        if (!visto_logout) begin
            $display("ERROR: LOGOUT no revoco la autorizacion");
            errores = errores + 1;
        end
        else
            $display("PASS: LOGOUT revoca la autorizacion");

        if (dut.key_vault_inst.authorized !== 1'b0) begin
            $display("ERROR: la boveda quedo autorizada al final");
            errores = errores + 1;
        end
        else
            $display("PASS: la boveda termina cerrada");

        // ----- FROUND tras LOGOUT -----
        if (visto_fround_ilegal) begin
            $display("ERROR: una ronda sin autorizacion produjo resultado");
            errores = errores + 1;
        end
        else
            $display("PASS: ninguna ronda sin autorizacion produjo resultado");

        if (dut.regfile_inst.regs[9] !== 32'b0 ||
            dut.regfile_inst.regs[10] !== 32'b0) begin
            $display("ERROR: FROUND tras LOGOUT escribio x9/x10");
            errores = errores + 1;
        end
        else
            $display("PASS: FROUND tras LOGOUT no escribe el regfile");

        // =====================================================
        // 7. Las llaves nunca aparecen en el register file
        // =====================================================

        // x4 contiene la subllave legitimamente: es el operando que
        // el programa entrego a KSTORE. Ningun otro registro debe
        // haberla recibido desde la boveda.
        for (ciclo = 0; ciclo < 16; ciclo = ciclo + 1) begin
            if (ciclo != 4 &&
                dut.regfile_inst.regs[ciclo] === SUBKEY) begin
                $display("ERROR: la subllave aparecio en x%0d", ciclo);
                errores = errores + 1;
            end
        end

        if (errores == 0)
            $display("PASS: ninguna subllave se exporto al register file");

        if (errores != 0)
            $fatal(1, "FALLARON %0d PRUEBAS DE FEISTEL", errores);

        $display("========================================");
        $display("Pruebas de FEISTEL finalizadas: TODAS PASARON");
        $display("========================================");
        $finish;
    end

endmodule

`timescale 1ns/1ps

module tb_cache_stall_store;

    logic clk_i = 1'b0;
    logic rst_i;
    logic stall_i;

    // En development top.sv tambien recibe un reloj para la memoria legacy.
    // En este test se usa el mismo reloj del procesador.
    wire clk_mem_i = clk_i;

    // Interfaz de cache simulada.
    logic        cache_ready_i;
    logic        cache_stall_i;
    logic [31:0] cache_read_data_i;

    wire         cache_read_o;
    wire         cache_write_o;
    wire [31:0]  cache_addr_o;
    wire [31:0]  cache_write_data_o;
    wire         global_stall_o;

    wire [31:0]  pc_o;
    wire [127:0] bundle_o;
    wire         fetch_valid_o;

    integer i;
    integer timeout;
    integer accepted_stores = 0;
    integer writes_x4 = 0;
    integer observed_stall_cycles = 0;

    logic [31:0] pc_hold;
    logic [159:0] if_id_hold;
    logic [166:0] id_rr_hold;
    logic [478:0] rr_ex_hold;
    logic [178:0] ex_wb_hold;
    logic [31:0] legacy_word0;
    logic [31:0] pc_before_hit;

    top #(
        .IMEM_WORDS(256),
        .PROGRAM_FILE("program_test.mem"),
        .CACHE_IF_EN(1'b1)
    ) dut (
        .clk_i(clk_i),
        .clk_mem_i(clk_mem_i),
        .rst_i(rst_i),
        .stall_i(stall_i),

        .cache_ready_i(cache_ready_i),
        .cache_stall_i(cache_stall_i),
        .cache_read_data_i(cache_read_data_i),

        .cache_read_o(cache_read_o),
        .cache_write_o(cache_write_o),
        .cache_addr_o(cache_addr_o),
        .cache_write_data_o(cache_write_data_o),
        .global_stall_o(global_stall_o),

        .pc_o(pc_o),
        .bundle_o(bundle_o),
        .fetch_valid_o(fetch_valid_o)
    );

    always #5 clk_i = ~clk_i;

    // ADDI rd, rs1, imm
    function automatic [31:0] alu_addi(
        input [11:0] imm,
        input [3:0]  rs1,
        input [3:0]  rd
    );
        alu_addi = {
            8'b0,
            imm,
            rs1,
            rd,
            1'b1,
            3'b001
        };
    endfunction

    // STORE rs1, offset(base)
    function automatic [31:0] lsu_store(
        input [11:0] offset,
        input [3:0]  base,
        input [3:0]  rs1
    );
        lsu_store = {
            10'b0,
            offset,
            base,
            rs1,
            2'b10
        };
    endfunction

    // Contar solo transacciones realmente aceptadas por la cache.
    // Una solicitud puede permanecer alta varios ciclos durante backpressure,
    // pero debe aceptarse una sola vez cuando ready=1 y stall=0.
    always @(posedge clk_i) begin
        if (!rst_i) begin
            if (global_stall_o)
                observed_stall_cycles = observed_stall_cycles + 1;

            if (cache_write_o && cache_ready_i && !cache_stall_i)
                accepted_stores = accepted_stores + 1;

            if (dut.regfile_wr_en[0] &&
                dut.regfile_wr_addr[0] == 4'd4)
                writes_x4 = writes_x4 + 1;
        end
    end

    initial begin
        $dumpfile("cache_stall_store.vcd");
        $dumpvars(0, tb_cache_stall_store);

        rst_i = 1'b1;
        stall_i = 1'b0;
        cache_ready_i = 1'b0;
        cache_stall_i = 1'b0;
        cache_read_data_i = 32'b0;

        #1;

        // Programa controlado por el testbench.
        for (i = 0; i < 32; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 128'b0;

        // Bundle 0:
        //   ALU:   ADDI x4, x0, 7
        //   LSU:   STORE x2, 0(x0)
        //
        // El STORE sufrira backpressure simulado durante tres ciclos.
        // El ALU del mismo bundle tampoco debe avanzar.
        dut.fetch_inst.instruction_memory_inst.memory[0] = {
            64'b0,
            lsu_store(12'd0, 4'd0, 4'd2),
            alu_addi(12'd7, 4'd0, 4'd4)
        };

        // Segundo STORE independiente. Se respondera como hit/sin stall.
        dut.fetch_inst.instruction_memory_inst.memory[8] = {
            64'b0,
            lsu_store(12'd4, 4'd0, 4'd3),
            32'b0
        };

        // Liberar reset.
        @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        // Datos que consumiran los STORE.
        dut.regfile_inst.regs[2] = 32'hA1B2C3D4;
        dut.regfile_inst.regs[3] = 32'h55667788;

        // Guardar la palabra 0 de la memoria legacy. En CACHE_IF_EN=1
        // esta memoria no debe recibir el STORE.
        legacy_word0 = {
            dut.data_memory_inst.memory[3],
            dut.data_memory_inst.memory[2],
            dut.data_memory_inst.memory[1],
            dut.data_memory_inst.memory[0]
        };

        // =============================================================
        // PRUEBA 1: STORE + BACKPRESSURE -> STALL DEL BUNDLE COMPLETO
        // =============================================================

        timeout = 0;
        while (!(cache_write_o === 1'b1 &&
                 cache_addr_o === 32'h00000000) &&
               timeout < 30) begin
            @(posedge clk_i);
            #1;
            timeout = timeout + 1;
        end

        if (timeout >= 30)
            $fatal(1, "ERROR: no aparecio la primera solicitud STORE hacia cache");

        if (cache_write_data_o !== 32'hA1B2C3D4)
            $fatal(1,
                "ERROR: STORE presento dato incorrecto: %h",
                cache_write_data_o);

        if (cache_read_o !== 1'b0)
            $fatal(1, "ERROR: STORE activo cache_read_o");

        $display(
            "Solicitud STORE observada: addr=0x%08h data=0x%08h",
            cache_addr_o,
            cache_write_data_o
        );

        // La cache aplica backpressure antes del siguiente flanco.
        @(negedge clk_i);
        cache_stall_i = 1'b1;
        cache_ready_i = 1'b0;

        pc_hold    = pc_o;
        if_id_hold = dut.if_id_data_out;
        id_rr_hold = dut.id_rr_data_out;
        rr_ex_hold = dut.rr_ex_data_out;
        ex_wb_hold = dut.ex_wb_data_out;

        repeat (3) begin
            @(posedge clk_i);
            #1;

            if (global_stall_o !== 1'b1)
                $fatal(1, "ERROR: cache_stall_i no genero global_stall");

            if (pc_o !== pc_hold)
                $fatal(1, "ERROR: PC avanzo durante STORE stall");

            if (dut.if_id_data_out !== if_id_hold)
                $fatal(1, "ERROR: IF/ID cambio durante STORE stall");

            if (dut.id_rr_data_out !== id_rr_hold)
                $fatal(1, "ERROR: ID/RR cambio durante STORE stall");

            if (dut.rr_ex_data_out !== rr_ex_hold)
                $fatal(1, "ERROR: RR/EX cambio durante STORE stall");

            if (dut.ex_wb_data_out !== ex_wb_hold)
                $fatal(1, "ERROR: EX/WB cambio durante STORE stall");

            // La solicitud debe permanecer presentada mientras la cache
            // mantiene el backpressure.
            if (cache_write_o !== 1'b1)
                $fatal(1, "ERROR: STORE desaparecio durante cache stall");

            if (cache_addr_o !== 32'h00000000)
                $fatal(1, "ERROR: direccion STORE cambio durante stall");

            if (cache_write_data_o !== 32'hA1B2C3D4)
                $fatal(1, "ERROR: dato STORE cambio durante stall");

            if (cache_read_o !== 1'b0)
                $fatal(1, "ERROR: cache_read_o activo durante STORE");

            // La cache aun no ha aceptado ninguna escritura.
            if (accepted_stores !== 0)
                $fatal(1,
                    "ERROR: STORE fue aceptado durante backpressure (%0d)",
                    accepted_stores);

            // La ALU del mismo bundle tampoco puede escribir.
            if (writes_x4 !== 0 ||
                dut.regfile_inst.regs[4] !== 32'd0)
                $fatal(1,
                    "ERROR: slot ALU avanzo durante STORE stall");
        end

        $display("PASS: STORE mantiene request, direccion y dato durante backpressure");
        $display("PASS: cache stall congela PC y todos los registros del pipeline");
        $display("PASS: el slot ALU del mismo bundle tampoco avanza");

        // La cache acepta la escritura.
        @(negedge clk_i);
        cache_stall_i = 1'b0;
        cache_ready_i = 1'b1;

        @(posedge clk_i);
        #1;

        if (global_stall_o !== 1'b0)
            $fatal(1, "ERROR: global_stall no se libero al aceptar STORE");

        if (accepted_stores !== 1)
            $fatal(1,
                "ERROR: primer STORE fue aceptado %0d veces",
                accepted_stores);

        // ready solo durante la transferencia aceptada.
        @(negedge clk_i);
        cache_ready_i = 1'b0;

        // Esperar que la ALU del bundle llegue a WB.
        timeout = 0;
        while (writes_x4 < 1 && timeout < 12) begin
            @(posedge clk_i);
            #1;
            timeout = timeout + 1;
        end

        if (timeout >= 12)
            $fatal(1, "ERROR: timeout esperando ALU despues del STORE stall");

        if (dut.regfile_inst.regs[4] !== 32'd7)
            $fatal(1, "ERROR: ALU del bundle no escribio x4=7");

        if (writes_x4 !== 1)
            $fatal(1,
                "ERROR: ALU del bundle escribio %0d veces",
                writes_x4);

        // En modo cache, la memoria interna legacy no debe modificarse.
        if ({
            dut.data_memory_inst.memory[3],
            dut.data_memory_inst.memory[2],
            dut.data_memory_inst.memory[1],
            dut.data_memory_inst.memory[0]
        } !== legacy_word0)
            $fatal(1,
                "ERROR: STORE de cache tambien modifico data_memory legacy");

        $display("PASS: primer STORE fue aceptado exactamente una vez");
        $display("PASS: bundle reanudo sin duplicar efectos");
        $display("PASS: data_memory legacy permanecio aislada en CACHE_IF_EN=1");

        // =============================================================
        // PRUEBA 2: STORE TIPO HIT -> SIN STALL
        // =============================================================

        timeout = 0;
        while (!(cache_write_o === 1'b1 &&
                 cache_addr_o === 32'h00000004) &&
               timeout < 30) begin
            @(posedge clk_i);
            #1;
            timeout = timeout + 1;
        end

        if (timeout >= 30)
            $fatal(1, "ERROR: no aparecio el segundo STORE");

        if (cache_write_data_o !== 32'h55667788)
            $fatal(1,
                "ERROR: segundo STORE presento dato incorrecto: %h",
                cache_write_data_o);

        if (global_stall_o !== 1'b0)
            $fatal(1, "ERROR: STORE hit genero stall antes de respuesta");

        // Respuesta inmediata, sin cache_stall_i.
        @(negedge clk_i);
        pc_before_hit = pc_o;
        cache_stall_i = 1'b0;
        cache_ready_i = 1'b1;

        @(posedge clk_i);
        #1;

        if (global_stall_o !== 1'b0)
            $fatal(1, "ERROR: STORE hit genero global_stall");

        if (pc_o !== pc_before_hit + 32'd16)
            $fatal(1, "ERROR: PC no avanzo normalmente durante STORE hit");

        if (accepted_stores !== 2)
            $fatal(1,
                "ERROR: total de STORE aceptados = %0d, esperado 2",
                accepted_stores);

        @(negedge clk_i);
        cache_ready_i = 1'b0;

        // Asegurar que ninguna transaccion se repita despues.
        repeat (5) @(posedge clk_i);
        #1;

        if (accepted_stores !== 2)
            $fatal(1,
                "ERROR: hubo STORE duplicado, total=%0d",
                accepted_stores);

        if (writes_x4 !== 1)
            $fatal(1,
                "ERROR: se repitio efecto ALU, total=%0d",
                writes_x4);

        if (observed_stall_cycles !== 3)
            $fatal(1,
                "ERROR: se observaron %0d ciclos de stall, esperados 3",
                observed_stall_cycles);

        $display("PASS: STORE hit no detiene el pipeline");
        $display("PASS: STORE hit fue aceptado una sola vez");
        $display("----------------------------------------------");
        $display("PRUEBA STORE + CACHE STALL SUPERADA");
        $display("STORE aceptados: %0d", accepted_stores);
        $display("Stall observado: %0d ciclos", observed_stall_cycles);
        $display("----------------------------------------------");

        $finish;
    end

    initial begin
        #2500;
        $fatal(1, "ERROR: tiempo de espera agotado");
    end

endmodule

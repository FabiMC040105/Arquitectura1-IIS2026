`timescale 1ns/1ps

module tb_cache_stall_pipeline;

    logic clk_i = 1'b0;
    logic rst_i;
    logic stall_i;

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
    integer writes_x2 = 0;
    integer writes_x3 = 0;
    integer writes_x6 = 0;
    integer observed_stall_cycles = 0;

    logic [31:0] pc_hold;
    logic [159:0] if_id_hold;
    logic [166:0] id_rr_hold;
    logic [478:0] rr_ex_hold;
    logic [182:0] ex_wb_hold;
    logic [31:0] pc_before_hit;

    // -----------------------------------------------------------------
    // DUT: se habilita la interfaz de cache del Proyecto 2.
    // -----------------------------------------------------------------
    top #(
        .IMEM_WORDS(256),
        .PROGRAM_FILE("program_test.mem"),
        .CACHE_IF_EN(1'b1)
    ) dut (
        .clk_i(clk_i),
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

    // LOAD rd, offset(base)
    function automatic [31:0] lsu_load(
        input [11:0] offset,
        input [3:0]  base,
        input [3:0]  rd
    );
        lsu_load = {
            10'b0,
            offset,
            base,
            rd,
            2'b01
        };
    endfunction

    // Contadores de escrituras efectivas al register file.
    always @(posedge clk_i) begin
        if (!rst_i) begin
            if (global_stall_o)
                observed_stall_cycles = observed_stall_cycles + 1;

            if (dut.regfile_wr_en[0] && dut.regfile_wr_addr[0] == 4'd2)
                writes_x2 = writes_x2 + 1;

            if (dut.regfile_wr_en[1] && dut.regfile_wr_addr[1] == 4'd3)
                writes_x3 = writes_x3 + 1;

            if (dut.regfile_wr_en[1] && dut.regfile_wr_addr[1] == 4'd6)
                writes_x6 = writes_x6 + 1;
        end
    end

    initial begin
        $dumpfile("cache_stall_pipeline.vcd");
        $dumpvars(0, tb_cache_stall_pipeline);

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
        //   ALU: ADDI x2, x0, 9
        //   LSU: LOAD x3, 0(x0)
        // El LOAD sufrira un miss simulado. El ALU del MISMO bundle
        // tampoco puede avanzar mientras la cache mantiene el stall.
        dut.fetch_inst.instruction_memory_inst.memory[0] = {
            64'b0,
            lsu_load(12'd0, 4'd0, 4'd3),
            alu_addi(12'd9, 4'd0, 4'd2)
        };

        // Segundo LOAD independiente. Se respondera como hit.
        dut.fetch_inst.instruction_memory_inst.memory[8] = {
            64'b0,
            lsu_load(12'd4, 4'd0, 4'd6),
            32'b0
        };

        // Liberar reset.
        @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        // =============================================================
        // PRUEBA 1: MISS SIMULADO -> STALL DEL BUNDLE COMPLETO
        // =============================================================

        timeout = 0;
        while (!(cache_read_o === 1'b1 && cache_addr_o === 32'h00000000) &&
               timeout < 30) begin
            @(posedge clk_i);
            #1;
            timeout = timeout + 1;
        end

        if (timeout >= 30)
            $fatal(1, "ERROR: no aparecio la primera solicitud LOAD hacia cache");

        $display("Solicitud LOAD observada en direccion 0x%08h", cache_addr_o);

        // La cache informa miss/backpressure antes del siguiente flanco.
        @(negedge clk_i);
        cache_stall_i = 1'b1;
        cache_ready_i = 1'b0;

        // Capturar TODO el estado de los registros de pipeline.
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
                $fatal(1, "ERROR: PC avanzo durante cache stall");

            if (dut.if_id_data_out !== if_id_hold)
                $fatal(1, "ERROR: IF/ID cambio durante cache stall");

            if (dut.id_rr_data_out !== id_rr_hold)
                $fatal(1, "ERROR: ID/RR cambio durante cache stall");

            if (dut.rr_ex_data_out !== rr_ex_hold)
                $fatal(1, "ERROR: RR/EX cambio durante cache stall");

            if (dut.ex_wb_data_out !== ex_wb_hold)
                $fatal(1, "ERROR: EX/WB cambio durante cache stall");

            if (cache_read_o !== 1'b1)
                $fatal(1, "ERROR: la solicitud LOAD desaparecio durante cache stall");

            if (cache_addr_o !== 32'h00000000)
                $fatal(1, "ERROR: la direccion de cache cambio durante el stall");

            // Ni LSU ni ALU del mismo bundle deben haber escrito aun.
            if (writes_x2 !== 0 || writes_x3 !== 0)
                $fatal(1,
                    "ERROR: hubo escritura durante cache stall (x2=%0d x3=%0d)",
                    writes_x2, writes_x3);

            if (dut.regfile_inst.regs[2] !== 32'd0 ||
                dut.regfile_inst.regs[3] !== 32'd0)
                $fatal(1, "ERROR: el bundle avanzo parcialmente durante el miss");
        end

        $display("PASS: cache stall congela PC e IF/ID, ID/RR, RR/EX y EX/WB");
        $display("PASS: LOAD mantiene solicitud y direccion estables durante el miss");
        $display("PASS: el slot ALU del mismo bundle tampoco avanza");

        // Respuesta de la cache.
        @(negedge clk_i);
        cache_read_data_i = 32'h11223344;
        cache_ready_i = 1'b1;
        cache_stall_i = 1'b0;

        @(posedge clk_i);
        #1;

        if (global_stall_o !== 1'b0)
            $fatal(1, "ERROR: global_stall no se libero al responder la cache");

        // ready solo se mantiene durante la transferencia.
        @(negedge clk_i);
        cache_ready_i = 1'b0;

        // Esperar las escrituras de ALU y LSU.
        timeout = 0;
        while ((writes_x2 < 1 || writes_x3 < 1) && timeout < 12) begin
            @(posedge clk_i);
            #1;
            timeout = timeout + 1;
        end

        if (timeout >= 12)
            $fatal(1, "ERROR: timeout esperando resultados despues del cache miss");

        if (dut.regfile_inst.regs[2] !== 32'd9)
            $fatal(1, "ERROR: ALU del bundle no escribio x2=9");

        if (dut.regfile_inst.regs[3] !== 32'h11223344)
            $fatal(1, "ERROR: LOAD no escribio el dato devuelto por cache");

        if (writes_x2 !== 1 || writes_x3 !== 1)
            $fatal(1,
                "ERROR: operaciones ejecutadas mas de una vez (x2=%0d x3=%0d)",
                writes_x2, writes_x3);

        $display("PASS: bundle reanuda y ALU/LOAD escriben exactamente una vez");
        $display("PASS: LOAD recibio 0x11223344 desde la interfaz de cache");

        // =============================================================
        // PRUEBA 2: HIT SIMULADO -> SIN STALL
        // =============================================================

        timeout = 0;
        while (!(cache_read_o === 1'b1 && cache_addr_o === 32'h00000004) &&
               timeout < 30) begin
            @(posedge clk_i);
            #1;
            timeout = timeout + 1;
        end

        if (timeout >= 30)
            $fatal(1, "ERROR: no aparecio la segunda solicitud LOAD");

        if (global_stall_o !== 1'b0)
            $fatal(1, "ERROR: se genero stall antes de responder el hit");

        // Hit: respuesta disponible sin activar cache_stall_i.
        @(negedge clk_i);
        pc_before_hit = pc_o;
        cache_read_data_i = 32'h55667788;
        cache_ready_i = 1'b1;
        cache_stall_i = 1'b0;

        @(posedge clk_i);
        #1;

        if (global_stall_o !== 1'b0)
            $fatal(1, "ERROR: un hit genero global_stall");

        if (pc_o !== pc_before_hit + 32'd16)
            $fatal(1, "ERROR: PC no avanzo normalmente durante hit");

        @(negedge clk_i);
        cache_ready_i = 1'b0;

        timeout = 0;
        while (writes_x6 < 1 && timeout < 10) begin
            @(posedge clk_i);
            #1;
            timeout = timeout + 1;
        end

        if (timeout >= 10)
            $fatal(1, "ERROR: timeout esperando LOAD atendido como hit");

        if (dut.regfile_inst.regs[6] !== 32'h55667788)
            $fatal(1, "ERROR: hit no escribio 0x55667788 en x6");

        if (writes_x6 !== 1)
            $fatal(1, "ERROR: LOAD hit escribio %0d veces", writes_x6);

        $display("PASS: hit de cache no detiene el pipeline");
        $display("PASS: LOAD hit escribio x6=0x55667788 una sola vez");

        // Verificacion final: ninguna escritura debe repetirse.
        repeat (4) @(posedge clk_i);
        #1;

        if (writes_x2 !== 1 || writes_x3 !== 1 || writes_x6 !== 1)
            $fatal(1,
                "ERROR: se repitieron escrituras (x2=%0d x3=%0d x6=%0d)",
                writes_x2, writes_x3, writes_x6);

        if (observed_stall_cycles !== 3)
            $fatal(1,
                "ERROR: se observaron %0d ciclos de stall, se esperaban 3",
                observed_stall_cycles);

        $display("----------------------------------------------");
        $display("PRUEBA PIPELINE + CACHE STALL SUPERADA");
        $display("Stall observado: %0d ciclos", observed_stall_cycles);
        $display("----------------------------------------------");

        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "ERROR: tiempo de espera agotado");
    end

endmodule

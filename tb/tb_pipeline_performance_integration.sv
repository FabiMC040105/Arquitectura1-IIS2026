`timescale 1ns/1ps

module tb_pipeline_performance_integration;

    logic clk_i = 1'b0;
    logic rst_i;
    logic stall_i;

    wire clk_mem_i = clk_i;

    logic        cache_ready_i;
    logic        cache_stall_i;
    logic [31:0] cache_read_data_i;

    wire         cache_read_o;
    wire         cache_write_o;
    wire [31:0]  cache_addr_o;
    wire [31:0]  cache_write_data_o;
    wire         global_stall_o;

    wire [63:0] perf_cycles_o;
    wire [63:0] perf_bundles_o;
    wire [63:0] perf_instructions_o;

    wire [31:0]  pc_o;
    wire [127:0] bundle_o;
    wire         fetch_valid_o;

    integer i;
    integer timeout;

    logic [63:0] cycles_before_stall;
    logic [63:0] bundles_before_stall;
    logic [63:0] instructions_before_stall;

    top #(
        .IMEM_WORDS(1024),
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

        .perf_cycles_o(perf_cycles_o),
        .perf_bundles_o(perf_bundles_o),
        .perf_instructions_o(perf_instructions_o),

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

    initial begin
        $dumpfile("pipeline_performance_integration.vcd");
        $dumpvars(0, tb_pipeline_performance_integration);

        rst_i = 1'b1;
        stall_i = 1'b0;

        cache_ready_i = 1'b0;
        cache_stall_i = 1'b0;
        cache_read_data_i = 32'h11223344;

        #1;

        // Limpiar una parte suficiente de la memoria de instrucciones.
        for (i = 0; i < 16; i = i + 1)
            dut.fetch_inst.instruction_memory_inst.memory[i] = 128'b0;

        // Bundle 0: dos instrucciones activas.
        // ALU: ADDI x2, x0, 9
        // LSU: LOAD x3, 0(x0)
        dut.fetch_inst.instruction_memory_inst.memory[0] = {
            64'b0,
            lsu_load(12'd0, 4'd0, 4'd3),
            alu_addi(12'd9, 4'd0, 4'd2)
        };

        // Liberar reset.
        @(posedge clk_i);
        @(negedge clk_i);
        rst_i = 1'b0;

        // Esperar a que el LOAD llegue a la interfaz de cache.
        timeout = 0;
        while (!(cache_read_o === 1'b1 &&
                 cache_addr_o === 32'h00000000) &&
               timeout < 30) begin
            @(posedge clk_i);
            #1;
            timeout = timeout + 1;
        end

        if (timeout >= 30)
            $fatal(1, "ERROR: no aparecio la solicitud LOAD");

        $display("LOAD observado. Iniciando stall de cache.");

        // Aplicar un miss/backpressure de exactamente tres ciclos.
        @(negedge clk_i);

        cycles_before_stall       = perf_cycles_o;
        bundles_before_stall      = perf_bundles_o;
        instructions_before_stall = perf_instructions_o;

        cache_stall_i = 1'b1;
        cache_ready_i = 1'b0;

        repeat (3) begin
            @(posedge clk_i);
            #1;

            if (global_stall_o !== 1'b1)
                $fatal(1, "ERROR: cache stall no genero global_stall");

            // Los ciclos SI deben seguir contando.
            if (perf_cycles_o <= cycles_before_stall)
                $fatal(1, "ERROR: contador de ciclos no avanzo durante stall");

            // Pero un bundle congelado NO puede retirarse ni volver a contarse.
            if (perf_bundles_o !== bundles_before_stall)
                $fatal(1,
                    "ERROR: bundles cambiaron durante stall: antes=%0d ahora=%0d",
                    bundles_before_stall,
                    perf_bundles_o);

            if (perf_instructions_o !== instructions_before_stall)
                $fatal(1,
                    "ERROR: instrucciones cambiaron durante stall: antes=%0d ahora=%0d",
                    instructions_before_stall,
                    perf_instructions_o);
        end

        if (perf_cycles_o !== cycles_before_stall + 64'd3)
            $fatal(1,
                "ERROR: stall de 3 ciclos incremento cycles en %0d",
                perf_cycles_o - cycles_before_stall);

        $display("PASS: los 3 ciclos de stall se contaron como ciclos");
        $display("PASS: stall no duplico bundles ni instrucciones");

        // Liberar la cache y entregar el dato del LOAD.
        @(negedge clk_i);
        cache_stall_i = 1'b0;
        cache_ready_i = 1'b1;
        cache_read_data_i = 32'h11223344;

        @(posedge clk_i);
        #1;

        if (global_stall_o !== 1'b0)
            $fatal(1, "ERROR: global_stall no se libero");

        // La respuesta solo se considera lista en este ciclo.
        @(negedge clk_i);
        cache_ready_i = 1'b0;

        // Esperar a que el bundle llegue a WB y sea retirado.
        timeout = 0;
        while (perf_bundles_o == bundles_before_stall &&
               timeout < 12) begin
            @(posedge clk_i);
            #1;
            timeout = timeout + 1;
        end

        if (timeout >= 12)
            $fatal(1, "ERROR: el bundle nunca fue contado como retirado");

        // Debe retirarse exactamente un bundle.
        if (perf_bundles_o !== bundles_before_stall + 64'd1)
            $fatal(1,
                "ERROR: bundles retirados delta=%0d, esperado 1",
                perf_bundles_o - bundles_before_stall);

        // Ese bundle tenia exactamente dos slots activos: ALU + LSU.
        if (perf_instructions_o !== instructions_before_stall + 64'd2)
            $fatal(1,
                "ERROR: instrucciones retiradas delta=%0d, esperado 2",
                perf_instructions_o - instructions_before_stall);

        if (dut.regfile_inst.regs[2] !== 32'd9)
            $fatal(1, "ERROR: ALU no escribio x2=9");

        if (dut.regfile_inst.regs[3] !== 32'h11223344)
            $fatal(1,
                "ERROR: LOAD no escribio x3=0x11223344, valor=%h",
                dut.regfile_inst.regs[3]);

        $display("PASS: se retiro exactamente 1 bundle despues del stall");
        $display("PASS: el bundle conto exactamente 2 instrucciones");
        $display("PASS: ALU y LOAD produjeron sus resultados correctos");

        $display("----------------------------------------------");
        $display("PRUEBA CONTADORES + PIPELINE STALL SUPERADA");
        $display("Ciclos antes del stall : %0d", cycles_before_stall);
        $display("Ciclos despues stall   : %0d", cycles_before_stall + 3);
        $display("Bundles retirados      : +1");
        $display("Instrucciones retiradas: +2");
        $display("----------------------------------------------");

        $finish;
    end

    initial begin
        #2500;
        $fatal(1, "ERROR: tiempo de espera agotado");
    end

endmodule

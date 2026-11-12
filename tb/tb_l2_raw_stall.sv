`timescale 1ns/1ps

module tb_l2_raw_stall;
    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic l2_req_valid = 0;
    wire l2_req_ready;
    logic [31:0] l2_req_addr = 0;
    wire l2_resp_valid;
    wire [255:0] l2_resp_data;
    logic l2_write_valid = 0;
    wire l2_write_ready;
    logic [31:0] l2_write_addr = 0;
    logic [31:0] l2_write_data = 0;

    wire mem_req_valid, mem_req_write;
    logic mem_req_ready = 1;
    wire [31:0] mem_req_addr;
    wire [255:0] mem_req_wdata;
    logic mem_resp_valid = 0;
    logic [255:0] mem_resp_data = 0;
    wire [31:0] read_hits, read_misses, write_hits, write_misses;
    wire [3:0] eviction_count;

    localparam [31:0] TEST_ADDR = 32'h00001000;
    localparam [255:0] OLD_LINE = {8{32'h11111111}};
    localparam [255:0] NEW_LINE = {8{32'hCAFEBABE}};

    integer errors = 0;
    integer memory_reads = 0;
    integer memory_writes = 0;
    integer delay_count = 0;
    integer timeout;
    logic memory_busy = 0;
    logic captured_write = 0;
    logic [31:0] captured_addr = 0;
    logic [255:0] captured_data = 0;
    logic write_finished = 0;
    logic premature_read = 0;
    logic response_seen = 0;
    logic raw_seen = 0;

    // Modelo de RAM con contenido inicial ANTIGUO.
    logic [255:0] ram [0:2047];
    integer i;
    initial begin
        for (i = 0; i < 2048; i = i + 1)
            ram[i] = {8{32'h00000000}};
        ram[TEST_ADDR[15:5]] = OLD_LINE;
    end

    l2_data_system dut (
        .clk(clk), .rst(rst),
        .l2_req_valid(l2_req_valid), .l2_req_ready(l2_req_ready),
        .l2_req_addr(l2_req_addr),
        .l2_resp_valid(l2_resp_valid), .l2_resp_data(l2_resp_data),
        .l2_write_valid(l2_write_valid), .l2_write_ready(l2_write_ready),
        .l2_write_addr(l2_write_addr), .l2_write_data(l2_write_data),
        .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
        .mem_req_write(mem_req_write), .mem_req_addr(mem_req_addr),
        .mem_req_wdata(mem_req_wdata),
        .mem_resp_valid(mem_resp_valid), .mem_resp_data(mem_resp_data),
        .read_hits(read_hits), .read_misses(read_misses),
        .write_hits(write_hits), .write_misses(write_misses),
        .eviction_count(eviction_count)
    );

    task automatic check(input logic condition, input string message);
        begin
            if (condition === 1'b1)
                $display("PASS: %s", message);
            else begin
                $display("FAIL: %s", message);
                errors = errors + 1;
            end
        end
    endtask

    // Memoria: tarda 25 ciclos para completar una escritura.
    // Solo una solicitud activa; la respuesta confirma FINALIZACION.
    always @(posedge clk) begin
        if (rst) begin
            memory_busy <= 0;
            mem_resp_valid <= 0;
            mem_resp_data <= 0;
            memory_reads <= 0;
            memory_writes <= 0;
            write_finished <= 0;
            premature_read <= 0;
            delay_count <= 0;
        end else begin
            mem_resp_valid <= 0;
            if (!memory_busy && mem_req_valid && mem_req_ready) begin
                captured_write <= mem_req_write;
                captured_addr <= mem_req_addr;
                captured_data <= mem_req_wdata;
                memory_busy <= 1;
                delay_count <= mem_req_write ? 25 : 4;
                if (mem_req_write) begin
                    memory_writes <= memory_writes + 1;
                    $display("RAM: recibio write-back a %h", mem_req_addr);
                end else begin
                    memory_reads <= memory_reads + 1;
                    if (mem_req_addr == TEST_ADDR && !write_finished)
                        premature_read <= 1;
                    $display("RAM: recibio refill a %h", mem_req_addr);
                end
            end else if (memory_busy) begin
                if (delay_count > 0)
                    delay_count <= delay_count - 1;
                else begin
                    if (captured_write) begin
                        ram[captured_addr[15:5]] <= captured_data;
                        mem_resp_data <= 0;
                        write_finished <= 1;
                        $display("RAM: write-back completado");
                    end else
                        mem_resp_data <= ram[captured_addr[15:5]];
                    mem_resp_valid <= 1;
                    memory_busy <= 0;
                end
            end
        end
    end

    initial begin
        $dumpfile("l2_raw_stall.vcd");
        $dumpvars(0, tb_l2_raw_stall);
        repeat (3) @(negedge clk);
        rst = 0;
        $display("--- PRUEBA RAW: write-back pendiente y lectura misma linea ---");
        check(ram[TEST_ADDR[15:5]] === OLD_LINE,
              "RAM comienza con contenido antiguo");

        // Preparar el conflicto de forma controlada: inyectar una
        // linea dirty en la FIFO SIN modificar el hardware de produccion.
        // La caché L2 comienza vacia, para forzar posteriormente un miss.
        @(negedge clk);
        force dut.evict_valid = 1'b1;
        force dut.evict_addr = 32'h00001000;
        force dut.evict_data = {8{32'hCAFEBABE}};
        #1;
        check(dut.evict_ready, "FIFO acepta la linea dirty de prueba");
        @(posedge clk);
        #1;
        release dut.evict_valid;
        release dut.evict_addr;
        release dut.evict_data;
        check(eviction_count == 1, "Linea dirty almacenada en FIFO");

        // Esperar hasta que RAM haya aceptado el write-back pero
        // antes de que lo complete (demora deliberada de 25 ciclos).
        timeout = 0;
        while (memory_writes == 0 && timeout < 30) begin
            @(negedge clk);
            timeout = timeout + 1;
        end
        if (memory_writes != 1)
            $fatal(1, "No se acepto la escritura pendiente");
        check(!write_finished, "Escritura aun pendiente en RAM");

        // Solicitar desde L1 la misma linea, ausente de la caché L2.
        @(negedge clk);
        check(l2_req_ready, "L2 disponible para solicitar lectura");
        l2_req_addr = TEST_ADDR;
        l2_req_valid = 1;
        @(negedge clk);
        l2_req_valid = 0;

        timeout = 0;
        while (!l2_resp_valid && timeout < 200) begin
            @(negedge clk);
            if (dut.raw_conflict === 1'b1) raw_seen = 1;
            timeout = timeout + 1;
        end
        check(timeout < 200, "Lectura finaliza sin bloqueo indefinido");
        check(raw_seen, "Se detecta RAW mientras la linea sigue pendiente");
        check(!premature_read, "No se lee RAM antes de completar write-back");
        check(write_finished, "La escritura termina antes del refill");
        check(l2_resp_valid && l2_resp_data === NEW_LINE,
              "L2 devuelve el dato nuevo, no el antiguo");
        check(memory_writes == 1, "Exactamente un write-back a RAM");
        check(memory_reads == 1, "Exactamente un refill desde RAM");
        check(eviction_count == 0, "FIFO drenada despues del write-back");

        if (errors == 0)
            $display("TODAS LAS PRUEBAS PASARON");
        else
            $fatal(1, "FALLARON %0d PRUEBAS", errors);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "Timeout global RAW");
    end
endmodule

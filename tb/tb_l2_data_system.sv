`timescale 1ns/1ps

module tb_l2_data_system;
    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic l2_req_valid = 0, l2_req_ready;
    logic [31:0] l2_req_addr = 0;
    logic l2_resp_valid;
    logic [255:0] l2_resp_data;
    logic l2_write_valid = 0, l2_write_ready;
    logic [31:0] l2_write_addr = 0, l2_write_data = 0;

    logic mem_req_valid, mem_req_ready = 1, mem_req_write;
    logic [31:0] mem_req_addr;
    logic [255:0] mem_req_wdata;
    logic mem_resp_valid = 0;
    logic [255:0] mem_resp_data = 0;
    logic [31:0] read_hits, read_misses, write_hits, write_misses;
    logic [3:0] eviction_count;

    integer errors = 0;
    integer memory_reads = 0;
    integer memory_writes = 0;
    logic [31:0] evicted_address = 0;
    logic [255:0] evicted_data = 0;

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

    function automatic [255:0] initial_line(input logic [31:0] addr);
        logic [255:0] result;
        logic [31:0] aligned;
        integer j;
        begin
            aligned = {addr[31:5], 5'b0};
            result = 0;
            for (j=0; j<8; j=j+1)
                result[j*32 +: 32] = 32'hA0000000 + aligned + j;
            initial_line = result;
        end
    endfunction

    // 64 KB, 2048 lineas de 32 bytes. Este modelo RESPONDE a escrituras.
    logic [255:0] ram [0:2047];
    integer j;
    initial begin
        for (j=0; j<2048; j=j+1)
            ram[j] = initial_line(j*32);
    end

    logic mem_busy = 0;
    logic captured_write = 0;
    logic [31:0] captured_addr = 0;
    logic [255:0] captured_data = 0;
    integer delay_count = 0;

    // Una operacion activa; respuesta despues de 5 ciclos de prueba.
    always @(posedge clk) begin
        if (rst) begin
            mem_busy <= 0;
            mem_resp_valid <= 0;
            delay_count <= 0;
            memory_reads <= 0;
            memory_writes <= 0;
            evicted_address <= 0;
            evicted_data <= 0;
        end else begin
            mem_resp_valid <= 0;
            if (!mem_busy && mem_req_valid && mem_req_ready) begin
                captured_write <= mem_req_write;
                captured_addr <= mem_req_addr;
                captured_data <= mem_req_wdata;
                mem_busy <= 1;
                delay_count <= 4;
                if (mem_req_write) begin
                    memory_writes <= memory_writes + 1;
                    evicted_address <= mem_req_addr;
                    evicted_data <= mem_req_wdata;
                end else begin
                    memory_reads <= memory_reads + 1;
                end
            end else if (mem_busy) begin
                if (delay_count != 0) delay_count <= delay_count - 1;
                else begin
                    if (captured_write) begin
                        ram[captured_addr[15:5]] <= captured_data;
                        mem_resp_data <= 0;
                    end else begin
                        mem_resp_data <= ram[captured_addr[15:5]];
                    end
                    mem_resp_valid <= 1;
                    mem_busy <= 0;
                end
            end
        end
    end

    task automatic check(input logic condition, input string message);
        begin
            if (condition === 1'b1) $display("PASS: %s",message);
            else begin
                $display("FAIL: %s",message);
                errors = errors + 1;
            end
        end
    endtask

    task automatic read_line(input logic [31:0] addr,
                             input logic [255:0] expected);
        integer timeout;
        logic got;
        begin
            @(negedge clk);
            timeout=0;
            while (l2_req_ready !== 1'b1 && timeout<200) begin
                @(negedge clk);
                timeout=timeout+1;
            end
            if (timeout==200) $fatal(1,"Timeout: ready lectura");
            l2_req_addr=addr;
            l2_req_valid=1;
            @(negedge clk);
            l2_req_valid=0;
            timeout=0;
            got=0;
            while (!got && timeout<400) begin
                @(negedge clk);
                if (l2_resp_valid) begin
                    got=1;
                    check(l2_resp_data === expected, "Lectura devuelve linea correcta");
                end
                timeout=timeout+1;
            end
            if (!got) $fatal(1,"Timeout: respuesta lectura %h",addr);
        end
    endtask

    task automatic write_word(input logic [31:0] addr,
                              input logic [31:0] data);
        integer timeout;
        begin
            @(negedge clk);
            timeout=0;
            while (l2_write_ready !== 1'b1 && timeout<200) begin
                @(negedge clk);
                timeout=timeout+1;
            end
            if (timeout==200) $fatal(1,"Timeout: ready escritura");
            l2_write_addr=addr;
            l2_write_data=data;
            l2_write_valid=1;
            @(negedge clk);
            l2_write_valid=0;
            timeout=0;
            while (l2_write_ready !== 1'b1 && timeout<400) begin
                @(negedge clk);
                timeout=timeout+1;
            end
            if (timeout==400) $fatal(1,"Timeout: escritura");
        end
    endtask

    logic [255:0] expected;
    integer k;
    initial begin
        $dumpfile("l2_data_system.vcd");
        $dumpvars(0,tb_l2_data_system);
        repeat (3) @(negedge clk);
        rst=0;
        $display("--- Integracion L2 + eviction buffer ---");

        // Cuatro direcciones que caen en el set 0.
        // Se instalan y luego se modifican para volverlas dirty.
        for (k=0; k<4; k=k+1) begin
            read_line(k*32'h1000, initial_line(k*32'h1000));
            write_word(k*32'h1000 + 4, 32'hD0000000 + k);
            expected=initial_line(k*32'h1000);
            expected[63:32]=32'hD0000000 + k;
            read_line(k*32'h1000, expected);
        end
        check(memory_reads == 4,"Cuatro refills iniciales");
        check(memory_writes == 0,"Sin evictions antes de llenar el set");

        // Quinto acceso: reemplaza una linea dirty y la drena a RAM.
        read_line(32'h4000, initial_line(32'h4000));
        check(memory_reads == 5,"Quinta linea recuperada");
        check(memory_writes == 1,"Un eviction write-back enviado a RAM");
        check(evicted_address == 32'h0000 ||
              evicted_address == 32'h1000 ||
              evicted_address == 32'h2000 ||
              evicted_address == 32'h3000,
              "La victima pertenece al set lleno");
        expected=initial_line(evicted_address);
        expected[63:32]=32'hD0000000 + (evicted_address >> 12);
        check(evicted_data === expected,"Write-back conserva datos dirty");
        check(eviction_count == 0,"FIFO drenada tras confirmacion");

        // Leer la victima de nuevo: debe obtener la version modificada de RAM.
        read_line(evicted_address,expected);
        check(memory_reads == 6,"La victima desalojada se recupera de RAM");

        if (errors == 0) $display("TODAS LAS PRUEBAS PASARON");
        else $fatal(1,"FALLARON %0d PRUEBAS",errors);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1,"Timeout global");
    end
endmodule

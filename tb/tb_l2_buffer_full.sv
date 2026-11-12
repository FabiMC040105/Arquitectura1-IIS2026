`timescale 1ns/1ps

// Prueba de estres: L2 debe conservar una victima dirty cuando el
// eviction buffer de 8 entradas esta lleno. Para preparar el escenario,
// se precarga la FIFO por acceso jerarquico SOLO desde el testbench.
module tb_l2_buffer_full;
    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic l2_req_valid = 0, l2_req_ready;
    logic [31:0] l2_req_addr = 0;
    logic l2_resp_valid;
    logic [255:0] l2_resp_data;
    logic l2_write_valid = 0, l2_write_ready;
    logic [31:0] l2_write_addr = 0, l2_write_data = 0;

    logic mem_req_valid, mem_req_ready, mem_req_write;
    logic [31:0] mem_req_addr;
    logic [255:0] mem_req_wdata;
    logic mem_resp_valid = 0;
    logic [255:0] mem_resp_data = 0;
    logic [31:0] read_hits, read_misses, write_hits, write_misses;
    logic [3:0] eviction_count;

    integer errors = 0;
    integer memory_reads = 0;
    integer memory_writes = 0;
    integer i;
    logic allow_mem = 1;
    logic mem_busy = 0;
    logic captured_write = 0;
    logic [31:0] captured_addr = 0;
    logic [255:0] captured_data = 0;
    integer delay_count = 0;
    logic [255:0] ram [0:2047];

    logic [31:0] victim_addr_saved;
    logic [255:0] victim_data_saved;
    logic [255:0] expected;
    logic got;
    integer timeout;

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

    function automatic [255:0] initial_line(input logic [31:0] address);
        logic [255:0] line;
        logic [31:0] base;
        integer j;
        begin
            base = {address[31:5], 5'b0};
            line = 0;
            for (j=0; j<8; j=j+1)
                line[j*32 +: 32] = 32'hA0000000 + base + j;
            initial_line = line;
        end
    endfunction

    initial begin
        for (integer n=0; n<2048; n=n+1)
            ram[n] = initial_line(n*32);
    end

    // Un solo puerto de memoria, con backpressure controlado por allow_mem.
    assign mem_req_ready = allow_mem && !mem_busy;

    always @(posedge clk) begin
        if (rst) begin
            mem_busy <= 0;
            mem_resp_valid <= 0;
            mem_resp_data <= 0;
            memory_reads <= 0;
            memory_writes <= 0;
            delay_count <= 0;
        end else begin
            mem_resp_valid <= 0;
            if (!mem_busy && mem_req_valid && mem_req_ready) begin
                captured_write <= mem_req_write;
                captured_addr <= mem_req_addr;
                captured_data <= mem_req_wdata;
                mem_busy <= 1;
                delay_count <= 3;
                if (mem_req_write)
                    memory_writes <= memory_writes + 1;
                else
                    memory_reads <= memory_reads + 1;
            end else if (mem_busy) begin
                if (delay_count > 0)
                    delay_count <= delay_count - 1;
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
            if (condition === 1'b1)
                $display("PASS: %s", message);
            else begin
                $display("FAIL: %s", message);
                errors = errors + 1;
            end
        end
    endtask

    task automatic read_line(input logic [31:0] address,
                             input logic [255:0] value);
        integer t;
        logic received;
        begin
            t=0; received=0;
            @(negedge clk);
            while (l2_req_ready !== 1'b1 && t<400) begin
                @(negedge clk); t=t+1;
            end
            if (t==400) $fatal(1,"Timeout: L2 no acepta lectura");
            l2_req_addr=address;
            l2_req_valid=1;
            @(negedge clk);
            l2_req_valid=0;
            t=0;
            while (!received && t<1200) begin
                @(negedge clk);
                if (l2_resp_valid) begin
                    received=1;
                    check(l2_resp_data === value,
                          "Lectura de L2 devuelve linea correcta");
                end
                t=t+1;
            end
            if (!received) $fatal(1,"Timeout: respuesta de lectura %h",address);
        end
    endtask

    task automatic write_word(input logic [31:0] address,
                              input logic [31:0] value);
        integer t;
        begin
            t=0;
            @(negedge clk);
            while (l2_write_ready !== 1'b1 && t<400) begin
                @(negedge clk); t=t+1;
            end
            if (t==400) $fatal(1,"Timeout: L2 no acepta escritura");
            l2_write_addr=address;
            l2_write_data=value;
            l2_write_valid=1;
            @(negedge clk);
            l2_write_valid=0;
            t=0;
            while (l2_write_ready !== 1'b1 && t<1200) begin
                @(negedge clk); t=t+1;
            end
            if (t==1200) $fatal(1,"Timeout: escritura L2");
        end
    endtask

    initial begin
        $dumpfile("l2_buffer_full.vcd");
        $dumpvars(0,tb_l2_buffer_full);
        repeat (3) @(negedge clk);
        rst=0;
        $display("--- Preparar cuatro vias dirty del set 0 ---");
        for (i=0; i<4; i=i+1) begin
            read_line(i*32'h1000, initial_line(i*32'h1000));
            write_word(i*32'h1000 + 4, 32'hD0000000 + i);
            expected=initial_line(i*32'h1000);
            expected[63:32]=32'hD0000000 + i;
            read_line(i*32'h1000,expected);
        end
        check(memory_reads == 4, "Cuatro refills iniciales");
        check(memory_writes == 0, "Aun no hay desalojos");

        // Preparacion artificial: 8 lineas pendientes sin usar el
        // handshake normal. SOLO para probar backpressure del sistema.
        @(negedge clk);
        allow_mem=0;
        for (i=0; i<8; i=i+1) begin
            dut.eviction_fifo.addr_fifo[i] = 32'h00008000 + i*32;
            dut.eviction_fifo.data_fifo[i] = initial_line(32'h00008000 + i*32);
        end
        dut.eviction_fifo.wr_ptr = 0;
        dut.eviction_fifo.rd_ptr = 0;
        dut.eviction_fifo.count = 8;
        #1;
        check(eviction_count == 8 && dut.fifo_full,
              "Eviction buffer realmente lleno (8/8)");
        check(!dut.evict_ready, "Eviction buffer rechaza nueva linea");

        $display("--- Quinto acceso con FIFO llena y RAM bloqueada ---");
        @(negedge clk);
        l2_req_addr = 32'h00004000;
        l2_req_valid = 1;
        @(negedge clk);
        l2_req_valid = 0;

        timeout=0;
        while (dut.evict_valid !== 1'b1 && timeout<100) begin
            @(negedge clk); timeout=timeout+1;
        end
        if (timeout==100) $fatal(1,"L2 no llego a EVICT");
        #1;
        victim_addr_saved = dut.evict_addr;
        victim_data_saved = dut.evict_data;
        check(victim_addr_saved == 32'h0 || victim_addr_saved == 32'h1000 ||
              victim_addr_saved == 32'h2000 || victim_addr_saved == 32'h3000,
              "La victima pertenece al conjunto lleno");
        expected=initial_line(victim_addr_saved);
        expected[63:32]=32'hD0000000 + (victim_addr_saved >> 12);
        check(victim_data_saved === expected,
              "La victima dirty contiene la ultima escritura");

        for (i=0; i<5; i=i+1) begin
            @(negedge clk);
            check(dut.evict_valid && !dut.evict_ready,
                  "L2 permanece detenida por FIFO llena");
            check(dut.evict_addr === victim_addr_saved &&
                  dut.evict_data === victim_data_saved,
                  "Victima no cambia durante backpressure");
            check(memory_reads == 4 && eviction_count == 8 && !l2_resp_valid,
                  "Sin refill, perdida de datos ni respuesta prematura");
        end

        $display("--- Permitir drenado de RAM y continuacion ---");
        allow_mem=1;
        got=0;
        timeout=0;
        while (!got && timeout<1200) begin
            @(negedge clk);
            if (l2_resp_valid) begin
                got=1;
                check(l2_resp_data === initial_line(32'h4000),
                      "Quinta linea recuperada correctamente");
            end
            timeout=timeout+1;
        end
        check(got, "L2 reanuda tras liberar espacio");
        // Esperar el drenado del ultimo write-back, si sigue en curso.
        timeout=0;
        while (eviction_count != 0 && timeout<1200) begin
            @(negedge clk); timeout=timeout+1;
        end
        check(eviction_count == 0,"FIFO finalmente drenada");
        check(memory_writes == 9,
              "Ocho entradas iniciales mas la victima fueron escritas");
        check(memory_reads == 5,
              "Solo un refill adicional para quinta linea");
        check(ram[victim_addr_saved[15:5]] === victim_data_saved,
              "RAM conserva los 256 bits de la victima dirty");

        read_line(32'h4000, initial_line(32'h4000));
        check(memory_reads == 5,"Quinta linea queda en cache (hit)");

        if (errors == 0) $display("TODAS LAS PRUEBAS PASARON");
        else $fatal(1,"FALLARON %0d PRUEBAS",errors);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1,"Timeout global del testbench");
    end
endmodule

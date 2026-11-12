`timescale 1ns/1ps

module tb_l2_replacement;
    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic         l2_req_valid = 0;
    logic         l2_req_ready;
    logic [31:0]  l2_req_addr = 0;
    logic         l2_resp_valid;
    logic [255:0] l2_resp_data;
    logic         l2_write_valid = 0;
    logic         l2_write_ready;
    logic [31:0]  l2_write_addr = 0;
    logic [31:0]  l2_write_data = 0;
    logic         mem_req_valid;
    logic         mem_req_ready = 1;
    logic [31:0]  mem_req_addr;
    logic         mem_resp_valid = 0;
    logic [255:0] mem_resp_data = 0;
    logic         evict_valid;
    logic         evict_ready = 1;
    logic [31:0]  evict_addr;
    logic [255:0] evict_data;
    logic [31:0] read_hits, read_misses, write_hits, write_misses;

    integer errors = 0;
    integer mem_requests = 0;
    logic mem_pending = 0;
    integer mem_delay = 0;
    logic [31:0] saved_mem_addr = 0;
    logic [31:0] saved_victim_addr;
    logic [255:0] saved_victim_data;

    l2_controller dut (
        .clk(clk), .rst(rst),
        .l2_req_valid(l2_req_valid), .l2_req_ready(l2_req_ready),
        .l2_req_addr(l2_req_addr),
        .l2_resp_valid(l2_resp_valid), .l2_resp_data(l2_resp_data),
        .l2_write_valid(l2_write_valid), .l2_write_ready(l2_write_ready),
        .l2_write_addr(l2_write_addr), .l2_write_data(l2_write_data),
        .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
        .mem_req_addr(mem_req_addr),
        .mem_resp_valid(mem_resp_valid), .mem_resp_data(mem_resp_data),
        .evict_valid(evict_valid), .evict_ready(evict_ready),
        .evict_addr(evict_addr), .evict_data(evict_data),
        .read_hits(read_hits), .read_misses(read_misses),
        .write_hits(write_hits), .write_misses(write_misses)
    );

    function automatic [255:0] make_line(input logic [31:0] address);
        logic [255:0] result;
        logic [31:0] base_addr;
        integer j;
        begin
            base_addr = {address[31:5], 5'b0};
            result = 0;
            for (j=0; j<8; j=j+1)
                result[j*32 +: 32] = 32'hAB000000 + base_addr + j;
            make_line = result;
        end
    endfunction

    // Memoria simulada: tarda unos pocos ciclos en contestar.
    always @(posedge clk) begin
        if (rst) begin
            mem_resp_valid <= 0;
            mem_pending <= 0;
            mem_delay <= 0;
            mem_requests <= 0;
            saved_mem_addr <= 0;
        end else begin
            mem_resp_valid <= 0;
            if (mem_req_valid && mem_req_ready && !mem_pending) begin
                saved_mem_addr <= mem_req_addr;
                mem_pending <= 1;
                mem_delay <= 2;
                mem_requests <= mem_requests + 1;
            end else if (mem_pending) begin
                if (mem_delay != 0)
                    mem_delay <= mem_delay - 1;
                else begin
                    mem_resp_data <= make_line(saved_mem_addr);
                    mem_resp_valid <= 1;
                    mem_pending <= 0;
                end
            end
        end
    end

    task automatic check(input logic ok, input string msg);
        begin
            if (ok === 1'b1) $display("PASS: %s", msg);
            else begin
                $display("FAIL: %s", msg);
                errors = errors + 1;
            end
        end
    endtask

    task automatic read_line(input logic [31:0] address,
                             input logic [255:0] expected);
        integer cycles;
        logic received;
        begin
            cycles = 0;
            received = 0;
            @(negedge clk);
            while (!l2_req_ready && cycles < 200) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (cycles == 200) $fatal(1, "L2 no acepta lectura");
            l2_req_addr = address;
            l2_req_valid = 1;
            @(posedge clk);
            #1 l2_req_valid = 0;
            for (cycles=0; cycles<200 && !received; cycles=cycles+1) begin
                @(negedge clk);
                if (l2_resp_valid) begin
                    received = 1;
                    check(l2_resp_data === expected, "Linea leida correctamente");
                end
            end
            if (!received) $fatal(1, "Timeout de lectura");
        end
    endtask

    task automatic write_word(input logic [31:0] address,
                              input logic [31:0] data);
        integer cycles;
        begin
            cycles = 0;
            @(negedge clk);
            while (!l2_write_ready && cycles < 200) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (cycles == 200) $fatal(1, "L2 no acepta escritura");
            l2_write_addr = address;
            l2_write_data = data;
            l2_write_valid = 1;
            @(posedge clk);
            #1 l2_write_valid = 0;
            @(negedge clk);
            cycles = 0;
            while (!l2_write_ready && cycles < 200) begin
                @(negedge clk);
                cycles = cycles + 1;
            end
            if (cycles == 200) $fatal(1, "Timeout de escritura");
        end
    endtask

    initial begin
        integer j;
        integer start_requests;
        logic [255:0] expected;
        $dumpfile("l2_replacement.vcd");
        $dumpvars(0, tb_l2_replacement);
        repeat (3) @(negedge clk);
        rst = 0;

        $display("--- Llenar cuatro vias del mismo set ---");
        for (j=0; j<4; j=j+1) begin
            read_line(j * 32'h1000, make_line(j * 32'h1000));
            write_word(j * 32'h1000, 32'hDEAD0000 + j);
            expected = make_line(j * 32'h1000);
            expected[31:0] = 32'hDEAD0000 + j;
            read_line(j * 32'h1000, expected);
        end
        check(mem_requests == 4, "Cuatro misses iniciales a memoria");

        $display("--- Quinto acceso, eviction buffer ocupado ---");
        start_requests = mem_requests;
        evict_ready = 0;
        @(negedge clk);
        l2_req_addr = 32'h00004000; // Mismo set, diferente tag
        l2_req_valid = 1;
        @(posedge clk);
        #1 l2_req_valid = 0;

        wait (evict_valid === 1'b1);
        #1;
        saved_victim_addr = evict_addr;
        saved_victim_data = evict_data;
        check((saved_victim_addr == 32'h00000000 ||
               saved_victim_addr == 32'h00001000 ||
               saved_victim_addr == 32'h00002000 ||
               saved_victim_addr == 32'h00003000),
              "Victima pertenece al conjunto lleno");
        check(saved_victim_data[31:0] ===
              (32'hDEAD0000 + (saved_victim_addr >> 12)),
              "La victima contiene la escritura dirty");
        repeat (4) begin
            @(negedge clk);
            check(evict_valid && evict_addr === saved_victim_addr &&
                  evict_data === saved_victim_data,
                  "Victima estable durante backpressure");
            check(mem_requests == start_requests,
                  "No se solicita refill antes de aceptar eviction");
        end
        evict_ready = 1;

        // Esperar respuesta del miss y comprobar la nueva linea.
        begin : wait_response
            logic received;
            received = 0;
            for (j=0; j<200 && !received; j=j+1) begin
                @(negedge clk);
                if (l2_resp_valid) begin
                    received = 1;
                    check(l2_resp_data === make_line(32'h00004000),
                          "La quinta linea responde correctamente");
                end
            end
            if (!received) $fatal(1, "Timeout durante reemplazo");
        end
        check(mem_requests == start_requests + 1,
              "Solo un refill de memoria para la quinta linea");
        read_line(32'h00004000, make_line(32'h00004000));
        check(read_hits == 5, "La nueva linea produce hit");

        $display("--- RESULTADO ---");
        if (errors != 0) $fatal(1, "Fallaron %0d verificaciones", errors);
        $display("TODAS LAS PRUEBAS PASARON");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Timeout global");
    end
endmodule

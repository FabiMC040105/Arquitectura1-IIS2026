`timescale 1ns/1ps

module tb_l2_latency;
    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk; // 100 MHz

    logic l2_req_valid = 0;
    logic l2_req_ready;
    logic [31:0] l2_req_addr = 0;
    logic l2_resp_valid;
    logic [255:0] l2_resp_data;

    logic l2_write_valid = 0;
    logic l2_write_ready;
    logic [31:0] l2_write_addr = 0;
    logic [31:0] l2_write_data = 0;

    logic mem_req_valid;
    logic mem_req_ready = 1;
    logic [31:0] mem_req_addr;
    logic mem_resp_valid = 0;
    logic [255:0] mem_resp_data = 0;

    logic evict_valid;
    logic evict_ready = 1;
    logic [31:0] evict_addr;
    logic [255:0] evict_data;

    logic [31:0] read_hits, read_misses, write_hits, write_misses;

    integer cycles = 0;
    integer mem_requests = 0;
    integer errors = 0;
    integer responses = 0;
    logic mem_pending = 0;
    integer mem_delay = 0;

    localparam [31:0] TEST_ADDR = 32'h00000040;
    localparam [255:0] TEST_LINE = {
        32'h11111118, 32'h11111117, 32'h11111116, 32'h11111115,
        32'h11111114, 32'h11111113, 32'h11111112, 32'h11111111
    };

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

    // Contador de flancos para medir latencia en ciclos CPU.
    always @(posedge clk) begin
        if (rst) cycles <= 0;
        else cycles <= cycles + 1;
    end

    // Memoria de prueba: responde a una solicitud de refill.
    // No intenta modelar los 53 ciclos reales de memoria principal.
    always @(posedge clk) begin
        if (rst) begin
            mem_req_ready <= 1;
            mem_resp_valid <= 0;
            mem_resp_data <= 0;
            mem_pending <= 0;
            mem_delay <= 0;
            mem_requests <= 0;
        end else begin
            mem_resp_valid <= 0;
            if (mem_req_valid && mem_req_ready && !mem_pending) begin
                mem_requests <= mem_requests + 1;
                mem_pending <= 1;
                mem_delay <= 2;
            end else if (mem_pending) begin
                if (mem_delay != 0)
                    mem_delay <= mem_delay - 1;
                else begin
                    mem_resp_valid <= 1;
                    mem_resp_data <= TEST_LINE;
                    mem_pending <= 0;
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

    task automatic request_read(input logic [31:0] address, output integer accepted_cycle);
        integer timeout;
        begin
            @(negedge clk);
            timeout = 0;
            while (l2_req_ready !== 1'b1 && timeout < 100) begin
                @(negedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100) $fatal(1, "L2 nunca estuvo ready");
            l2_req_addr = address;
            l2_req_valid = 1;
            @(posedge clk);
            #1;
            accepted_cycle = cycles;
            l2_req_valid = 0;
        end
    endtask

    task automatic await_response(output integer response_cycle);
        integer timeout;
        begin
            timeout = 0;
            while (l2_resp_valid !== 1'b1 && timeout < 100) begin
                @(posedge clk);
                #1;
                timeout = timeout + 1;
            end
            if (timeout >= 100) $fatal(1, "Timeout esperando respuesta de L2");
            response_cycle = cycles;
            check(l2_resp_data === TEST_LINE, "Datos de linea correctos");
        end
    endtask

    task automatic test_hit(input integer number);
        integer accepted, responded, mem_before;
        begin
            $display("--- Read hit %0d ---", number);
            mem_before = mem_requests;
            request_read(TEST_ADDR, accepted);
            await_response(responded);
            $display("Latencia medida: %0d ciclos", responded - accepted);
            check((responded - accepted) == 8, "Read hit tarda exactamente 8 ciclos");
            check(mem_requests == mem_before, "Read hit no solicita memoria principal");
            // Un pulso por respuesta: comprobar el siguiente flanco.
            @(posedge clk);
            #1;
            check(l2_resp_valid === 1'b0, "No hay respuesta duplicada");
        end
    endtask

    integer accepted, responded;
    initial begin
        $dumpfile("l2_latency.vcd");
        $dumpvars(0, tb_l2_latency);
        repeat (3) @(negedge clk);
        rst = 0;

        $display("--- Preparacion: miss para instalar linea ---");
        request_read(TEST_ADDR, accepted);
        await_response(responded);
        check(read_misses == 1, "Primer acceso produce miss");
        check(mem_requests == 1, "Se solicito un solo refill");
        @(posedge clk); #1;
        check(l2_resp_valid === 1'b0, "Respuesta de miss es un solo pulso");

        test_hit(1);
        test_hit(2);

        check(read_hits == 2, "Dos read hits contabilizados");
        check(read_misses == 1, "Solo un read miss contabilizado");
        check(mem_requests == 1, "No hubo refills adicionales");

        if (errors == 0)
            $display("TODAS LAS PRUEBAS PASARON");
        else begin
            $display("TOTAL DE ERRORES: %0d", errors);
            $fatal(1, "Pruebas de latencia fallidas");
        end
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "Timeout global");
    end
endmodule

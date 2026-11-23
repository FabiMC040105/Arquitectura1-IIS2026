`timescale 1ns/1ps
module tb_l1_l2_integration;
    logic clk=0, rst=1;
    always #5 clk=~clk;

    logic cpu_read=0, cpu_write=0;
    logic [31:0] cpu_addr=0, cpu_write_data=0;
    wire [31:0] cpu_read_data;
    wire cpu_ready, cpu_stall;

    wire l2_req_valid, l2_req_ready, l2_resp_valid;
    wire [31:0] l2_req_addr;
    wire [255:0] l2_resp_data;
    wire l2_write_valid, l2_write_ready;
    wire [31:0] l2_write_addr, l2_write_data;

    wire mem_req_valid, mem_req_write;
    logic mem_req_ready=1;
    wire [31:0] mem_req_addr;
    wire [255:0] mem_req_wdata;
    logic mem_resp_valid=0;
    logic [255:0] mem_resp_data=0;
    wire [31:0] read_hits, read_misses, write_hits, write_misses;
    wire [3:0] eviction_count;

    l1_data_system l1 (
        .clk(clk), .rst(rst),
        .cpu_read(cpu_read), .cpu_write(cpu_write),
        .cpu_addr(cpu_addr), .cpu_write_data(cpu_write_data),
        .cpu_read_data(cpu_read_data), .cpu_ready(cpu_ready),
        .cpu_stall(cpu_stall),
        .l2_req_valid(l2_req_valid), .l2_req_ready(l2_req_ready),
        .l2_req_addr(l2_req_addr), .l2_resp_valid(l2_resp_valid),
        .l2_resp_data(l2_resp_data),
        .l2_write_valid(l2_write_valid), .l2_write_ready(l2_write_ready),
        .l2_write_addr(l2_write_addr), .l2_write_data(l2_write_data)
    );

    l2_data_system l2 (
        .clk(clk), .rst(rst),
        .l2_req_valid(l2_req_valid), .l2_req_ready(l2_req_ready),
        .l2_req_addr(l2_req_addr), .l2_resp_valid(l2_resp_valid),
        .l2_resp_data(l2_resp_data),
        .l2_write_valid(l2_write_valid), .l2_write_ready(l2_write_ready),
        .l2_write_addr(l2_write_addr), .l2_write_data(l2_write_data),
        .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready),
        .mem_req_write(mem_req_write), .mem_req_addr(mem_req_addr),
        .mem_req_wdata(mem_req_wdata), .mem_resp_valid(mem_resp_valid),
        .mem_resp_data(mem_resp_data),
        .read_hits(read_hits), .read_misses(read_misses),
        .write_hits(write_hits), .write_misses(write_misses),
        .eviction_count(eviction_count)
    );

    function automatic [255:0] initial_line(input [31:0] address);
        reg [255:0] result;
        reg [31:0] base;
        integer i;
        begin
            base={address[31:5],5'b0};
            result=0;
            for (i=0;i<8;i=i+1)
                result[i*32 +: 32]=32'hA0000000+base+i;
            initial_line=result;
        end
    endfunction

    // RAM simulada: 64 KB / 32 bytes = 2048 lineas.
    reg [255:0] ram [0:2047];
    integer i;
    initial for (i=0;i<2048;i=i+1) ram[i]=initial_line(i*32);

    logic mem_busy=0, saved_write=0;
    reg [31:0] saved_addr=0;
    reg [255:0] saved_data=0;
    integer remaining=0;
    integer ram_reads=0, ram_writes=0;
    integer l1_l2_reads=0, l1_l2_writes=0;

    always @(posedge clk) begin
        if (rst) begin
            mem_busy <= 0;
            mem_resp_valid <= 0;
            remaining <= 0;
            ram_reads <= 0;
            ram_writes <= 0;
            l1_l2_reads <= 0;
            l1_l2_writes <= 0;
        end else begin
            mem_resp_valid <= 0;
            if (l2_req_valid && l2_req_ready)
                l1_l2_reads <= l1_l2_reads+1;
            if (l2_write_valid && l2_write_ready)
                l1_l2_writes <= l1_l2_writes+1;
            if (!mem_busy && mem_req_valid && mem_req_ready) begin
                mem_busy <= 1;
                saved_write <= mem_req_write;
                saved_addr <= mem_req_addr;
                saved_data <= mem_req_wdata;
                remaining <= 4;
                if (mem_req_write) ram_writes <= ram_writes+1;
                else ram_reads <= ram_reads+1;
            end else if (mem_busy) begin
                if (remaining>0) remaining <= remaining-1;
                else begin
                    if (saved_write) begin
                        ram[saved_addr[15:5]] <= saved_data;
                        mem_resp_data <= 0;
                    end else begin
                        mem_resp_data <= ram[saved_addr[15:5]];
                    end
                    mem_resp_valid <= 1;
                    mem_busy <= 0;
                end
            end
        end
    end

    integer errors=0;
    task automatic check(input logic condition, input string message);
        begin
            if (condition===1'b1) $display("PASS: %s",message);
            else begin $display("FAIL: %s",message); errors=errors+1; end
        end
    endtask

    task automatic cpu_load(input [31:0] address,
                            input [31:0] expected);
        integer timeout;
        logic done;
        logic saw_stall;
        begin
            @(negedge clk);
            cpu_addr=address;
            cpu_read=1;
            cpu_write=0;
            timeout=0;
            done=0;
            saw_stall=0;
            while (!done && timeout<1000) begin
                #1;
                if (cpu_stall===1'b1) saw_stall=1;
                if (cpu_ready===1'b1) begin
                    check(cpu_read_data===expected,
                          $sformatf("LOAD %h devuelve %h",address,expected));
                    check(cpu_stall===1'b0,"CPU libera stall al completar LOAD");
                    done=1;
                end else begin
                    @(negedge clk);
                    timeout=timeout+1;
                end
            end
            if (!done) $fatal(1,"Timeout LOAD a %h",address);
            @(negedge clk);
            cpu_read=0;
        end
    endtask

    task automatic cpu_store(input [31:0] address,
                             input [31:0] value);
        integer timeout;
        logic done;
        begin
            @(negedge clk);
            cpu_addr=address;
            cpu_write_data=value;
            cpu_write=1;
            cpu_read=0;
            timeout=0;
            done=0;
            while (!done && timeout<1000) begin
                #1;
                if (cpu_ready===1'b1) begin
                    check(cpu_stall===1'b0,"CPU acepta STORE sin stall");
                    @(posedge clk);
                    #1;
                    cpu_write=0;
                    done=1;
                end else begin
                    @(negedge clk);
                    timeout=timeout+1;
                end
            end
            if (!done) $fatal(1,"Timeout STORE a %h",address);
        end
    endtask

    task automatic drain_l1_writes;
        integer timeout;
        begin
            timeout=0;
            // Esperar vaciado y que el controlador L2 termine la operacion.
            @(negedge clk);
            while ((l1.buffer_count!=0 || l2_write_ready!==1'b1) &&
                   timeout<1000) begin
                @(negedge clk);
                timeout=timeout+1;
            end
            if (timeout==1000) $fatal(1,"Timeout drenando L1 write buffer");
        end
    endtask

    initial begin
        $dumpfile("l1_l2_integration.vcd");
        $dumpvars(0,tb_l1_l2_integration);
        repeat (3) @(negedge clk);
        rst=0;
        $display("--- Integracion L1 real + L2 real ---");

        // Primera lectura: miss L1, miss L2, RAM.
        cpu_load(32'h00000024,32'hA0000021);
        check(l1_l2_reads==1,"L1 solicito una linea a L2");
        check(ram_reads==1,"Miss L2 genero un refill desde RAM");
        check(read_misses==1,"L2 conto primer read miss");

        // Misma linea: hit L1, no debe consultar L2.
        cpu_load(32'h00000028,32'hA0000022);
        check(l1_l2_reads==1,"Hit L1 no vuelve a consultar L2");
        check(ram_reads==1,"Hit L1 no consulta RAM");

        // Store: L1 actualiza la palabra y la envia a L2 por su buffer.
        cpu_store(32'h00000024,32'hDEADBEEF);
        drain_l1_writes();
        check(l1_l2_writes==1,"STORE de L1 llego a L2 una sola vez");
        check(write_hits==1,"L2 registro write hit");
        cpu_load(32'h00000024,32'hDEADBEEF);

        // Forzar un miss L1 de una linea que aun existe en L2:
        // L1 tiene 2 vias; las tres lineas comparten indice [10:5].
        cpu_load(32'h00000820,32'hA0000820);
        cpu_load(32'h00001020,32'hA0001020);
        check(l1_l2_reads==3,"Tres lineas diferentes solicitaron L2");
        check(ram_reads==3,"Tres misses L2 consultaron RAM");
        // Vuelve a 0x20: ahora L1 debe tener miss y L2 hit (L2 usa otro indice).
        cpu_load(32'h00000024,32'hDEADBEEF);
        check(read_hits>=1,"L1 miss fue atendido con hit de L2");
        check(ram_reads==3,"Hit L2 evito una nueva lectura de RAM");

        $display("--- RESULTADO ---");
        if (errors==0) $display("TODAS LAS PRUEBAS PASARON");
        else $fatal(1,"FALLARON %0d verificaciones",errors);
        $finish;
    end
    initial begin
        #200000;
        $fatal(1,"Timeout global de integracion L1 + L2");
    end
endmodule

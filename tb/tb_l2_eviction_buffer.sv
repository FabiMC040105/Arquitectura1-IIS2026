`timescale 1ns/1ps
module tb_l2_eviction_buffer;
    logic clk = 0, rst = 1;
    logic evict_valid = 0, evict_ready;
    logic [31:0] evict_addr = 0;
    logic [255:0] evict_data = 0;
    logic wb_valid;
    logic [31:0] wb_addr;
    logic [255:0] wb_data;
    logic write_complete = 0;
    logic [31:0] check_addr = 0;
    logic raw_conflict, full, empty;
    logic [3:0] count;
    integer errors = 0, i;
    always #5 clk = ~clk;
    l2_eviction_buffer #(.DEPTH(8)) dut (
        .clk(clk), .rst(rst), .evict_valid(evict_valid),
        .evict_ready(evict_ready), .evict_addr(evict_addr),
        .evict_data(evict_data), .wb_valid(wb_valid),
        .wb_addr(wb_addr), .wb_data(wb_data),
        .write_complete(write_complete), .check_addr(check_addr),
        .raw_conflict(raw_conflict), .full(full), .empty(empty),
        .count(count)
    );
    function automatic [255:0] pattern(input integer n);
        begin
            pattern = {8{32'hA5000000}};
            pattern[31:0] = n;
        end
    endfunction
    task automatic check(input logic condition, input string message);
        if (condition === 1'b1) $display("PASS: %s",message);
        else begin $display("FAIL: %s",message); errors = errors + 1; end
    endtask
    task automatic push_line(input logic [31:0] address,
                             input logic [255:0] data);
        begin
            @(negedge clk);
            evict_addr=address; evict_data=data; evict_valid=1;
            #1;
            if (!evict_ready) $fatal(1,"Buffer lleno");
            @(posedge clk); #1;
            evict_valid=0;
        end
    endtask
    task automatic pop_line(input logic [31:0] expected_addr,
                            input logic [255:0] expected_data);
        begin
            @(negedge clk); #1;
            check(wb_valid,"Hay escritura pendiente");
            check(wb_addr === expected_addr,"Direccion FIFO correcta");
            check(wb_data === expected_data,"Datos FIFO correctos");
            write_complete=1;
            @(posedge clk); #1;
            write_complete=0;
        end
    endtask
    initial begin
        $dumpfile("l2_eviction_buffer.vcd");
        $dumpvars(0,tb_l2_eviction_buffer);
        repeat (2) @(posedge clk);
        @(negedge clk); rst=0; #1;
        check(empty && count==0,"Buffer inicialmente vacio");
        push_line(32'h00001000,pattern(0));
        check(count==1,"Contador incrementa a uno");
        check(wb_valid && wb_addr==32'h1000 && wb_data===pattern(0),
              "Primera linea almacenada");
        check_addr=32'h00001004; #1;
        check(raw_conflict,"Conflicto RAW detectado");
        check_addr=32'h00002000; #1;
        check(!raw_conflict,"Sin conflicto para otra linea");
        for (i=1;i<8;i=i+1)
            push_line(32'h00001000+i*32,pattern(i));
        check(full && count==8,"FIFO llena");
        @(negedge clk);
        evict_valid=1; evict_addr=32'h00002000;
        evict_data=pattern(99); #1;
        check(!evict_ready,"Novena linea rechazada");
        @(posedge clk); #1;
        evict_valid=0;
        check(count==8,"No se inserta novena linea");
        pop_line(32'h00001000,pattern(0));
        check(count==7,"Se libera espacio");
        push_line(32'h00002000,pattern(99));
        check(count==8,"FIFO circular llena");
        for (i=1;i<8;i=i+1)
            pop_line(32'h00001000+i*32,pattern(i));
        pop_line(32'h00002000,pattern(99));
        check(empty && count==0 && !wb_valid,"FIFO vacia");
        check_addr=32'h00001000; #1;
        check(!raw_conflict,"Sin RAW tras drenado");
        if (errors==0) $display("TODAS LAS PRUEBAS PASARON");
        else $fatal(1,"Errores: %0d", errors);
        $finish;
    end
endmodule

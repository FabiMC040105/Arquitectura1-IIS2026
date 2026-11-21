`timescale 1ns/1ps
// Prueba unitaria reconstruida de los casos basicos del chat.
module tb_cache_l2;
    logic clk=0,rst=1;
    logic [31:0] lookup_addr=0,write_addr=0,write_data=0,fill_addr=0;
    logic lookup_hit;
    logic [255:0] lookup_data,fill_data=0,victim_data;
    logic write_valid=0,fill_valid=0,victim_valid,victim_dirty;
    logic [31:0] victim_addr;
    logic [1:0] candidate_way;
    integer errors=0;
    always #5 clk=~clk;
    cache_l2 dut(.clk(clk),.rst(rst),.lookup_addr(lookup_addr),
        .lookup_hit(lookup_hit),.lookup_data(lookup_data),
        .write_valid(write_valid),.write_addr(write_addr),.write_data(write_data),
        .fill_valid(fill_valid),.fill_addr(fill_addr),.fill_data(fill_data),
        .fill_way_i(candidate_way),.candidate_way(candidate_way),
        .victim_valid(victim_valid),.victim_dirty(victim_dirty),
        .victim_addr(victim_addr),.victim_data(victim_data));
    initial begin
        $dumpfile("cache_l2.vcd");$dumpvars(0,tb_cache_l2);
        repeat(2) @(negedge clk); rst=0;
        lookup_addr=32'h00000000; #1;
        if (!lookup_hit) $display("PASS: miss inicial");
        else begin $display("FAIL: miss inicial"); errors=errors+1; end
        @(negedge clk);fill_valid=1;fill_addr=0;fill_data={8{32'h11111111}};
        @(negedge clk);fill_valid=0; #1;
        if (lookup_hit && lookup_data=={8{32'h11111111}})
            $display("PASS: refill y hit");
        else begin $display("FAIL: refill");errors=errors+1;end
        @(negedge clk);write_valid=1;write_addr=32'h00000004;write_data=32'hDEADBEEF;
        @(negedge clk);write_valid=0;#1;
        if (lookup_data[63:32]===32'hDEADBEEF)
            $display("PASS: escritura de palabra");
        else begin $display("FAIL: escritura");errors=errors+1;end
        // Una linea dirty se comprueba con el testbench de reemplazo integrado.
        if(errors==0) $display("TODAS LAS PRUEBAS PASARON");
        else $fatal(1,"Errores: %0d",errors);
        $finish;
    end
endmodule

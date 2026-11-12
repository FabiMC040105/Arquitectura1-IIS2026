`timescale 1ns/1ps
// Prueba funcional basica reconstruida del chat.
module tb_l2_controller;
    logic clk=0,rst=1;
    logic l2_req_valid=0,l2_write_valid=0;
    wire l2_req_ready,l2_write_ready,l2_resp_valid;
    logic [31:0] l2_req_addr=0,l2_write_addr=0,l2_write_data=0;
    wire [255:0] l2_resp_data;
    wire mem_req_valid,evict_valid;
    logic mem_req_ready=1,mem_resp_valid=0,evict_ready=1;
    wire [31:0] mem_req_addr,evict_addr;
    wire [255:0] evict_data;
    logic [255:0] mem_resp_data=0;
    wire [31:0] read_hits,read_misses,write_hits,write_misses;
    integer errors=0,requests=0;
    logic mem_pending=0;
    integer mem_delay=0;
    logic [31:0] saved_addr=0;
    always #5 clk=~clk;
    l2_controller dut(.clk(clk),.rst(rst),
       .l2_req_valid(l2_req_valid),.l2_req_ready(l2_req_ready),
       .l2_req_addr(l2_req_addr),.l2_resp_valid(l2_resp_valid),
       .l2_resp_data(l2_resp_data),.l2_write_valid(l2_write_valid),
       .l2_write_ready(l2_write_ready),.l2_write_addr(l2_write_addr),
       .l2_write_data(l2_write_data),.mem_req_valid(mem_req_valid),
       .mem_req_ready(mem_req_ready),.mem_req_addr(mem_req_addr),
       .mem_resp_valid(mem_resp_valid),.mem_resp_data(mem_resp_data),
       .evict_valid(evict_valid),.evict_ready(evict_ready),
       .evict_addr(evict_addr),.evict_data(evict_data),
       .read_hits(read_hits),.read_misses(read_misses),
       .write_hits(write_hits),.write_misses(write_misses));
    function automatic [255:0] make_line(input [31:0] a);
        reg [255:0] r;reg [31:0] base;integer j;
        begin
            base={a[31:5],5'b0};r=0;
            for(j=0;j<8;j=j+1)r[j*32+:32]=32'hAB000000+base+j;
            make_line=r;
        end
    endfunction
    always @(posedge clk) begin
        if(rst) begin
            mem_pending<=0;mem_delay<=0;mem_resp_valid<=0;requests<=0;
        end else begin
            mem_resp_valid<=0;
            if(mem_req_valid&&mem_req_ready&&!mem_pending)begin
                saved_addr<=mem_req_addr;mem_pending<=1;mem_delay<=3;
                requests<=requests+1;
            end else if(mem_pending)begin
                if(mem_delay>0)mem_delay<=mem_delay-1;
                else begin
                    mem_resp_data<=make_line(saved_addr);
                    mem_resp_valid<=1;mem_pending<=0;
                end
            end
        end
    end
    task automatic check(input logic ok,input string label);
        if(ok===1'b1)$display("PASS: %s",label);
        else begin $display("FAIL: %s",label);errors=errors+1;end
    endtask
    task automatic read_line(input [31:0] a,input [255:0] expected);
        integer timeout;bit got_response;
        begin
            @(negedge clk);
            timeout=0;
            while(l2_req_ready!==1'b1&&timeout<250)begin
                @(negedge clk);timeout=timeout+1;
            end
            if(timeout>=250)$fatal(1,"timeout ready");
            l2_req_addr=a;l2_req_valid=1;
            @(posedge clk);#1;l2_req_valid=0;
            timeout=0;got_response=0;
            while(timeout<250&&!got_response)begin
                @(negedge clk);
                if(l2_resp_valid)begin
                    got_response=1;
                    check(l2_resp_data===expected,"Datos correctos");
                end
                timeout=timeout+1;
            end
            if(!got_response)$fatal(1,"timeout respuesta");
        end
    endtask
    task automatic write_word(input [31:0] a,input [31:0] value);
        integer timeout;
        begin
            @(negedge clk);timeout=0;
            while(l2_write_ready!==1'b1&&timeout<250)begin
                @(negedge clk);timeout=timeout+1;
            end
            if(timeout>=250)$fatal(1,"timeout write ready");
            l2_write_addr=a;l2_write_data=value;l2_write_valid=1;
            @(posedge clk);#1;l2_write_valid=0;
            @(negedge clk);timeout=0;
            while(l2_write_ready!==1'b1&&timeout<250)begin
                @(negedge clk);timeout=timeout+1;
            end
            if(timeout>=250)$fatal(1,"timeout write completion");
        end
    endtask
    logic [255:0] expected;
    initial begin
        $dumpfile("l2_controller.vcd");$dumpvars(0,tb_l2_controller);
        repeat(3)@(negedge clk);rst=0;
        expected=make_line(0);
        read_line(0,expected);
        check(read_misses==1&&requests==1,"Primer miss");
        read_line(0,expected);
        check(read_hits==1&&requests==1,"Segundo hit");
        write_word(32'h4,32'hDEADBEEF);
        check(write_hits==1,"Write hit");
        expected[63:32]=32'hDEADBEEF;
        read_line(0,expected);
        check(read_hits==2,"Read after write");
        write_word(32'h88,32'hCAFEBABE);
        check(write_misses==1&&requests==2,"Write allocate");
        expected=make_line(32'h80);
        expected[95:64]=32'hCAFEBABE;
        read_line(32'h80,expected);
        check(read_hits==3&&read_misses==1&&write_hits==1&&write_misses==1,
              "Contadores correctos");
        if(errors==0)$display("TODAS LAS PRUEBAS PASARON");
        else $fatal(1,"Errores: %0d",errors);
        $finish;
    end
    initial begin #100000;$fatal(1,"timeout global");end
endmodule

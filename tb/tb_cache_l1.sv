`timescale 1ns/1ps


module tb_cache_l1;

// SENALES DEL TESTBENCH

logic clk;
logic rst;
logic [31:0] addr;

wire [20:0] tag;
wire [5:0]  set_index;
wire [4:0]  offset;


    // INSTANCIA DE LA CACHE

    cache_l1 dut (
        .clk(clk),
        .rst(rst),

        // Direccion que queremos analizar
        .addr(addr),

        // En esta prueba no realizamos accesos
        .access_valid(1'b0),

        // Desactivamos las escrituras porque no forman parte de este tb
        .write_enable(1'b0),
        .write_data(32'b0),

        // Tampoco recibimos lineas desde L2
        .refill_valid(1'b0),
        .refill_addr(32'b0),
        .refill_data(256'b0),

        // Resultados de dividir la direccion
        .tag(tag),
        .set_index(set_index),
        .offset(offset),

        // Estas salidas no se utilizan en esta prueba
        .hit(),
        .miss(),
        .hit_way(),
        .replace_way(),
        .read_data(),
        .read_valid()
    );


// GENERACION DEL RELOJ

initial clk = 0;

always #5 clk = ~clk;

// PRUEBAS DE DIRECCIONES

task probar_direccion(
input logic [31:0] direccion,
input logic [20:0] tag_esperado,
input logic [5:0] set_esperado,
input logic [4:0] offset_esperado
);
begin
addr = direccion;
#1;

$display(
"Direccion: %h | TAG: %h | SET: %0d | OFFSET: %0d",
addr, tag, set_index, offset
);

if (tag !== tag_esperado ||
set_index !== set_esperado ||
offset !== offset_esperado) begin

$display("ERROR: division incorrecta");
$fatal(1);

end else begin
$display("OK: division correcta");
end
end
endtask

// EJECUCION DE LAS PRUEBAS

initial begin

$display("================================");
$display(" PRUEBAS DE CACHE L1-D");
$display("================================");

rst = 1;
addr = 0;

#12;
rst = 0;

// Verificar que el reset invalidó las lineas
for (integer via = 0; via < 2; via = via + 1) begin
for (integer conjunto = 0; conjunto < 64;
conjunto = conjunto + 1) begin

if (dut.valid_array[via][conjunto] !== 1'b0) begin
                    $display("ERROR: linea valida despues del reset");
                    $fatal(1);
                end
            end
        end

        $display("OK: 128 lineas invalidas despues del reset");

// Direccion inicial
        probar_direccion(32'h00000000, 21'd0, 6'd0, 5'd0);

// Segunda palabra del mismo bloque
        probar_direccion(32'h00000004, 21'd0, 6'd0, 5'd4);

// Ultimo byte del primer bloque
        probar_direccion(32'h0000001F, 21'd0, 6'd0, 5'd31);

// Primera direccion del conjunto 1
        probar_direccion(32'h00000020, 21'd0, 6'd1, 5'd0);

// Mismo conjunto, otro tag
        probar_direccion(32'h00000820, 21'd1, 6'd1, 5'd0);

// Ejemplo combinado
        probar_direccion(32'h00000824, 21'd1, 6'd1, 5'd4);

$display("================================");
        $display(" TODAS LAS PRUEBAS PASARON");
        $display("================================");

$finish;
    end

endmodule
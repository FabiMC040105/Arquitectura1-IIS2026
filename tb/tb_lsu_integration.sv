`timescale 1ns/1ps

module lsu_integration_tb;

    // ============================================================
    // Clock y reset
    // ============================================================

    logic clk;
    logic rst;


    // ============================================================
    // Instrucción LSU
    // ============================================================

    logic [31:0] instr;


    // ============================================================
    // Salidas del decoder
    // ============================================================

    logic [3:0]  base_reg_idx;
    logic [3:0]  data_reg_idx;
    logic [11:0] offset;

    logic load_enable;
    logic store_enable;
    logic reg_write;

    logic nop;
    logic illegal_instr;


    // ============================================================
    // Banco de registros SIMULADO
    //
    // Esto será reemplazado después por reg_file.sv.
    // ============================================================

    logic [31:0] registers [0:15];

    logic [31:0] base_addr;
    logic [31:0] store_data;


    // ============================================================
    // Salidas LSU
    // ============================================================

    logic [31:0] effective_addr;
    logic [31:0] mem_write_data;

    logic mem_read;
    logic mem_write;


    // ============================================================
    // Salidas memoria
    // ============================================================

    logic [31:0] read_data;
    logic access_error;


    // ============================================================
    // LSU DECODER
    // ============================================================

    lsu_decoder decoder (
        .instr(instr),

        .base_reg_idx(base_reg_idx),
        .data_reg_idx(data_reg_idx),
        .offset(offset),

        .load_enable(load_enable),
        .store_enable(store_enable),
        .reg_write(reg_write),

        .nop(nop),
        .illegal_instr(illegal_instr)
    );


    // ============================================================
    // Lectura simulada del banco de registros
    // ============================================================

    always_comb begin
        base_addr  = registers[base_reg_idx];
        store_data = registers[data_reg_idx];
    end


    // ============================================================
    // LSU
    // ============================================================

    lsu lsu_unit (
        .base_addr(base_addr),
        .offset(offset),

        .store_data(store_data),

        .load_enable(load_enable),
        .store_enable(store_enable),

        .effective_addr(effective_addr),
        .mem_write_data(mem_write_data),

        .mem_read(mem_read),
        .mem_write(mem_write)
    );


    // ============================================================
    // DATA MEMORY
    // ============================================================

    data_memory #(
        .MEM_BYTES(65536)
    ) memory (
        .clk(clk),
        .rst(rst),

        .mem_read(mem_read),
        .mem_write(mem_write),

        .addr(effective_addr),
        .write_data(mem_write_data),

        .read_data(read_data),
        .access_error(access_error)
    );


    // ============================================================
    // Clock
    // ============================================================

    always #5 clk = ~clk;


    // ============================================================
    // Test
    // ============================================================

    integer i;

    initial begin

        $dumpfile("lsu_integration.vcd");
        $dumpvars(0, lsu_integration_tb);


        // --------------------------------------------------------
        // Inicialización
        // --------------------------------------------------------

        clk   = 0;
        rst   = 1;
        instr = 32'h00000000;

        for (i = 0; i < 16; i = i + 1)
            registers[i] = 32'h00000000;


        // x0 fijo en cero
        registers[0] = 32'h00000000;

        // x2 será nuestro registro base
        registers[2] = 32'd100;

        // x5 contiene el dato a almacenar
        registers[5] = 32'hCAFEBABE;


        #10;

        rst = 0;


        // ========================================================
        // TEST 1
        //
        // STORE x5, 8(x2)
        //
        // Esperamos:
        //
        // base       = 100
        // offset     = 8
        // dirección  = 108
        // dato       = CAFEBABE
        //
        // ========================================================

        instr = {
            10'b0,         // [31:22] reservados
            12'd8,         // [21:10] offset
            4'd2,          // [9:6]   rb = x2
            4'd5,          // [5:2]   rs1 = x5
            2'b10          // [1:0]   STORE
        };

        #1;


        // Comprobar decoder + LSU antes de escritura
        if (
            base_reg_idx  == 4'd2 &&
            data_reg_idx  == 4'd5 &&
            effective_addr == 32'd108 &&
            mem_write_data == 32'hCAFEBABE &&
            mem_write == 1 &&
            mem_read == 0
        )
            $display(
                "TEST 1 PASS - STORE decodificado y direccion calculada"
            );
        else begin
            $display("TEST 1 FAIL - Error antes de memoria");
            $display("rb index  = %0d", base_reg_idx);
            $display("data index= %0d", data_reg_idx);
            $display("addr      = %0d", effective_addr);
            $display("data      = %h", mem_write_data);
        end


        // Esperamos al flanco positivo para realizar el STORE
        @(posedge clk);

        #1;


        // ========================================================
        // TEST 2
        // Verificar little-endian dentro de la memoria
        // ========================================================

        if (
            memory.memory[108] == 8'hBE &&
            memory.memory[109] == 8'hBA &&
            memory.memory[110] == 8'hFE &&
            memory.memory[111] == 8'hCA
        )
            $display(
                "TEST 2 PASS - STORE little-endian correcto"
            );
        else begin
            $display("TEST 2 FAIL - Error little-endian");
            $display(
                "%h %h %h %h",
                memory.memory[108],
                memory.memory[109],
                memory.memory[110],
                memory.memory[111]
            );
        end


        // ========================================================
        // TEST 3
        //
        // LOAD x6, 8(x2)
        //
        // Debe recuperar CAFEBABE.
        // ========================================================

        instr = {
            10'b0,
            12'd8,
            4'd2,          // rb = x2
            4'd6,          // rd = x6
            2'b01          // LOAD
        };

        #1;


        if (
            base_reg_idx   == 4'd2 &&
            data_reg_idx   == 4'd6 &&
            effective_addr == 32'd108 &&
            mem_read       == 1 &&
            mem_write      == 0 &&
            reg_write      == 1 &&
            read_data      == 32'hCAFEBABE
        )
            $display(
                "TEST 3 PASS - LOAD completo correcto"
            );
        else begin
            $display("TEST 3 FAIL - Error en LOAD");
            $display("rd        = x%0d", data_reg_idx);
            $display("addr      = %0d", effective_addr);
            $display("read_data = %h", read_data);
        end


        // ========================================================
        // Simular WRITEBACK
        //
        // Esto todavía NO forma parte del bloque LSU.
        // Lo hacemos solamente para comprobar el resultado.
        // ========================================================

        if (reg_write)
            registers[data_reg_idx] = read_data;

        #1;


        // ========================================================
        // TEST 4
        // Comprobar que x6 recibió CAFEBABE
        // ========================================================

        if (registers[6] == 32'hCAFEBABE)
            $display(
                "TEST 4 PASS - Resultado listo para writeback"
            );
        else
            $display(
                "TEST 4 FAIL - x6 contiene %h",
                registers[6]
            );


        // ========================================================
        // TEST 5
        //
        // STORE con offset negativo
        //
        // STORE x5, -4(x2)
        //
        // 100 - 4 = 96
        // ========================================================

        instr = {
            10'b0,
            12'hFFC,       // -4
            4'd2,
            4'd5,
            2'b10
        };

        #1;

        if (effective_addr == 32'd96)
            $display(
                "TEST 5 PASS - Offset negativo integrado correctamente"
            );
        else
            $display(
                "TEST 5 FAIL - Esperado 96, obtenido %0d",
                effective_addr
            );


        // Ejecutar escritura
        @(posedge clk);

        #1;


        // ========================================================
        // TEST 6
        // Leer el valor desde dirección 96
        // ========================================================

        instr = {
            10'b0,
            12'hFFC,
            4'd2,
            4'd7,          // LOAD a x7
            2'b01
        };

        #1;

        if (
            effective_addr == 32'd96 &&
            read_data == 32'hCAFEBABE
        )
            $display(
                "TEST 6 PASS - LOAD con offset negativo correcto"
            );
        else
            $display(
                "TEST 6 FAIL - addr=%0d data=%h",
                effective_addr,
                read_data
            );


        // ========================================================
        // TEST 7
        // NOP
        // ========================================================

        instr = 32'h00000000;

        #1;

        if (
            nop == 1 &&
            mem_read == 0 &&
            mem_write == 0
        )
            $display(
                "TEST 7 PASS - NOP no accede a memoria"
            );
        else
            $display(
                "TEST 7 FAIL - NOP genero actividad"
            );


        #10;

        $display("============================================");
        $display("Fin del test de integracion LSU");
        $display("============================================");

        $finish;

    end

endmodule
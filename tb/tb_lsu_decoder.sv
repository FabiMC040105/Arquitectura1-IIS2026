`timescale 1ns/1ps

module lsu_decoder_tb;

    logic [31:0] instr;

    logic [3:0]  base_reg_idx;
    logic [3:0]  data_reg_idx;
    logic [11:0] offset;

    logic load_enable;
    logic store_enable;
    logic reg_write;

    logic nop;
    logic illegal_instr;


    // ============================================================
    // DUT
    // ============================================================

    lsu_decoder dut (
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


    initial begin

        $dumpfile("lsu_decoder.vcd");
        $dumpvars(0, lsu_decoder_tb);


        // ========================================================
        // TEST 1
        // NOP
        // ========================================================

        instr = 32'h00000000;

        #1;

        if (
            nop == 1 &&
            load_enable == 0 &&
            store_enable == 0 &&
            reg_write == 0 &&
            illegal_instr == 0
        )
            $display("TEST 1 PASS - NOP correcto");
        else
            $display("TEST 1 FAIL - Error en NOP");


        // ========================================================
        // TEST 2
        //
        // LOAD x5, 8(x2)
        //
        // offset = 8
        // rb     = x2
        // rd     = x5
        // opcode = 01
        //
        // ========================================================

        instr = {
            10'b0,     // bits [31:22]
            12'd8,     // offset
            4'd2,      // rb = x2
            4'd5,      // rd = x5
            2'b01      // LOAD
        };

        #1;

        if (
            offset == 12'd8 &&
            base_reg_idx == 4'd2 &&
            data_reg_idx == 4'd5 &&
            load_enable == 1 &&
            store_enable == 0 &&
            reg_write == 1 &&
            nop == 0 &&
            illegal_instr == 0
        )
            $display("TEST 2 PASS - LOAD decodificado correctamente");
        else begin
            $display("TEST 2 FAIL - Error decodificando LOAD");
            $display("offset = %0d", offset);
            $display("rb     = x%0d", base_reg_idx);
            $display("rd     = x%0d", data_reg_idx);
        end


        // ========================================================
        // TEST 3
        //
        // STORE x7, 12(x3)
        //
        // offset = 12
        // rb     = x3
        // rs1    = x7
        // opcode = 10
        //
        // ========================================================

        instr = {
            10'b0,
            12'd12,
            4'd3,
            4'd7,
            2'b10
        };

        #1;

        if (
            offset == 12'd12 &&
            base_reg_idx == 4'd3 &&
            data_reg_idx == 4'd7 &&
            load_enable == 0 &&
            store_enable == 1 &&
            reg_write == 0 &&
            nop == 0 &&
            illegal_instr == 0
        )
            $display("TEST 3 PASS - STORE decodificado correctamente");
        else
            $display("TEST 3 FAIL - Error decodificando STORE");


        // ========================================================
        // TEST 4
        //
        // LOAD con offset negativo -4
        //
        // offset = 0xFFC
        //
        // ========================================================

        instr = {
            10'b0,
            12'hFFC,
            4'd4,
            4'd8,
            2'b01
        };

        #1;

        if (
            offset == 12'hFFC &&
            base_reg_idx == 4'd4 &&
            data_reg_idx == 4'd8 &&
            load_enable == 1
        )
            $display("TEST 4 PASS - Offset negativo extraido correctamente");
        else
            $display("TEST 4 FAIL - Error con offset negativo");


        // ========================================================
        // TEST 5
        //
        // Opcode reservado 11
        //
        // ========================================================

        instr = {
            10'b0,
            12'd0,
            4'd1,
            4'd2,
            2'b11
        };

        #1;

        if (illegal_instr == 1)
            $display("TEST 5 PASS - Opcode reservado detectado");
        else
            $display("TEST 5 FAIL - No detecto opcode invalido");


        // ========================================================
        // TEST 6
        //
        // Bits superiores reservados distintos de cero
        //
        // ========================================================

        instr = {
            10'b0000000001,
            12'd8,
            4'd2,
            4'd5,
            2'b01
        };

        #1;

        if (illegal_instr == 1)
            $display("TEST 6 PASS - Bits reservados detectados");
        else
            $display("TEST 6 FAIL - No detecto bits reservados");


        #10;

        $display("Fin del test de LSU decoder");

        $finish;

    end

endmodule
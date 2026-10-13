`timescale 1ns/1ps

module lsu (
    input  logic [31:0] base_addr,
    input  logic [11:0] offset,

    input  logic [31:0] store_data,

    input  logic        load_enable,
    input  logic        store_enable,

    output logic [31:0] effective_addr,
    output logic [31:0] mem_write_data,

    output logic        mem_read,
    output logic        mem_write
);

    logic [31:0] offset_extended;
    assign offset_extended = {{20{offset[11]}},offset};


    // ============================================================
    // Cálculo de dirección efectiva
    // ============================================================
    //
    // LOAD  rd, offset(rb)
    // STORE rs1, offset(rb)
    //
    // dirección = rb + offset
    //

    always_comb begin
        effective_addr = base_addr + offset_extended;
    end


    // ============================================================
    // Datos para STORE
    // ============================================================

    always_comb begin
        mem_write_data = store_data;
    end


    // ============================================================
    // Señales hacia la memoria
    // ============================================================

    always_comb begin
        mem_read  = load_enable;
        mem_write = store_enable;
    end

endmodule
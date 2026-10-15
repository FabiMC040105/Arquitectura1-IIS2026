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

    always_comb begin
        effective_addr = base_addr + offset_extended;
    end

    always_comb begin
        mem_write_data = store_data;
    end

    always_comb begin
        mem_read  = load_enable;
        mem_write = store_enable;
    end

endmodule
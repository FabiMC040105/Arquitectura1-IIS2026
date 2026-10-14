`timescale 1ns/1ps

module instruction_memory #(
    parameter int MEM_BYTES = 65536, //64KiB
    parameter PROGRAM_FILE = "program_test.mem"
)(
    input  logic [31:0]  addr,

    output logic [127:0] bundle_out,
    output logic         access_error
);
    localparam int BUNDLE_BYTES = 16;
    localparam int BUNDLE_WIDTH = 128;
    localparam int NUM_BUNDLES = MEM_BYTES / BUNDLE_BYTES;

    logic [BUNDLE_WIDTH-1:0] memory [0:NUM_BUNDLES-1];
    logic [3:0] addr_dir;
    assign addr_dir = addr[3:0];

    integer i;

    initial begin
        // Inicializar toda la memoria como NOP.
        for (i = 0; i < NUM_BUNDLES; i = i + 1) begin
            memory[i] = 128'b0;
        end

        $readmemh(PROGRAM_FILE, memory); // Cada línea de program.mem representa un bundlecompleto de 128 bits.
    end

    always_comb begin
        bundle_out  = 128'b0;
        access_error = 1'b0;

        // Una dirección válida de instrucción debe estar alineada a 16 bytes
        if (addr_dir != 4'b0000) begin
            access_error = 1'b1;
        end

        else if (addr > (MEM_BYTES - BUNDLE_BYTES)) begin
            access_error = 1'b1;
        end

        else begin
            bundle_out = memory[addr >> 4];
        end
    end

endmodule
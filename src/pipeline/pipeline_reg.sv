`timescale 1ns/1ps

module pipeline_reg #(
    parameter integer WIDTH = 32
)(
    input  logic             clk_i,
    input  logic             rst_i,
    input  logic             enable_i,
    input  logic             flush_i,

    input  logic             valid_i,
    input  logic [WIDTH-1:0] data_i,

    output logic             valid_o,
    output logic [WIDTH-1:0] data_o
);

    // Registro de pipeline
    // Prioridad:
    // 1. Reset
    // 2. Flush
    // 3. Enable
    // 4. Mantener datos

    always_ff @(posedge clk_i or posedge rst_i) begin

        // Reiniciar el registro
        if (rst_i) begin
            valid_o <= 1'b0;
            data_o  <= {WIDTH{1'b0}};
        end

        // Invalidar contenido del registro
        else if (flush_i) begin
            valid_o <= 1'b0;
            data_o  <= {WIDTH{1'b0}};
        end

        // Guardar los nuevos datos
        else if (enable_i) begin
            valid_o <= valid_i;
            data_o  <= data_i;
        end

        // Si enable_i = 0: mantiene los datos anteriores.

    end

endmodule

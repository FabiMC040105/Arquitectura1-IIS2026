
`timescale 1ns/1ps

module l1_write_buffer #(
    parameter DEPTH = 4
)(
    input logic clk,
    input logic rst,

    // ENTRADAS DESDE EL PROCESADOR / L1

    // Nos indica que queremos guardar una escritura
    input logic push,

    // Direccion y dato de la escritura pendiente
    input logic [31:0] push_addr,
    input logic [31:0] push_data,

    // CONTROL DE SALIDA HACIA L2

    // Indica que L2 acepto la escritura mas antigua. Cuando esto ocurre, podemos retirarla
    input logic pop,

    // Escritura que esta esperando ser enviada a L2
    output logic [31:0] out_addr,
    output logic [31:0] out_data,

    // Indica si tenemos una escritura disponible
    output wire out_valid,


    // ESTADO DE LA FIFO

    // Indica que no quedan espacios disponibles
    output wire full,

    // Indica que no tenemos escrituras pendientes
    output wire empty,

    // Cantidad de escrituras almacenadas
    output logic [$clog2(DEPTH+1)-1:0] count
);

    // MEMORIA INTERNA

    // Guardamos por separado las direcciones y los datos de cada escritura
    logic [31:0] addr_mem [0:DEPTH-1];
    logic [31:0] data_mem [0:DEPTH-1];

    // Puntero donde guardaremos la siguiente escritura
    logic [$clog2(DEPTH)-1:0] wr_ptr;

    // Puntero de la escritura mas antigua
    logic [$clog2(DEPTH)-1:0] rd_ptr;

    // Señales internas que indican si realmente podemos insertar o retirar una escritura
    wire do_push;
    wire do_pop;


    // ESTADO ACTUAL

    assign empty = (count == 0);
    assign full  = (count == DEPTH);

    // Solo tenemos una salida valida cuando existe al menos una escritura pendiente
    assign out_valid = !empty;

    // Podemos retirar una escritura si la FIFO no esta vacia y recibimos la confirmacion
    assign do_pop = pop && !empty;

    // Permitimos insertar si existe espacio.
    // Si esta llena, tambien podemos insertar cuando simultaneamente retiramos una entrada
    assign do_push = push && (!full || do_pop);

    // SALIDA HACIA L2

    always_comb begin

        // Por defecto entregamos ceros cuando no tenemos ninguna escritura pendiente
        out_addr = 32'b0;
        out_data = 32'b0;

        if (!empty) begin
            out_addr = addr_mem[rd_ptr];
            out_data = data_mem[rd_ptr];
        end
    end

    // ACTUALIZACION DE LA FIFO

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin

            // Empezamos con la FIFO vacia
            wr_ptr <= '0;
            rd_ptr <= '0;
            count <= '0;

        end
        else begin

            // GUARDAR UNA NUEVA ESCRITURA

            if (do_push) begin

                addr_mem[wr_ptr] <= push_addr;
                data_mem[wr_ptr] <= push_data;

                // Avanzamos hacia la siguiente entrada. Al llegar al final volvemos a cero
                if (wr_ptr == DEPTH-1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            // RETIRAR LA ESCRITURA MAS ANTIGUA

            if (do_pop) begin

                // No necesitamos borrar los datos. Basta con avanzar el puntero
                if (rd_ptr == DEPTH-1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            // ACTUALIZAR CANTIDAD DE ENTRADAS

            case ({do_push, do_pop})

                // Entra una escritura y no sale ninguna
                2'b10: count <= count + 1'b1;

                // Sale una escritura y no entra ninguna
                2'b01: count <= count - 1'b1;

                // Si entran y salen al mismo tiempo, la cantidad de entradas no cambia
                default: count <= count;

            endcase
        end
    end

endmodule

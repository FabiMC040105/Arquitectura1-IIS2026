
`timescale 1ns/1ps

module l2_memory_model #(
    parameter MEM_WORDS = 4096,
    parameter READ_LATENCY = 3
)(
    input logic clk,
    input logic rst,

    // INTERFAZ DE LECTURA DESDE L1

    // L1 solicita una linea completa
    input logic l2_req_valid,

    // Indicamos cuando podemos aceptar la solicitud
    output wire l2_req_ready,

    // Direccion de la linea solicitada
    input logic [31:0] l2_req_addr,

    // Avisamos cuando la linea esta disponible
    output logic l2_resp_valid,

    // Devolvemos ocho palabras de 32 bits
    output logic [255:0] l2_resp_data,

    // INTERFAZ DE ESCRITURA DESDE L1

    // L1 tiene una escritura pendiente
    input logic l2_write_valid,

    // Indicamos si podemos recibir la escritura
    output wire l2_write_ready,

    // Direccion y dato que queremos almacenar
    input logic [31:0] l2_write_addr,
    input logic [31:0] l2_write_data
);

    // MEMORIA SIMULADA

    // Cada posicion guarda una palabra de 32 bits
    // La memoria se inicializa con valores conocidos para que podamos comprobar las lecturas
    logic [31:0] memory [0:MEM_WORDS-1];

    // ESTADO DE LAS LECTURAS

    logic read_busy;

    // Guardamos la direccion para que no cambie mientras esperamos la respuesta
    logic [31:0] pending_addr;

    // Contamos los ciclos de espera de L2
    integer read_counter;

    // Variables auxiliares para recorrer la memoria
    integer i;
    integer j;

    // CONTROL DE SOLICITUDES

    // Aceptamos una lectura cuando no estamos atendiendo otra solicitud
    assign l2_req_ready = !rst && !read_busy;

    // Para mantener el orden entre operaciones, no aceptamos escrituras durante una lectura
    // Ademas, damos prioridad a las solicitudes de lectura cuando ambas llegan juntas
    assign l2_write_ready =
        !rst &&
        !read_busy &&
        !l2_req_valid;

    // INICIALIZACION DE LA MEMORIA

    initial begin

        // Cada palabra comienza con un valor igual a su posicion dentro de memoria
        for (i = 0; i < MEM_WORDS; i = i + 1) begin
            memory[i] = i;
        end

    end

    // LECTURAS Y ESCRITURAS

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            read_busy <= 1'b0;
            pending_addr <= 32'b0;
            read_counter <= 0;

            l2_resp_valid <= 1'b0;
            l2_resp_data <= 256'b0;

        end
        else begin

            // La respuesta solo permanece activa durante un ciclo de reloj
            l2_resp_valid <= 1'b0;

            // ACEPTAR UNA SOLICITUD DE LECTURA

            if (l2_req_valid && l2_req_ready) begin

                // Guardamos la direccion de la linea
                pending_addr <= {
                    l2_req_addr[31:5],
                    5'b00000
                };

                read_busy <= 1'b1;
                read_counter <= READ_LATENCY;

            end

            // PROCESAR UNA LECTURA PENDIENTE

            else if (read_busy) begin

                if (read_counter > 1) begin

                    // Todavia faltan ciclos para completar la solicitud
                    read_counter <= read_counter - 1;

                end
                else begin


                    // La primera palabra se coloca en los bits menos significativos
                    for (j = 0; j < 8; j = j + 1) begin

                        if (((pending_addr >> 2) + j)
                            < MEM_WORDS) begin

                            l2_resp_data[j*32 +: 32] <=
                                memory[(pending_addr >> 2) + j];

                        end
                        else begin

                            // Si la direccion esta fuera del rango, devolvemos cero
                            l2_resp_data[j*32 +: 32] <=
                                32'b0;

                        end

                    end

                    l2_resp_valid <= 1'b1;
                    read_busy <= 1'b0;
                    read_counter <= 0;

                end

            end

            // ACEPTAR UNA ESCRITURA DESDE L1

            // Una escritura aceptada se actualiza en memoria en este mismo flanco
            if (l2_write_valid && l2_write_ready) begin

                if ((l2_write_addr[1:0] == 2'b00) &&
                    ((l2_write_addr >> 2) < MEM_WORDS)) begin

                    memory[l2_write_addr >> 2] <=
                        l2_write_data;

                end

            end

        end

    end

endmodule
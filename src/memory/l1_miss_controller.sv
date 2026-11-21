
`timescale 1ns/1ps

module l1_miss_controller (
    input logic clk,
    input logic rst,

    // Solicitud que llega desde la cache L1
    input logic miss_start,
    input logic [31:0] miss_addr,

    // Solicitud que enviamos a L2
    output logic l2_req_valid,
    input logic l2_req_ready,
    output logic [31:0] l2_req_addr,

    // Respuesta que recibimos desde L2
    input logic l2_resp_valid,
    input logic [255:0] l2_resp_data,

    // Linea que entregamos a nuestra cache
    output logic refill_valid,
    output logic [31:0] refill_addr,
    output logic [255:0] refill_data,

    // Indica que hay una solicitud pendiente
    output logic busy
);

    // Estados del controlador
    typedef enum logic [1:0] {
        IDLE, // No hay ninguna solicitud pendiente
        SEND_REQUEST, // L1 solicita a L2 la línea que necesita
        WAIT_RESPONSE, // L2 aceptó la solicitud, pero todavía no devolvió los datos
        INSTALL_LINE // El controlador presenta los 256 bits recibidos a L1 y activa refill_valid para que la caché los almacene
    } state_t;

    state_t state;

    // Guardamos la direccion solicitada
    logic [31:0] pending_addr;

    // Guardamos los datos recibidos desde L2
    logic [255:0] pending_data;


    // CONTROL SECUENCIAL DE ESTADOS

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            state <= IDLE;
            pending_addr <= 32'b0;
            pending_data <= 256'b0;
        end

        else begin
            case (state)

                IDLE: begin
                    // Guardamos la direccion del bloque cuando comienza un miss de lectura
                    if (miss_start) begin
                        pending_addr <= {miss_addr[31:5], 5'b0};
                        state <= SEND_REQUEST;
                    end
                end

                SEND_REQUEST: begin
                    // Esperamos hasta que L2 acepte la solicitud que estamos enviando
                    if (l2_req_ready)
                        state <= WAIT_RESPONSE;
                end

                WAIT_RESPONSE: begin
                    // Esperamos a que L2 devuelva los 256 bits de la linea
                    if (l2_resp_valid) begin
                        pending_data <= l2_resp_data;
                        state <= INSTALL_LINE;
                    end
                end

                INSTALL_LINE: begin
                    // La linea se instala en L1 durante este estado
                    state <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

    // SALIDAS DEL CONTROLADOR

    // Mantenemos la solicitud hasta que L2 la acepte
    assign l2_req_valid = (state == SEND_REQUEST);

    // Enviamos la direccion del inicio de la linea
    assign l2_req_addr = pending_addr;

    // El controlador esta ocupado mientras procesa una solicitud de lectura
    assign busy = (state != IDLE);

    // Solo enviamos la linea a L1 cuando llegamos al estado de instalacion
    assign refill_valid = (state == INSTALL_LINE);

    assign refill_addr = pending_addr;
    assign refill_data = pending_data;

endmodule

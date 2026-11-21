
`timescale 1ns/1ps

module l1_data_system (
    input logic clk,
    input logic rst,

    // SOLICITUDES DEL PROCESADOR

    // El procesador solicita una lectura o escritura (nunca al mismo tiempo)
    input logic cpu_read,
    input logic cpu_write,

    // Direccion de memoria para LOAD o STORE
    input logic [31:0] cpu_addr,

    // Dato que queremos guardar durante un STORE
    input logic [31:0] cpu_write_data,

    // Respuesta hacia el procesador
    output wire [31:0] cpu_read_data,
    output wire cpu_ready,
    output wire cpu_stall,

    // INTERFAZ DE LECTURA HACIA L2

    // Solicitud de una linea completa de 256 bits
    output wire l2_req_valid,
    input logic l2_req_ready,
    output wire [31:0] l2_req_addr,

    // Respuesta de L2 con la linea solicitada
    input logic l2_resp_valid,
    input logic [255:0] l2_resp_data,


    // INTERFAZ DE ESCRITURA HACIA L2

    // Nos indica que tenemos una escritura pendiente
    output wire l2_write_valid,

    // L2 confirma que puede aceptar la escritura
    input logic l2_write_ready,

    // Direccion y dato que enviaremos hacia L2
    output wire [31:0] l2_write_addr,
    output wire [31:0] l2_write_data
);

    // SEÑALES INTERNAS DE LA CACHE

    wire [20:0] tag;
    wire [5:0] set_index;
    wire [4:0] offset;

    wire hit;
    wire miss;
    wire hit_way;
    wire replace_way;

    wire [31:0] read_data;
    wire read_valid;

    // SENALES DEL CONTROLADOR MISS

    wire refill_valid;
    wire [31:0] refill_addr;
    wire [255:0] refill_data;
    wire controller_busy;

    // Evitamos iniciar varias solicitudes para el mismo MISS
    logic miss_pending;

    wire miss_start;

    // SEÑALES DEL WRITE BUFFER

    wire buffer_push;
    wire buffer_pop;

    wire [31:0] buffer_addr;
    wire [31:0] buffer_data;

    wire buffer_valid;
    wire buffer_full;
    wire buffer_empty;

    wire [2:0] buffer_count;

    // CONTROL DE OPERACIONES

    wire addr_aligned;
    wire store_accept;
    wire load_request;
    wire store_request;

    // Trabajamos con palabras de 32 bits y por eso la direccion debe ser multiplo de cuatro
    assign addr_aligned = (cpu_addr[1:0] == 2'b00);

    // Solo aceptamos una operacion cuando el procesador no solicita LOAD y STORE a la vez
    assign store_request = cpu_write && !cpu_read;

    assign load_request = cpu_read && !cpu_write;

    // ENVIO DE ESCRITURAS HACIA L2

    // La FIFO presenta siempre la escritura mas antigua que todavia no ha salido
    assign l2_write_addr = buffer_addr;
    assign l2_write_data = buffer_data;

    // Evitamos enviar escrituras mientras el controlador esta atendiendo un MISS
    // Tambien evitamos compartir L2 con una solicitud de lectura en curso
    assign l2_write_valid =
        buffer_valid &&
        !controller_busy &&
        !miss_pending &&
        !l2_req_valid;

    // Retiramos una escritura solamente cuando L2 confirma que la acepto
    assign buffer_pop =
        l2_write_valid && l2_write_ready;

    // ACEPTACION DE STORE

    // Aceptamos STORE si:
    // - la direccion esta alineada
    // - no hay un MISS de lectura en proceso
    // - no estamos instalando una linea
    // - hay espacio en la FIFO
    // Si la FIFO esta llena, tambien podemos aceptar un STORE cuando sale otra entrada

    assign store_accept =
        store_request &&
        addr_aligned &&
        !controller_busy &&
        !miss_pending &&
        !refill_valid &&
        (!buffer_full || buffer_pop);

    // Cada STORE aceptado se guarda en la FIFO (esto ocurre tanto con HIT como con MISS)
    assign buffer_push = store_accept;


    // CONTROL DE LECTURAS

    // Por seguridad, no iniciamos una lectura mientras existan escrituras pendientes
    wire load_allowed;

    assign load_allowed =
        load_request &&
        buffer_empty &&
        !store_accept;

    // Solo iniciamos un MISS cuando:
    // - existe una lectura valida
    // - la linea no esta en L1
    // - no tenemos otra solicitud pendiente
    // - el controlador esta disponible
    // - la direccion esta alineada

    assign miss_start =
        load_allowed &&
        miss &&
        !miss_pending &&
        !controller_busy &&
        addr_aligned;

    // INSTANCIA DE LA CACHE L1

    cache_l1 cache (
        .clk(clk),
        .rst(rst),

        // LOAD y STORE utilizan la misma direccion
        .addr(cpu_addr),

        // Solo habilitamos accesos que realmente pueden realizarse en este ciclo
        // Permitimos que la cache reconozca el HIT incluso cuando estamos terminando un MISS
        // Las escrituras solo se habilitan si fueron aceptadas

        .access_valid(
            load_allowed || store_accept
        ),

        // La cache modifica su palabra solamente cuando aceptamos un STORE con HIT
        .write_enable(store_accept),
        .write_data(cpu_write_data),

        // El controlador instala lineas completas recibidas desde L2
        .refill_valid(refill_valid),
        .refill_addr(refill_addr),
        .refill_data(refill_data),

        // Division de la direccion
        .tag(tag),
        .set_index(set_index),
        .offset(offset),

        // Resultado de la busqueda
        .hit(hit),
        .miss(miss),
        .hit_way(hit_way),
        .replace_way(replace_way),

        // Resultado de lectura
        .read_data(read_data),
        .read_valid(read_valid)
    );

    // INSTANCIA DEL WRITE BUFFER

    l1_write_buffer #(
        .DEPTH(4)
    ) write_buffer (
        .clk(clk),
        .rst(rst),

        // Guardamos cada STORE aceptado
        .push(buffer_push),
        .push_addr(cpu_addr),
        .push_data(cpu_write_data),

        // Retiramos una entrada cuando L2 confirma que recibio la escritura
        .pop(buffer_pop),

        // Escritura mas antigua
        .out_addr(buffer_addr),
        .out_data(buffer_data),
        .out_valid(buffer_valid),

        // Estado de la FIFO
        .full(buffer_full),
        .empty(buffer_empty),
        .count(buffer_count)
    );

    // CONTROLADOR DE MISS

    l1_miss_controller controller (
        .clk(clk),
        .rst(rst),

        .miss_start(miss_start),
        .miss_addr(cpu_addr),

        .l2_req_valid(l2_req_valid),
        .l2_req_ready(l2_req_ready),
        .l2_req_addr(l2_req_addr),

        .l2_resp_valid(l2_resp_valid),
        .l2_resp_data(l2_resp_data),

        .refill_valid(refill_valid),
        .refill_addr(refill_addr),
        .refill_data(refill_data),

        .busy(controller_busy)
    );

    // CONTROL DE MISS PENDIENTE

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin
            miss_pending <= 1'b0;
        end
        else begin

            // Registramos una solicitud de lectura que necesita consultar L2
            if (miss_start)
                miss_pending <= 1'b1;

            // Cuando termina el refill y el dato ya puede leerse, liberamos la espera
            else if (miss_pending &&
                     !controller_busy &&
                     read_valid)
                miss_pending <= 1'b0;
        end
    end

    // RESPUESTA AL PROCESADOR

    wire load_ready;

    // Una lectura termina cuando encontramos el dato y no quedan operaciones pendientes
    assign load_ready =
        load_allowed &&
        read_valid &&
        !controller_busy &&
        !miss_pending &&
        addr_aligned;

    // Para STORE, ready indica que la escritura puede aceptarse en el flanco del reloj (no significa que ya se haya escrito en L2)
    assign cpu_ready = load_ready || store_accept;

    // Solo entregamos datos durante LOAD
    assign cpu_read_data =
        load_ready ? read_data : 32'b0;

    // Si el procesador solicita una operacion y todavia no podemos atenderla, debe esperar
    assign cpu_stall =
        (cpu_read || cpu_write) && !cpu_ready;

endmodule
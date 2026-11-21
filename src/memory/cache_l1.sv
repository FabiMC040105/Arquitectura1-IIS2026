`timescale 1ns/1ps

module cache_l1 (
    input logic clk,
    input logic rst,
    input logic [31:0] addr,

    // Nos indica cuando hay una solicitud del procesador
    input logic access_valid,

    // Nos indica que el procesador quiere escribir
    input logic write_enable,

    // Dato de 32 bits que queremos almacenar
    input logic [31:0] write_data,

    // Señales para recibir una linea desde el nivel inferior
    input logic         refill_valid,
    input logic [31:0]  refill_addr,
    input logic [255:0] refill_data,

    // Partes de la direccion de memoria
    output wire [20:0] tag,
    output wire [5:0] set_index,
    output wire [4:0] offset,

    // Resultado de buscar la linea
    output logic hit,
    output logic miss,
    output logic hit_way,

    // Via que se utilizaria para guardar una linea nueva
    output logic replace_way,

    // Dato de 32 bits que leemos de la cache
    output logic [31:0] read_data,

    // Indica si el dato de lectura es valido
    output logic read_valid
);

    // CONFIGURACION DE LA CACHE

    localparam int CACHE_SIZE = 4096;
    localparam int LINE_SIZE  = 32;
    localparam int NUM_WAYS   = 2;

    localparam int NUM_SETS =
        CACHE_SIZE / (LINE_SIZE * NUM_WAYS);

    localparam int OFFSET_BITS = 5;
    localparam int INDEX_BITS  = 6;
    localparam int TAG_BITS    = 21;

    // DIVISION DE LA DIRECCION

    assign offset    = addr[4:0];
    assign set_index = addr[10:5];
    assign tag       = addr[31:11];

    // ESTRUCTURAS INTERNAS

    // Datos: 2 vias, 64 conjuntos, 256 bits
    logic [255:0] data_array [0:1][0:63];

    // Una etiqueta por linea
    logic [20:0] tag_array [0:1][0:63];

    // Un bit valido por linea
    logic valid_array [0:1][0:63];

    // Un bit LRU por conjunto
    logic lru [0:63];
    

    // RESET, RELLENO DE LINEAS Y LRU

    integer i, j;

    // Separamos tambien la direccion de la linea recibida. No necesariamente es igual a la direccion que el procesador tiene en addr en ese momento
    wire [20:0] refill_tag;
    wire [5:0] refill_set;

    assign refill_tag = refill_addr[31:11];
    assign refill_set = refill_addr[10:5];

    // Revisamos donde guardar la nueva linea. Primero usamos una via invalida y, si ambas estan ocupadas, utilizamos el bit LRU
    wire refill_way;

    assign refill_way = !valid_array[0][refill_set] ? 1'b0 :
                        !valid_array[1][refill_set] ? 1'b1 :
                        lru[refill_set];

    always_ff @(posedge clk or posedge rst) begin

        if (rst) begin

            // Al reiniciar, ninguna linea contiene informacion valida
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                for (j = 0; j < NUM_SETS; j = j + 1) begin
                    valid_array[i][j] <= 1'b0;
                    tag_array[i][j]   <= '0;
                    data_array[i][j]  <= '0;
                end
            end

            // Inicializamos el reemplazo de cada conjunto
            for (j = 0; j < NUM_SETS; j = j + 1) begin
                lru[j] <= 1'b0;
            end

        end
        else begin

            // Cuando llega una linea, la guardamos en la via seleccionada del conjunto correcto
            if (refill_valid) begin

                data_array[refill_way][refill_set] <= refill_data;
                tag_array[refill_way][refill_set]   <= refill_tag;
                valid_array[refill_way][refill_set] <= 1'b1;

                // La linea nueva es la mas reciente. Por eso dejamos la otra via como LRU
                lru[refill_set] <= ~refill_way;

            end

            // Si no estamos rellenando, actualizamos LRU cuando el procesador encuentra una linea.
            else if (access_valid && hit) begin

                // Si encontramos la linea, actualizamos el LRU porque acabamos de utilizarla
                lru[set_index] <= ~hit_way;

                // Si es una escritura, modificamos solamente la palabra solicitada
                if (write_enable &&
                    offset[1:0] == 2'b00) begin

                    data_array[hit_way][set_index]
                              [offset[4:2] * 32 +: 32]
                        <= write_data;

                end

            end

        end

    end

    // BUSQUEDA DE HIT Y MISS

    // Guardamos el resultado de revisar cada via
    logic hit_way0;
    logic hit_way1;

    always_comb begin

        // Revisamos si la via 0 tiene la linea solicitada (debe estar valida y tener el mismo tag)
        hit_way0 = valid_array[0][set_index] &&
                   (tag_array[0][set_index] == tag);

        // Hacemos la misma comparacion para la via 1
        hit_way1 = valid_array[1][set_index] &&
                   (tag_array[1][set_index] == tag);

        // Si alguna de las dos vias coincide, hay hit
        hit = hit_way0 || hit_way1;

        // Si no encontramos la linea, hay miss
        miss = !hit;

        // Por defecto seleccionamos la via 0
        hit_way = 1'b0;

        // Si encontramos el dato en la via 1, la seleccionamos
        if (hit_way1)
            hit_way = 1'b1;

    end

    // SELECCION DE VIA PARA REEMPLAZO

    always_comb begin

        // Primero buscamos si hay alguna via libre. Una via invalida se puede usar sin desalojar datos
        if (!valid_array[0][set_index]) begin
            replace_way = 1'b0;
        end

        else if (!valid_array[1][set_index]) begin
            replace_way = 1'b1;
        end

        else begin
            // Si ambas vias estan ocupadas, utilizamos la que indica LRU
            replace_way = lru[set_index];
        end

    end

    // LECTURA DE DATOS DE LA CACHE

    // Cada linea tiene 32 bytes, equivalentes a 8 palabras de 32 bits cada una
    // Los bits [4:2] del offset nos indican cual de esas 8 palabras queremos leer
    wire [2:0] word_index;

    // Aqui guardamos la linea completa de la via donde encontramos el dato solicitado
    wire [255:0] selected_line;

    // Seleccionamos una de las 8 palabras
    assign word_index = offset[4:2];

    // Elegimos la linea de la via que produjo el hit. Si no hay hit, dejamos la linea en cero
    assign selected_line = hit
        ? (hit_way ? data_array[1][set_index]
                   : data_array[0][set_index])
        : 256'b0;

    // Extraemos los 32 bits de la palabra solicitada
    assign read_data = (access_valid && hit &&
                        offset[1:0] == 2'b00)
                       ? selected_line[word_index * 32 +: 32]
                       : 32'b0;

    // El dato solo es valido cuando existe una solicitud, encontramos la linea y la direccion esta alineada
    assign read_valid = access_valid && hit &&
                        (offset[1:0] == 2'b00);


endmodule
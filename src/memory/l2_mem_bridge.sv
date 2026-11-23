`timescale 1ns/1ps

// Adapta el puerto generico mem_req/mem_resp de l2_data_system (una sola
// transaccion en curso, lectura o escritura de una linea de 256 bits) a la
// interfaz partida de mem_subsystem: rd_req/rd_addr/rd_data/rd_done para
// lecturas y ev_push/ev_addr/ev_line para escrituras (drenadas de forma
// asincrona por el FIFO de eviccion). mem_subsystem ya resuelve el cruce de
// dominio de reloj hacia clk_mem, asi que este puente vive enteramente en
// el dominio del procesador.
module l2_mem_bridge (
    input  logic         clk,
    input  logic         rst,

    // Lado L2 (l2_data_system.mem_req_* / mem_resp_*)
    input  logic         mem_req_valid,
    output logic         mem_req_ready,
    input  logic         mem_req_write,
    input  logic [31:0]  mem_req_addr,
    input  logic [255:0] mem_req_wdata,
    output logic         mem_resp_valid,
    output logic [255:0] mem_resp_data,

    // Lado mem_subsystem
    output logic         rd_req,
    output logic [31:0]  rd_addr,
    input  logic [255:0] rd_data,
    input  logic         rd_done,

    output logic         ev_push,
    output logic [31:0]  ev_addr,
    output logic [255:0] ev_line,
    input  logic         ev_full
);

    typedef enum logic [1:0] {S_IDLE, S_READ, S_WRITE_WAIT} state_t;
    state_t state;
    // Guardamos la direccion de lectura cuando L2 acepta la solicitud.
    // L2 puede retirar mem_req_addr al cambiar de estado, pero RAM
    // necesita una direccion estable durante toda la transaccion.
    // Sin este registro, las lecturas podian terminar usando 0x0000.
    logic [31:0] read_addr_q;

    // Solo aceptamos una solicitud nueva cuando no hay otra en curso.
    wire accept_read  = mem_req_valid &&  mem_req_write == 1'b0 && (state == S_IDLE);
    wire accept_write = mem_req_valid &&  mem_req_write == 1'b1 && (state == S_IDLE) && !ev_full;

    assign mem_req_ready = (state == S_IDLE) && (mem_req_write ? !ev_full : 1'b1);

    assign rd_req  = (state == S_READ);
    assign rd_addr = read_addr_q;

    // El push al FIFO de eviccion ocurre en el mismo ciclo en que se acepta
    // la escritura: el FIFO drena de forma asincrona hacia memoria.
    assign ev_push = accept_write;
    assign ev_addr = mem_req_addr;
    assign ev_line = mem_req_wdata;

    assign mem_resp_data  = rd_data;
    assign mem_resp_valid = (state == S_READ && rd_done) || (state == S_WRITE_WAIT);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= S_IDLE;
            read_addr_q <= 32'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (accept_read) begin
                        read_addr_q <= mem_req_addr;
                        state <= S_READ;
                    end
                    else if (accept_write)
                        state <= S_WRITE_WAIT;
                end
                S_READ: begin
                    if (rd_done)
                        state <= S_IDLE;
                end
                // La escritura ya se encolo en el FIFO de eviccion; un solo
                // ciclo basta para notificarle a L2 que puede continuar.
                S_WRITE_WAIT: begin
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

module data_memory #(
    parameter int MEM_BYTES = 65536,
    parameter DATA_FILE = "input.mem" //Para cargar archivos
)(
    input  logic        clk,
    input  logic        rst,

    input  logic        mem_read,
    input  logic        mem_write,

    input  logic [31:0] addr,
    input  logic [31:0] write_data,

    output logic [31:0] read_data,
    output logic        access_error
);

    // Memoria direccionable por bytes.
    // 65536 bytes = 64 KB por defecto.
    logic [7:0] memory [0:MEM_BYTES-1];

    integer i;


    // ============================================================
    // Inicialización
    // ============================================================

    initial begin
        for (i = 0; i < MEM_BYTES; i = i + 1) begin
            memory[i] = 8'h00;
        end

        if (DATA_FILE != "") begin
            $display("Cargando archivo de datos: %s", DATA_FILE);
            $readmemh(DATA_FILE, memory);
        end
    end

    // ============================================================
    // Escritura
    // ============================================================
    //
    // STORE escribe una palabra de 32 bits utilizando little-endian.
    //
    // write_data = 0x12345678
    //
    // addr     -> 0x78
    // addr + 1 -> 0x56
    // addr + 2 -> 0x34
    // addr + 3 -> 0x12
    //

    always_ff @(posedge clk) begin
        if (rst) begin
            // No es necesario borrar los 64 KB durante cada reset.
            // La memoria ya se inicializa en cero en el bloque initial.
        end
        else if (mem_write && !access_error) begin

            memory[addr]     <= write_data[7:0];
            memory[addr + 1] <= write_data[15:8];
            memory[addr + 2] <= write_data[23:16];
            memory[addr + 3] <= write_data[31:24];

        end
    end


    // ============================================================
    // Lectura
    // ============================================================
    //
    // La lectura es combinacional.
    //
    // Los cuatro bytes se reconstruyen respetando little-endian.
    //

    always_comb begin

        read_data = 32'h00000000;

        if (mem_read && !access_error) begin
            read_data = {
                memory[addr + 3],
                memory[addr + 2],
                memory[addr + 1],
                memory[addr]
            };
        end

    end


    // ============================================================
    // Verificación de acceso
    // ============================================================
    //
    // Se deben poder acceder cuatro bytes completos.
    // Por ello addr no puede apuntar a una posición mayor que
    // MEM_BYTES - 4.
    //

    always_comb begin

        access_error = 1'b0;

        if (mem_read || mem_write) begin
            if ((addr > (MEM_BYTES - 4)) || (addr[1:0] != 2'b00)) begin
                access_error = 1'b1;
            end
        end

    end

endmodule
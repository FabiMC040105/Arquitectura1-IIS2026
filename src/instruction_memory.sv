module instruction_memory #(
    parameter int MEM_BYTES = 65536,
    parameter PROGRAM_FILE = "program.mem"
)(
    input  logic [31:0]  addr,

    output logic [127:0] bundle_out,
    output logic         access_error
);

    // ============================================================
    // Parámetros derivados
    // ============================================================

    localparam int BUNDLE_BYTES = 16;
    localparam int BUNDLE_WIDTH = 128;

    localparam int NUM_BUNDLES =
        MEM_BYTES / BUNDLE_BYTES;


    // ============================================================
    // Memoria de instrucciones
    // ============================================================
    //
    // Cada posición contiene UN bundle VLIW completo:
    //
    // [127:96] = CRYPTO
    // [95:64]  = BRU
    // [63:32]  = LSU
    // [31:0]   = ALU
    //

    logic [BUNDLE_WIDTH-1:0] memory [0:NUM_BUNDLES-1];

    integer i;


    // ============================================================
    // Inicialización
    // ============================================================

    initial begin

        // Inicializar toda la memoria como NOP.
        //
        // Bundle completamente en cero:
        //
        // ALU    = NOP
        // LSU    = NOP
        // BRU    = NOP
        // CRYPTO = NOP

        for (i = 0; i < NUM_BUNDLES; i = i + 1) begin
            memory[i] = 128'b0;
        end


        // Cargar programa VLIW.
        //
        // Cada línea de program.mem representa un bundle
        // completo de 128 bits.

        $readmemh(PROGRAM_FILE, memory);

    end


    // ============================================================
    // Lectura
    // ============================================================

    always_comb begin

        bundle_out  = 128'b0;
        access_error = 1'b0;


        // --------------------------------------------------------
        // Verificación de alineamiento
        // --------------------------------------------------------
        //
        // Un bundle ocupa 16 bytes.
        //
        // Por lo tanto una dirección válida de instrucción debe
        // estar alineada a 16 bytes:
        //
        // 0x0000
        // 0x0010
        // 0x0020
        // ...
        //

        if (addr[3:0] != 4'b0000) begin

            access_error = 1'b1;

        end


        // --------------------------------------------------------
        // Verificación de rango
        // --------------------------------------------------------

        else if (addr > (MEM_BYTES - BUNDLE_BYTES)) begin

            access_error = 1'b1;

        end


        // --------------------------------------------------------
        // Lectura del bundle
        // --------------------------------------------------------

        else begin

            bundle_out = memory[addr >> 4];

        end

    end

endmodule
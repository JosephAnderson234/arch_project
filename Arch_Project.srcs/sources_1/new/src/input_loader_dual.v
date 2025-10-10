`timescale 1ns / 1ps;
// ------------------------------------------------------------
// input_loader_dual.v
// Carga secuencial de dos operandos de 32 bits (A y B) usando
// un único botón y 4 switches por nibble para cada operando.
// - Cada flanco de subida en load_btn toma un nibble de A o B.
// - Primero se cargan 8 nibbles en A, luego 8 nibbles en B.
// - Cuando termina, sube load_done=1.
// Señales auxiliares: loading_a indica si aún se está cargando A,
// nibble_count cuenta los nibbles del operando en curso (0..7).
// ------------------------------------------------------------
module input_loader_dual (
    input  wire       clk,
    input  wire       rst,          // activo en alto
    input  wire       load_btn,     // botón para "latch" del nibble actual
    input  wire [3:0] nibbleA,      // switches para cargar A (4 bits)
    input  wire [3:0] nibbleB,      // switches para cargar B (4 bits)
    output reg  [31:0] op_a,        // operando A completo
    output reg  [31:0] op_b,        // operando B completo
    output reg        load_done,    // 1 cuando A y B completos (8+8 nibbles)
    output reg        loading_a,    // 1 si estamos cargando A; 0 si B
    output reg  [3:0] nibble_count  // nibbles cargados del operando actual (0..7)
);

    // Anti-rebote / detector de flanco de subida
    reg load_btn_q;
    wire load_btn_rise;

    always @(posedge clk or posedge rst) begin
        if (rst) load_btn_q <= 1'b0;
        else     load_btn_q <= load_btn;
    end
    assign load_btn_rise = load_btn & ~load_btn_q;

    // Lógica principal
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            op_a         <= 32'd0;
            op_b         <= 32'd0;
            load_done    <= 1'b0;
            loading_a    <= 1'b1;     // comenzamos cargando A
            nibble_count <= 4'd0;
        end else begin
            // Si ya se completó el paquete A+B, no seguir cargando
            // hasta que alguien (arriba) consuma y haga reset.
            if (!load_done) begin
                if (load_btn_rise) begin
                    if (loading_a) begin
                        // Desplazar A (28->0) e insertar nibbleA en bits [3:0]
                        op_a <= {op_a[27:0], nibbleA};
                        // Actualiza contador de nibbles para A
                        if (nibble_count == 4'd7) begin
                            nibble_count <= 4'd0;
                            loading_a    <= 1'b0; // pasar a cargar B
                        end else begin
                            nibble_count <= nibble_count + 4'd1;
                        end
                    end else begin
                        // Cargando B
                        op_b <= {op_b[27:0], nibbleB};
                        if (nibble_count == 4'd7) begin
                            nibble_count <= 4'd0;
                            load_done    <= 1'b1; // ambos operandos listos
                        end else begin
                            nibble_count <= nibble_count + 4'd1;
                        end
                    end
                end
            end
        end
    end

endmodule

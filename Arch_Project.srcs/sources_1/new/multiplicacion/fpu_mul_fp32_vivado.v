`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/07/2025 06:08:59 PM
// Design Name: 
// Module Name: mul_div
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////



// fpu_mul_fp32_min.v - multiplicación IEEE-754 FP32 (didáctico y compacto)

module fpu_mul_fp32_vivado (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] a,          // FP32: S|E|F
    input  wire [31:0] b,          // FP32
    output reg  [31:0] result,     // FP32
    output reg         valid_out,
    output reg  [4:0]  flags       // {invalid, div_by_zero, overflow, underflow, inexact}
);
    // --- Constantes FP32 ---
    localparam BIAS = 127;

    // 1) Unpack
    wire sA = a[31];
    wire sB = b[31];
    wire [7:0]  eA = a[30:23];
    wire [7:0]  eB = b[30:23];
    wire [22:0] fA = a[22:0];
    wire [22:0] fB = b[22:0];

    // 2) Clasificación
    wire A_isZero = (eA==8'd0) && (fA==23'd0);
    wire B_isZero = (eB==8'd0) && (fB==23'd0);
    wire A_isSub  = (eA==8'd0) && (fA!=23'd0);
    wire B_isSub  = (eB==8'd0) && (fB!=23'd0);
    wire A_isInf  = (eA==8'hFF) && (fA==23'd0);
    wire B_isInf  = (eB==8'hFF) && (fB==23'd0);
    wire A_isNaN  = (eA==8'hFF) && (fA!=23'd0);
    wire B_isNaN  = (eB==8'hFF) && (fB!=23'd0);

    // 3) Signo de salida
    wire sOUT = sA ^ sB;

    // 4) Camino especial (combinacional)
    reg         is_special;
    reg  [31:0] special_word;
    reg  [4:0]  special_flags;

    always @* begin
        is_special    = 1'b0;
        special_word  = 32'b0;
        special_flags = 5'b0;

        if (A_isNaN || B_isNaN) begin
            // NaN * x -> NaN (quiet NaN)
            is_special    = 1'b1;
            special_flags = 5'b1_0000;                  // invalid
            special_word  = {1'b0, 8'hFF, 1'b1, 22'b0};
        end else if ((A_isZero && B_isInf) || (B_isZero && A_isInf)) begin
            // 0 * Inf -> NaN (invalid)
            is_special    = 1'b1;
            special_flags = 5'b1_0000;                  // invalid
            special_word  = {1'b0, 8'hFF, 1'b1, 22'b0};
        end else if (A_isInf || B_isInf) begin
            // Inf * finito != 0 -> Inf
            is_special    = 1'b1;
            special_word  = {sOUT, 8'hFF, 23'b0};
        end else if (A_isZero || B_isZero) begin
            // 0 * finito -> 0
            is_special    = 1'b1;
            special_word  = {sOUT, 8'd0, 23'd0};
        end
    end

    // 5) Mantisas de 24 bits (1 oculto si normal; 0 si subnormal)
    wire [23:0] MA = A_isSub ? {1'b0, fA} : {(eA!=8'd0), fA};
    wire [23:0] MB = B_isSub ? {1'b0, fB} : {(eB!=8'd0), fB};

    // 6) Exponentes desbiasados (e=E-bias; para subnormal E=0 => 1-bias)
    function signed [12:0] unbias;
        input [7:0] E;
        begin
            if (E==8'd0) unbias = 13'sd1 - 13'sd127;
            else         unbias = $signed({5'b0,E}) - 13'sd127;
        end
    endfunction

    wire signed [12:0] eA_unb = unbias(eA);
    wire signed [12:0] eB_unb = unbias(eB);

    // 7) Producto de mantisas (24x24 -> 48)
    wire [47:0] PROD = MA * MB;
    wire signed [12:0] eSUM0 = eA_unb + eB_unb;

    // 8) Normalización (queremos 1.x con el 1 en bit 46 de PROD)
    reg  [47:0] Pn;
    reg  signed [12:0] eSUM1;

    always @* begin
        if (PROD[47]) begin
            Pn    = PROD >> 1;   // 10.x -> corrección
            eSUM1 = eSUM0 + 1;
        end else if (PROD[46]) begin
            Pn    = PROD;        // 1.x ok
            eSUM1 = eSUM0;
        end else begin
            Pn    = PROD << 1;   // 0.x (subnormales)
            eSUM1 = eSUM0 - 1;
        end
    end

    // 9) Redondeo RNE (Nearest, ties-to-even)
    // fracción 23 bits = Pn[45:23], G=Pn[22], R=Pn[21], S=OR(Pn[20:0])
    wire [22:0] frac_pre = Pn[45:23];
    wire        G        = Pn[22];
    wire        R        = Pn[21];
    wire        S        = |Pn[20:0];
    wire        roundUp  = G && (R || S || frac_pre[0]);

    wire [23:0] frac_with_hidden = {Pn[46], frac_pre}; // 1 + 23
    wire [24:0] rounded          = {1'b0, frac_with_hidden} + (roundUp ? 25'd1 : 25'd0);

    reg  [23:0] frac_fin;
    reg  signed [12:0] eSUM2;

    always @* begin
        if (rounded[24]) begin
            // carry por redondeo -> desplaza y e+1
            frac_fin = {1'b1, rounded[24:1]};
            eSUM2    = eSUM1 + 1;
        end else begin
            frac_fin = rounded[23:0];
            eSUM2    = eSUM1;
        end
    end

    // 10) Re-sesgar y chequear overflow/underflow
    wire signed [13:0] E_biased = eSUM2 + 13'sd127;
    wire overflow  = (E_biased > 13'sd254);   // 255 reservado
    wire under_biased_nonpos = (E_biased <= 0);
    wire inexact_rnd = (G | R | S);

    // 11) Empaquetado (sin slices variables; subnormal con bucles)
    reg [31:0] normal_word;
    reg [4:0]  normal_flags;

    always @(*) begin : ALUSITO
        integer shift;
        reg [23:0] frac_den;
        integer i;
        reg lost_bits;
        reg [23:0] mask;

        normal_word  = 32'b0;
        normal_flags = 5'b0;

        if (overflow) begin
            // -> +/-Inf
            normal_word        = {sOUT, 8'hFF, 23'b0};
            normal_flags[2]    = 1'b1;        // overflow
            normal_flags[0]    = inexact_rnd; // inexact si hubo descarte
        end else if (under_biased_nonpos) begin
            // -> intentar subnormal (E_biased<=0)
            // shift = 1 - E_biased (entero >=1)
            shift = (1 - E_biased);
            if (shift > 24) begin
                // demasiado pequeño: va a 0
                normal_word     = {sOUT, 8'd0, 23'd0};
                normal_flags[1] = 1'b1; // underflow
                // lost bits = cualquiera en frac_fin o por redondeo previo
                lost_bits = 1'b0;
                for (i=0; i<24; i=i+1) begin
                    if (frac_fin[i]) lost_bits = 1'b1;
                end
                normal_flags[0] = inexact_rnd | lost_bits;
            end else begin
                // subnormal: desplaza derecha frac_fin (quita hidden)
                frac_den = frac_fin >> shift;
                normal_word     = {sOUT, 8'd0, frac_den[22:0]};
                normal_flags[1] = 1'b1; // underflow
                // sticky por lo perdido en el desplazamiento: OR de los bits que se "cayeron"
                lost_bits = 1'b0;
                if (shift >= 24) begin
                    lost_bits = |frac_fin;
                end else if (shift != 0) begin
                    mask = ((24'd1 << shift) - 24'd1);
                    lost_bits = |(frac_fin & mask);
                end
                normal_flags[0] = inexact_rnd | lost_bits;
            end
        end else begin
            // normal
            normal_word     = {sOUT, E_biased[7:0], frac_fin[22:0]};
            normal_flags[0] = inexact_rnd;
        end
    end

    // 12) Salida registrada (1 ciclo después de start)
    always @(posedge clk) begin
        if (rst) begin
            result    <= 32'd0;
            flags     <= 5'd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b0;
            if (start) begin
                if (is_special) begin
                    result    <= special_word;
                    flags     <= special_flags;
                    valid_out <= 1'b1;
                end else begin
                    result    <= normal_word;
                    flags     <= normal_flags;
                    valid_out <= 1'b1;
                end
            end
        end
    end
endmodule

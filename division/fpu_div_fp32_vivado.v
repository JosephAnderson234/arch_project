`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/08/2025 10:19:21 AM
// Design Name: 
// Module Name: fpu_div_fp32_vivado
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


// fpu_div_fp32_vivado.v
// División IEEE-754 FP32 (1|8|23), compatible con Vivado (Verilog-2001)

module fpu_div_fp32_vivado (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [31:0] a,          // dividendo  FP32: S|E|F
    input  wire [31:0] b,          // divisor    FP32: S|E|F
    output reg  [31:0] result,     // cociente   FP32
    output reg         valid_out,
    output reg  [4:0]  flags       // {invalid, div_by_zero, overflow, underflow, inexact}
);
    // --- Constantes ---
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

    // 4) Camino especial
    reg         is_special;
    reg  [31:0] special_word;
    reg  [4:0]  special_flags;

    always @* begin
        is_special    = 1'b0;
        special_word  = 32'b0;
        special_flags = 5'b0;

        if (A_isNaN || B_isNaN) begin
            // NaN / x -> NaN (invalid por propagación segura)
            is_special    = 1'b1;
            special_flags = 5'b1_0000;                 // invalid
            special_word  = {1'b0, 8'hFF, 1'b1, 22'b0}; // quiet NaN
        end else if (A_isZero && B_isZero) begin
            // 0 / 0 -> NaN (invalid)
            is_special    = 1'b1;
            special_flags = 5'b1_0000;                 // invalid
            special_word  = {1'b0, 8'hFF, 1'b1, 22'b0};
        end else if (A_isInf && B_isInf) begin
            // Inf / Inf -> NaN (invalid)
            is_special    = 1'b1;
            special_flags = 5'b1_0000;                 // invalid
            special_word  = {1'b0, 8'hFF, 1'b1, 22'b0};
        end else if (!A_isInf && B_isZero) begin
            // finite / 0 -> Inf (div_by_zero)
            is_special    = 1'b1;
            special_flags = 5'b0_1000;                 // div_by_zero
            special_word  = {sOUT, 8'hFF, 23'b0};
        end else if (A_isZero && !B_isZero && !B_isInf) begin
            // 0 / finite -> 0
            is_special    = 1'b1;
            special_word  = {sOUT, 8'd0, 23'd0};
        end else if (A_isInf && !B_isInf) begin
            // Inf / finite -> Inf
            is_special    = 1'b1;
            special_word  = {sOUT, 8'hFF, 23'b0};
        end else if (!A_isInf && B_isInf) begin
            // finite / Inf -> 0
            is_special    = 1'b1;
            special_word  = {sOUT, 8'd0, 23'd0};
        end
    end

    // 5) Mantisas (24 bits): normal -> 1.F ; subnormal -> 0.F
    wire [23:0] MA = A_isSub ? {1'b0, fA} : {(eA!=8'd0), fA};
    wire [23:0] MB = B_isSub ? {1'b0, fB} : {(eB!=8'd0), fB};

    // 6) Exponentes desbiasados (para subnormales usar 1-bias)
    function signed [12:0] unbias;
        input [7:0] E;
        begin
            if (E==8'd0) unbias = 13'sd1 - 13'sd127;
            else         unbias = $signed({5'b0,E}) - 13'sd127;
        end
    endfunction

    wire signed [12:0] eA_unb = unbias(eA);
    wire signed [12:0] eB_unb = unbias(eB);

    // 7) División de mantisas (fixed-point):
    // Queremos ~27 bits (1+23+3) para tener fracción+GRS.
    // q_fixed = floor( (MA / MB) * 2^(23+3) ) = (MA << 26) / MB
    wire [49:0] numer = {MA, 26'b0};     // 24+26 = 50 bits
    wire [23:0] denom = MB;

    wire [26:0] q_fixed = (denom!=0) ? (numer / denom) : 27'd0;  // cociente
    wire [23:0] r_fixed = (denom!=0) ? (numer % denom) : 24'd0;  // resto (para sticky)

    // r = MA/MB ∈ (0, 2). Si r<1, el MSB de q_fixed (bit26) es 0.
    // Normalizamos: si q_fixed[26]==1 -> ya está 1.x ; si 0 -> <<1 y exp--.
    reg  [26:0] qn;
    reg  signed [12:0] eDIFF0;
    always @* begin
        if (q_fixed[26]) begin
            qn     = q_fixed;             // 1.x
            eDIFF0 = eA_unb - eB_unb;     // exponente base
        end else begin
            qn     = q_fixed << 1;        // 0.x -> 1.x
            eDIFF0 = (eA_unb - eB_unb) - 1;
        end
    end

    // 8) Redondeo RNE con G/R/S
    // fracción 23 bits: qn[25:3]
    // G = qn[2], R = qn[1], S = (qn[0] | (r_fixed!=0))  -> sticky si resto ≠ 0
    wire [22:0] frac_pre = qn[25:3];
    wire        G        = qn[2];
    wire        R        = qn[1];
    wire        S        = qn[0] | (r_fixed != 0);
    wire        roundUp  = G && (R || S || frac_pre[0]);

    // Mantisa con oculto: {1, frac_pre} y suma de redondeo
    wire [23:0] frac_with_hidden = {qn[26], frac_pre};  // 1 + 23
    wire [24:0] rounded          = {1'b0, frac_with_hidden} + (roundUp ? 25'd1 : 25'd0);

    reg  [23:0] frac_fin;
    reg  signed [12:0] eDIFF1;
    always @* begin
        if (rounded[24]) begin
            // carry por redondeo -> 10.000... -> desplazar y exp++
            frac_fin = {1'b1, rounded[24:1]};
            eDIFF1   = eDIFF0 + 1;
        end else begin
            frac_fin = rounded[23:0];
            eDIFF1   = eDIFF0;
        end
    end

    // 9) Re-sesgar y chequear overflow/underflow
    wire signed [13:0] E_biased = eDIFF1 + 13'sd127;
    wire overflow  = (E_biased > 13'sd254);     // 255 reservado
    wire under_biased_nonpos = (E_biased <= 0);
    wire inexact_rnd = (G | R | S);

    // 10) Empaquetado (subnormal si E_biased<=0)
    always @* begin : PACK
        integer shift;
        integer i;
        reg [23:0] frac_den;
        reg        lost_bits;

        result     = 32'b0;
        flags      = 5'b0;

        if (is_special) begin
            result = special_word;
            flags  = special_flags;
        end
        else if (overflow) begin
            result        = {sOUT, 8'hFF, 23'b0}; // ±Inf
            flags[2]      = 1'b1;                 // overflow
            flags[0]      = inexact_rnd;          // normalmente 1
        end
        else if (under_biased_nonpos) begin
            // Subnormal o 0
            shift = (1 - E_biased); // >=1
            if (shift > 24) begin
                // demasiado pequeño: va a 0
                result   = {sOUT, 8'd0, 23'd0};
                flags[1] = 1'b1;                  // underflow
                // pérdida de bits: cualquiera en frac_fin o por resto
                lost_bits = (r_fixed!=0) ? 1'b1 : 1'b0;
                for (i=0; i<24; i=i+1) begin
                    if (frac_fin[i]) lost_bits = 1'b1;
                end
                flags[0] = inexact_rnd | lost_bits;
            end else begin
                // subnormal: desplazar derecha frac_fin
                frac_den = frac_fin >> shift;
                result   = {sOUT, 8'd0, frac_den[22:0]};
                flags[1] = 1'b1;                  // underflow
                // sticky por bits "caídos" + resto de la división
                lost_bits = (r_fixed!=0) ? 1'b1 : 1'b0;
                for (i=0; i<shift; i=i+1) begin
                    if (frac_fin[i]) lost_bits = 1'b1;
                end
                flags[0] = inexact_rnd | lost_bits;
            end
        end
        else begin
            // normal
            result   = {sOUT, E_biased[7:0], frac_fin[22:0]};
            flags[0] = inexact_rnd;
        end
    end

    // 11) Registro de salida (misma latencia que MUL: 1 ciclo tras start)
    reg [31:0] result_r;
    reg [4:0]  flags_r;

    always @(posedge clk) begin
        if (rst) begin
            result_r  <= 32'd0;
            flags_r   <= 5'd0;
            result    <= 32'd0;
            flags     <= 5'd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b0;
            if (start) begin
                result_r  <= result;
                flags_r   <= flags;
                result    <= result;
                flags     <= flags;
                valid_out <= 1'b1;
            end
        end
    end

endmodule


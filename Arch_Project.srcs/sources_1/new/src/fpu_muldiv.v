`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.10.2025 10:52:42
// Design Name: 
// Module Name: fpu_muldiv
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


// =============================================================
// File: src/fpu_muldiv.v
// Role: Wrapper MUL/DIV para FP16/FP32 usando módulos Vivado-friendly.
//  - Interfaz con start/valid.
//  - Soporta mode_fp: 0=half (usa conversión half<->single), 1=single.
//  - round_mode[1:0]: actualmente se soporta 00 (RNE). Otros modos ignorados.
//  - Requiere: fpu_mul_fp32_vivado, fpu_div_fp32_vivado
// =============================================================


// =============================================================
// File: src/fpu_muldiv.v
// Wrapper MUL/DIV para FP16/FP32 (Vivado-friendly)
// Requiere: fpu_mul_fp32_vivado, fpu_div_fp32_vivado
// =============================================================


module fpu_muldiv (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,      // pulso de 1 ciclo
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    input  wire        op_sel,     // 0=mul, 1=div
    input  wire        mode_fp,    // 0=half, 1=single
    input  wire [1:0]  round_mode, // 00=RNE (otros ignorados aquí)
    output reg  [31:0] result,
    output reg  [4:0]  flags,      // {overflow, underflow, div0, invalid, inexact}
    output reg         valid_out
);
    // Interno FP32 (si mode_fp=0 convertimos HALF→SINGLE)
    wire [31:0] a32 = mode_fp ? op_a : half_to_single(op_a[15:0]);
    wire [31:0] b32 = mode_fp ? op_b : half_to_single(op_b[15:0]);

    // Instancias FP32 específicas
    wire [31:0] res_mul32, res_div32;
    wire        v_mul32, v_div32;
    // Orden de flags en estos módulos: {invalid, div_by_zero, overflow, underflow, inexact}
    wire [4:0]  flg_mul32, flg_div32;

    fpu_mul_fp32_vivado U_MUL (
        .clk(clk), .rst(rst), .start(start & ~op_sel),
        .a(a32), .b(b32),
        .result(res_mul32), .valid_out(v_mul32), .flags(flg_mul32)
    );

    fpu_div_fp32_vivado U_DIV (
        .clk(clk), .rst(rst), .start(start & op_sel),
        .a(a32), .b(b32),
        .result(res_div32), .valid_out(v_div32), .flags(flg_div32)
    );

    // Selección
    wire [31:0] res32   = op_sel ? res_div32 : res_mul32;
    wire [4:0]  flg32_v = op_sel ? flg_div32 : flg_mul32; // {invalid, div_by_zero, overflow, underflow, inexact}
    wire        v32     = op_sel ? v_div32   : v_mul32;

    // Remapeo a orden {overflow, underflow, div0, invalid, inexact}
    wire [4:0] flags_remap = {flg32_v[2], flg32_v[3], flg32_v[1], flg32_v[0], flg32_v[4]};

    // Empaquetado final (half opcional)
    always @(posedge clk) begin
        if (rst) begin
            result    <= 32'd0;
            flags     <= 5'd0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= 1'b0;
            if (v32) begin
                if (mode_fp) begin
                    result <= res32; // FP32 directo
                end else begin
                    result <= {16'd0, single_to_half(res32)}; // FP16 en lower
                end
                flags     <= flags_remap;
                valid_out <= 1'b1;
            end
        end
    end

    // ------------ Conversión HALF<->SINGLE (RNE) ------------
    function [31:0] half_to_single;
        input [15:0] h;
        reg        s;
        reg  [4:0] e;
        reg  [9:0] f;
        reg  [7:0] E;
        reg [22:0] F;
        integer    sh;
        reg  [9:0] ff;
        begin
            s = h[15]; e = h[14:10]; f = h[9:0];
            if (e==5'd0) begin
                if (f==10'd0) begin
                    E=8'd0; F=23'd0;            // ±0
                end else begin
                    // subnormal -> normaliza
                    ff = f; sh = 0;
                    while (ff[9]==1'b0) begin
                        ff = ff << 1;
                        sh = sh + 1;
                    end
                    ff = ff & 10'h1FF;          // quitar el 1
                    // Nota: aproximación simple del exponente al normalizar
                    E = 8'd127 - (15-1) - sh;   // = 113 - sh
                    F = {ff, 13'd0};
                end
            end else if (e==5'h1F) begin
                E=8'hFF; F = {(f!=0), 22'd0};   // Inf/NaN (qNaN simple)
            end else begin
                E = e - 5'd15 + 8'd127;
                F = {f, 13'd0};
            end
            half_to_single = {s,E,F};
        end
    endfunction

    function [15:0] single_to_half;
        input [31:0] x;
        reg        s;
        reg  [7:0] E;
        reg [22:0] F;
        reg  [4:0] eH;
        reg  [9:0] fH;
        reg        G, R, Sb, roundUp;
        integer    shift;
        reg [24:0] frac24;
        reg [24:0] shv;
        integer    E_unb;
        integer    Eb;
        begin
            s = x[31]; E = x[30:23]; F = x[22:0];
            if (E==8'd255) begin
                // Inf/NaN
                eH = 5'h1F; fH = (F!=0)? 10'h200 : 10'd0;
            end else if (E==8'd0) begin
                // 0 o subnormal -> 0 (aprox)
                eH = 5'd0; fH = 10'd0;
            end else begin
                // Re-bias
                E_unb = E - 127;        // -126..+127
                Eb    = E_unb + 15;     // half bias
                if (Eb >= 31) begin
                    // overflow -> Inf
                    eH = 5'h1F; fH = 10'd0;
                end else if (Eb <= 0) begin
                    // subnormal half
                    shift  = (1 - Eb);
                    frac24 = {1'b1, F};               // 1.F
                    shv    = frac24 >> (14 + shift);  // a 10 bits
                    G      = (frac24 >> (13 + shift)) & 1;
                    R      = (frac24 >> (12 + shift)) & 1;
                    // máscara de sticky de los bits caídos
                    Sb     = |(frac24 & ((25'd1 << (12 + shift)) - 1));
                    fH     = shv[9:0];
                    roundUp = G && (R || Sb || fH[0]);
                    if (roundUp) fH = fH + 1'b1;
                    eH = 5'd0;
                end else begin
                    // normal half: mapear 23->10 con RNE
                    eH = Eb[4:0];
                    G  = F[12];
                    R  = F[11];
                    Sb = |F[10:0];
                    fH = F[22:13];
                    roundUp = G && (R || Sb || fH[0]);
                    if (roundUp) begin
                        fH = fH + 1'b1;
                        if (fH==10'd0) begin
                            // carry -> incrementa exponente si cabe
                            if (eH!=5'h1F) eH = eH + 1'b1; else begin eH=5'h1F; fH=10'd0; end
                        end
                    end
                end
            end
            single_to_half = {s,eH,fH};
        end
    endfunction
endmodule

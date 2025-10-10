`timescale 1ns / 1ps
module fpu_addsub (
    input  [31:0] op_a,
    input  [31:0] op_b,
    input         op_sel,       // 0 = add, 1 = sub
    input         mode_fp,      // 0 = half (16-bit), 1 = single (32-bit)
    input         round_mode,   // 0 = nearest even, 1 = toward +∞
    output reg [31:0] result,
    output reg [4:0]  flags      // {overflow, underflow, div0, invalid, inexact}
);

    // ===== Constantes =====
    localparam SINGLE_EXP_BITS  = 8;
    localparam SINGLE_FRAC_BITS = 23;
    localparam SINGLE_BIAS      = 127;
    localparam HALF_EXP_BITS    = 5;
    localparam HALF_FRAC_BITS   = 10;
    localparam HALF_BIAS        = 15;

    // ===== Preparación de operandos según modo =====
    wire [31:0] a_val = (mode_fp) ? op_a : {16'b0, op_a[15:0]};
    wire [31:0] b_val = (mode_fp) ? op_b : {16'b0, op_b[15:0]};

    wire sign_a = mode_fp ? a_val[31] : a_val[15];
    wire sign_b = mode_fp ? b_val[31] : b_val[15];

    wire [7:0] exp_a = mode_fp ? a_val[30:23] : {3'b000, a_val[14:10]};
    wire [7:0] exp_b = mode_fp ? b_val[30:23] : {3'b000, b_val[14:10]};

    wire [22:0] frac_a = mode_fp ? a_val[22:0] : {a_val[9:0], 13'b0};
    wire [22:0] frac_b = mode_fp ? b_val[22:0] : {b_val[9:0], 13'b0};

    // Mantisa con bit implícito (solo si NO es denormal)
    wire [23:0] mant_a = (exp_a == 0) ? {1'b0, frac_a} : {1'b1, frac_a};
    wire [23:0] mant_b = (exp_b == 0) ? {1'b0, frac_b} : {1'b1, frac_b};

    // ===== Casos especiales con límites dinámicos =====
    wire [7:0] exp_max = mode_fp ? 8'hFF : 8'h1F;
    
    wire is_nan_a  = (exp_a == exp_max && frac_a != 0);
    wire is_nan_b  = (exp_b == exp_max && frac_b != 0);
    wire is_inf_a  = (exp_a == exp_max && frac_a == 0);
    wire is_inf_b  = (exp_b == exp_max && frac_b == 0);
    wire is_zero_a = (exp_a == 0 && frac_a == 0);
    wire is_zero_b = (exp_b == 0 && frac_b == 0);
    
    reg effective_sub;
    wire sign_b_eff;
    
    assign sign_b_eff = sign_b ^ op_sel;

    always @(*) begin 
        flags = 5'b00000;
        result = 32'b0;

        // -------- Casos especiales --------
        if (is_nan_a || is_nan_b) begin
            result = mode_fp ? 32'h7FC00000 : 32'h00007E00;
            flags[1] = 1'b1; // invalid
        end
        else if (is_inf_a || is_inf_b) begin
            if (is_inf_a && is_inf_b && (sign_a ^ sign_b_eff)) begin
                // Inf - Inf = NaN
                result = mode_fp ? 32'h7FC00000 : 32'h00007E00;
                flags[1] = 1'b1;
            end else begin
                if (is_inf_a)
                    result = mode_fp ? {sign_a, 8'hFF, 23'b0} : {16'b0, sign_a, 5'h1F, 10'b0};
                else
                    result = mode_fp ? {sign_b_eff, 8'hFF, 23'b0} : {16'b0, sign_b_eff, 5'h1F, 10'b0};
            end
        end
        else if (is_zero_a && is_zero_b) begin: xd
            reg sign_zero;
            sign_zero = (sign_a && sign_b && !op_sel) || (sign_a && !sign_b && op_sel);
            result = mode_fp ? {sign_zero, 31'b0} : {16'b0, sign_zero, 15'b0};
        end
        else if (is_zero_a) begin
            result = mode_fp ? {sign_b_eff, exp_b, frac_b} : {16'b0, sign_b_eff, exp_b[4:0], frac_b[22:13]};
        end
        else if (is_zero_b) begin
            result = mode_fp ? {sign_a, exp_a, frac_a} : {16'b0, sign_a, exp_a[4:0], frac_a[22:13]};
        end
        // -------- Operación normal --------
        else begin: xd2
            reg [7:0] exp_diff;
            reg [26:0] mant_a_shifted, mant_b_shifted;
            reg [27:0] mant_res;
            reg [7:0] exp_res;
            reg sign_res;
            reg guard, round_bit, sticky;
            reg [23:0] mant_final;
            integer shift_count;

            // === 1. Determinar operación efectiva ===
            effective_sub = (sign_a != sign_b_eff);

            // === 2. Alinear exponentes ===
            if (exp_a > exp_b) begin
                exp_diff = exp_a - exp_b;
                mant_a_shifted = {mant_a, 3'b000};
                if (exp_diff >= 27)
                    mant_b_shifted = 27'b0;
                else
                    mant_b_shifted = ({mant_b, 3'b000} >> exp_diff);
                exp_res = exp_a;
                sign_res = sign_a;
            end else if (exp_b > exp_a) begin
                exp_diff = exp_b - exp_a;
                if (exp_diff >= 27)
                    mant_a_shifted = 27'b0;
                else
                    mant_a_shifted = ({mant_a, 3'b000} >> exp_diff);
                mant_b_shifted = {mant_b, 3'b000};
                exp_res = exp_b;
                sign_res = sign_b_eff;
            end else begin
                mant_a_shifted = {mant_a, 3'b000};
                mant_b_shifted = {mant_b, 3'b000};
                exp_res = exp_a;
                // Si exponentes iguales, en resta el signo depende de cuál mantisa es mayor
                if (effective_sub && mant_b > mant_a)
                    sign_res = sign_b_eff;
                else
                    sign_res = sign_a;
            end

            // === 3. Suma o resta efectiva ===
            if (!effective_sub) begin
                mant_res = {1'b0, mant_a_shifted} + {1'b0, mant_b_shifted};
            end else begin
                if (mant_a_shifted >= mant_b_shifted) begin
                    mant_res = {1'b0, mant_a_shifted} - {1'b0, mant_b_shifted};
                    sign_res = sign_a;
                end else begin
                    mant_res = {1'b0, mant_b_shifted} - {1'b0, mant_a_shifted};
                    sign_res = sign_b_eff;
                end
            end

            // === 4. Normalización ===
            if (mant_res == 0) begin
                result = mode_fp ? 32'h00000000 : 32'h00000000;
                flags[3] = 1'b1; // underflow
            end else begin
                // Shift derecha si hay overflow (bit 27 set)
                if (mant_res[27]) begin
                    mant_res = mant_res >> 1;
                    exp_res = exp_res + 1;
                end 
                // Shift izquierda hasta que bit 26 esté en 1
                else begin
                    shift_count = 0;
                    while (!mant_res[26] && mant_res != 0 && exp_res > 1 && shift_count < 27) begin
                        mant_res = mant_res << 1;
                        exp_res = exp_res - 1;
                        shift_count = shift_count + 1;
                    end
                end

                // Extraer bits de redondeo ANTES de tomar la mantisa
                // La mantisa normalizada debe tener el bit implícito en posición 26
                // Tomamos bits 25:3 para obtener los 23 bits de fracción
                // y bits 2:0 para redondeo (guard, round, sticky)
                guard = mant_res[2];
                round_bit = mant_res[1];
                sticky = mant_res[0];
                mant_final = {1'b0, mant_res[25:3]};

                // === 5. Redondeo ===
                flags[0] = 0;
                case(round_mode)
                    1'b0: begin // Round to nearest even
                        if (guard && (round_bit || sticky || mant_final[0])) begin
                            mant_final = mant_final + 1'b1;
                            flags[0] = 1'b1;
                        end
                    end
                    1'b1: begin // Round toward +∞
                        if (!sign_res && (guard || round_bit || sticky)) begin
                            mant_final = mant_final + 1'b1;
                            flags[0] = 1'b1;
                        end
                    end
                endcase

                // Si redondeo causó overflow en la mantisa
                if (mant_final[23]) begin
                    mant_final = mant_final >> 1;
                    exp_res = exp_res + 1;
                end

                // === 6. Verificar overflow/underflow y construir resultado ===
                if (mode_fp) begin
                    if (exp_res >= 8'hFF) begin
                        // Overflow: retornar infinito
                        flags[4] = 1'b1;
                        result = {sign_res, 8'hFF, 23'b0};
                    end else if (exp_res == 0) begin
                        // Underflow: retornar cero o denormal
                        flags[3] = 1'b1;
                        result = {sign_res, 8'h00, mant_final[22:0]};
                    end else begin
                        result = {sign_res, exp_res, mant_final[22:0]};
                    end
                end else begin
                    if (exp_res >= 8'h1F) begin
                        flags[4] = 1'b1;
                        result = {16'b0, sign_res, 5'h1F, 10'b0};
                    end else if (exp_res == 0) begin
                        flags[3] = 1'b1;
                        result = {16'b0, sign_res, 5'h00, mant_final[22:13]};
                    end else begin
                        result = {16'b0, sign_res, exp_res[4:0], mant_final[22:13]};
                    end
                end
            end
        end
    end
endmodule
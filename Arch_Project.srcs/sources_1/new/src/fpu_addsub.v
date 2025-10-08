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

    // ===== Variables internas =====
    reg [7:0] exp_diff;
    reg [26:0] mant_a_shifted, mant_b_shifted;
    reg [27:0] mant_res;
    reg [7:0] exp_res;
    reg sign_res;
    reg guard, round_bit, sticky;
    reg [23:0] mant_final;
    reg effective_sub;
    reg sign_zero;
    integer shift_count;

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

    // ===== Casos especiales =====
    wire [7:0] exp_max = mode_fp ? 8'hFF : 8'h1F;
    wire is_nan_a  = (exp_a == exp_max && frac_a != 0);
    wire is_nan_b  = (exp_b == exp_max && frac_b != 0);
    wire is_inf_a  = (exp_a == exp_max && frac_a == 0);
    wire is_inf_b  = (exp_b == exp_max && frac_b == 0);
    wire is_zero_a = (exp_a == 0 && frac_a == 0);
    wire is_zero_b = (exp_b == 0 && frac_b == 0);

    always @(*) begin
        // ===== Inicialización =====
        flags = 5'b00000;
        result = 32'b0;
        exp_diff = 8'b0;
        mant_a_shifted = 27'b0;
        mant_b_shifted = 27'b0;
        mant_res = 28'b0;
        exp_res = 8'b0;
        sign_res = 1'b0;
        guard = 1'b0;
        round_bit = 1'b0;
        sticky = 1'b0;
        mant_final = 24'b0;
        effective_sub = 1'b0;
        sign_zero = 1'b0;
        shift_count = 0;

        // ===== Casos especiales =====
        if (is_nan_a || is_nan_b) begin
            result = mode_fp ? 32'h7FC00000 : 32'h00007E00;
            flags[1] = 1'b1; // invalid
        end
        else if (is_inf_a || is_inf_b) begin
            if (is_inf_a && is_inf_b && (sign_a ^ sign_b ^ op_sel)) begin
                // Inf - Inf = NaN
                result = mode_fp ? 32'h7FC00000 : 32'h00007E00;
                flags[1] = 1'b1;
            end else begin
                if (is_inf_a)
                    result = mode_fp ? {sign_a, 8'hFF, 23'b0} : {16'b0, sign_a, 5'h1F, 10'b0};
                else
                    result = mode_fp ? {sign_b ^ op_sel, 8'hFF, 23'b0} : {16'b0, sign_b ^ op_sel, 5'h1F, 10'b0};
            end
        end
        else if (is_zero_a && is_zero_b) begin
            sign_zero = (sign_a && sign_b && !op_sel) || (sign_a && !sign_b && op_sel);
            result = mode_fp ? {sign_zero, 31'b0} : {16'b0, sign_zero, 15'b0};
        end
        else if (is_zero_a) begin
            result = mode_fp ? {sign_b ^ op_sel, exp_b, frac_b} : {16'b0, sign_b ^ op_sel, exp_b[4:0], frac_b[22:13]};
        end
        else if (is_zero_b) begin
            result = mode_fp ? {sign_a, exp_a, frac_a} : {16'b0, sign_a, exp_a[4:0], frac_a[22:13]};
        end

        // ===== Operación normal =====
        else begin
            // Alinear exponentes
            if (exp_a > exp_b) begin
                exp_diff = exp_a - exp_b;
                mant_a_shifted = {mant_a, 3'b000};
                mant_b_shifted = (exp_diff >= 27) ? 27'b0 : ({mant_b, 3'b000} >> exp_diff);
                exp_res = exp_a;
                sign_res = sign_a;
            end else if (exp_b > exp_a) begin
                exp_diff = exp_b - exp_a;
                mant_b_shifted = {mant_b, 3'b000};
                mant_a_shifted = (exp_diff >= 27) ? 27'b0 : ({mant_a, 3'b000} >> exp_diff);
                exp_res = exp_b;
                sign_res = sign_b ^ op_sel;
            end else begin
                mant_a_shifted = {mant_a, 3'b000};
                mant_b_shifted = {mant_b, 3'b000};
                exp_res = exp_a;
                sign_res = sign_a;
            end

            // Determinar operación efectiva
            effective_sub = (sign_a ^ sign_b ^ op_sel);

            if (!effective_sub)
                mant_res = {1'b0, mant_a_shifted} + {1'b0, mant_b_shifted};
            else begin
                if (mant_a_shifted >= mant_b_shifted) begin
                    mant_res = {1'b0, mant_a_shifted} - {1'b0, mant_b_shifted};
                    sign_res = sign_a;
                end else begin
                    mant_res = {1'b0, mant_b_shifted} - {1'b0, mant_a_shifted};
                    sign_res = sign_b ^ op_sel;
                end
            end

            // ===== Normalización =====
            if (mant_res == 0) begin
                result = 32'h00000000;
                flags[3] = 1'b1; // underflow
            end else begin
                if (mant_res[27]) begin
                    mant_res = mant_res >> 1;
                    exp_res = exp_res + 1;
                end else if (!mant_res[26]) begin
                    shift_count = 0;
                    while (!mant_res[26] && mant_res != 0 && exp_res > 0 && shift_count < 27) begin
                        mant_res = mant_res << 1;
                        exp_res = exp_res - 1;
                        shift_count = shift_count + 1;
                    end
                end

                // Guard, round, sticky
                guard = mant_res[2];
                round_bit = mant_res[1];
                sticky = mant_res[0];
                mant_final = mant_res[26:3];

                // ===== Redondeo =====
                flags[0] = 0; // inexact
                case (round_mode)
                    1'b0: if (guard && (round_bit || sticky || mant_final[0])) begin
                              mant_final = mant_final + 1'b1;
                              flags[0] = 1'b1;
                          end
                    1'b1: if (!sign_res && (guard || round_bit || sticky)) begin
                              mant_final = mant_final + 1'b1;
                              flags[0] = 1'b1;
                          end
                endcase

                // Handle mantissa overflow before it wraps exp_res
if (mant_final[23]) begin
    if (exp_res >= 8'hFE) begin
        // would overflow exponent → Infinity
        exp_res = 8'hFF;
        mant_final = 24'b0;
    end else begin
        mant_final = mant_final >> 1;
        exp_res = exp_res + 1;
    end
end

                
                // ===== Overflow / Underflow y resultado =====
                if (mode_fp) begin
                    if (exp_res >= 8'hFF) begin
                        flags[4] = 1'b1; // overflow
                        result = {sign_res, 8'hFF, 23'b0}; // +Inf / -Inf
                    end else if (exp_res == 0) begin
                        flags[3] = 1'b1; // underflow
    result = {sign_res, exp_res[7:0], mant_final[22:0]};
                    end else begin
                        result = {sign_res, exp_res[7:0], mant_final[22:0]};
                    end
                end else begin
                    if (exp_res >= 8'h1F) begin
                        flags[4] = 1'b1; // overflow
                        result = {16'b0, sign_res, 5'h1F, 10'b0};
                    end else if (exp_res == 0) begin
                        flags[3] = 1'b1; // underflow
    result = {sign_res, exp_res[7:0], mant_final[22:0]};
                    end else begin
                        result = {16'b0, sign_res, exp_res[4:0], mant_final[22:13]};
                    end
                end
            end
        end
    end
endmodule

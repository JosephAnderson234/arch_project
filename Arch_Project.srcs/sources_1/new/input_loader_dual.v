`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////
// Modo half (mode_fp=0): 16 bits (4 nibbles por operando)
// Modo single (mode_fp=1): 32 bits (8 nibbles por operando)
////////////////////////////////////////////////////////////////////////////////// Primero se termina de cargar A y despues se termina de cargar B

module input_loader_dual (
    input clk,
    input rst,
    input load_btn,           // botón para cargar nibble
    input mode_fp,            // 0 = 16 bits, 1 = 32 bits
    input [3:0] nibbleA,      // switches para A
    input [3:0] nibbleB,      // switches para B
    output reg [31:0] op_a,   // operandos completos
    output reg [31:0] op_b,
    output reg load_done,     // indica que ambos operandos están listos
    output reg loading_a,     // 1 = cargando A, 0 = cargando B
    output reg [3:0] nibble_count // cuántos nibbles se han cargado del actual
);

    // Anti-rebote simple
    reg load_btn_prev;
    wire btn_rise = load_btn & ~load_btn_prev;

    // Cálculo dinámico del límite de nibbles según modo
    wire [3:0] nibble_limit = (mode_fp) ? 4'd8 : 4'd4;

    // FSM
    localparam LOAD_A = 2'b00, LOAD_B = 2'b01, DONE = 2'b10;
    reg [1:0] state, next_state;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= LOAD_A;
            op_a <= 0;
            op_b <= 0;
            nibble_count <= 0;
            loading_a <= 1;
            load_done <= 0;
            load_btn_prev <= 0;
        end else begin
            load_btn_prev <= load_btn;
            state <= next_state;

            if (btn_rise) begin
                case (state)
                    LOAD_A: begin
                        op_a <= {op_a[27:0], nibbleA};
                        nibble_count <= nibble_count + 1;
                    end
                    LOAD_B: begin
                        op_b <= {op_b[27:0], nibbleB};
                        nibble_count <= nibble_count + 1;
                    end
                endcase
            end
        end
    end

    // Transiciones de estado
    always @(*) begin
        next_state = state;
        case (state)
            LOAD_A: begin
                loading_a = 1;
                load_done = 0;
                if (btn_rise && nibble_count == nibble_limit - 1)
                    next_state = LOAD_B;
            end
            LOAD_B: begin
                loading_a = 0;
                load_done = 0;
                if (btn_rise && nibble_count == nibble_limit - 1)
                    next_state = DONE;
            end
            DONE: begin
                load_done = 1;
                loading_a = 0;
            end
        endcase
    end
endmodule

/* Suma y resta comnbinacional
module fpu_addsub (
    input  [31:0] op_a,
    input  [31:0] op_b,
    input         op_sel,       // 0 = add, 1 = sub
    input         mode_fp,      // 0 = half (16-bit), 1 = single (32-bit)
    input  [1:0]  round_mode,   // 00 = nearest even
    output reg [31:0] result,
    output reg [4:0]  flags      // {overflow, underflow, div0, invalid, inexact}
);

    // IEEE-754 constants
    localparam HALF_EXP_BITS = 5;
    localparam HALF_FRAC_BITS = 10;
    localparam SINGLE_EXP_BITS = 8;
    localparam SINGLE_FRAC_BITS = 23;

    // --- Dynamic field sizes based on mode ---
    wire [15:0] a_half = op_a[15:0];
    wire [15:0] b_half = op_b[15:0];

    // Select precision
    wire [31:0] a_val = (mode_fp) ? op_a : {16'b0, a_half};
    wire [31:0] b_val = (mode_fp) ? op_b : {16'b0, b_half};

    // Field extraction
    wire sign_a = a_val[31];
    wire sign_b = b_val[31];
    wire [7:0] exp_a = mode_fp ? a_val[30:23] : {3'b000, a_val[14:10]};
    wire [7:0] exp_b = mode_fp ? b_val[30:23] : {3'b000, b_val[14:10]};
    wire [23:0] mant_a = mode_fp ? {1'b1, a_val[22:0]} : {1'b1, a_val[9:0], 13'b0};
    wire [23:0] mant_b = mode_fp ? {1'b1, b_val[22:0]} : {1'b1, b_val[9:0], 13'b0};

    // Case flags
    wire is_zero_a = (exp_a == 0 && mant_a[22:0] == 0);
    wire is_zero_b = (exp_b == 0 && mant_b[22:0] == 0);
    wire is_inf_a  = (exp_a == 8'hFF && mant_a[22:0] == 0);
    wire is_inf_b  = (exp_b == 8'hFF && mant_b[22:0] == 0);
    wire is_nan_a  = (exp_a == 8'hFF && mant_a[22:0] != 0);
    wire is_nan_b  = (exp_b == 8'hFF && mant_b[22:0] != 0);

    // --- Early return for special cases ---
    always @(*) begin
        flags = 5'b00000;
        result = 32'b0;

        // NaN propagation
        if (is_nan_a || is_nan_b) begin
            result = 32'h7FC00000; // canonical NaN
            flags[1] = 1'b1;       // invalid
        end

        // Infinity handling
        else if (is_inf_a || is_inf_b) begin
            if (is_inf_a && is_inf_b && (sign_a ^ sign_b) && (op_sel == 1'b0))
                result = 32'h7FC00000; // inf - inf => NaN
            else
                result = {sign_a, 8'hFF, 23'b0};
        end

        // Zero handling
        else if (is_zero_a && is_zero_b) begin
            result = {op_sel ? 1'b1 : 1'b0, {mode_fp ? 8'h00 : 8'h00}, 23'b0};
        end

        // --- Normal operation ---
        else begin
            reg [7:0] exp_diff;
            reg [23:0] mant_a_shifted, mant_b_shifted;
            reg [24:0] mant_res;
            reg [7:0] exp_res;
            reg sign_res;

            exp_diff = (exp_a > exp_b) ? (exp_a - exp_b) : (exp_b - exp_a);

            // Align mantissas
            if (exp_a > exp_b) begin
                mant_a_shifted = mant_a;
                mant_b_shifted = mant_b >> exp_diff;
                exp_res = exp_a;
            end else begin
                mant_a_shifted = mant_a >> exp_diff;
                mant_b_shifted = mant_b;
                exp_res = exp_b;
            end

            // Suma o resta según signo
            if (sign_a == (sign_b ^ op_sel))
                mant_res = mant_a_shifted + mant_b_shifted;
            else
                mant_res = mant_a_shifted - mant_b_shifted;

            sign_res = sign_a;

            // Normalización
            if (mant_res[24]) begin
                mant_res = mant_res >> 1;
                exp_res = exp_res + 1;
            end else begin
                while (!mant_res[23] && exp_res > 0) begin
                    mant_res = mant_res << 1;
                    exp_res = exp_res - 1;
                end
            end

            // Reconstrucción del resultado IEEE-754
            result = {sign_res, exp_res, mant_res[22:0]};

            // Flags básicos
            flags[4] = (exp_res == 8'hFF); // overflow
            flags[3] = (exp_res == 0);     // underflow
            flags[0] = 0;                  // div0 no aplica
            flags[1] = 0;                  // invalid handled above
            flags[2] = 0;                  // inexact placeholder
        end
    end
endmodule*/

`timescale 1ns / 1ns

module tb_fpu_addsub();

    // Señales del DUT
    reg [31:0] op_a, op_b;
    reg op_sel, mode_fp, round_mode;
    wire [31:0] result;
    wire [4:0] flags;

    // Instancia del módulo
    fpu_addsub uut (
        .op_a(op_a),
        .op_b(op_b),
        .op_sel(op_sel),
        .mode_fp(mode_fp),
        .round_mode(round_mode),
        .result(result),
        .flags(flags)
    );

    integer test_num = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    // ==========================================
    // FUNCIONES DE CONVERSIÓN FLOAT <-> REAL
    // ==========================================
    
    // Convierte float32 a real
    function real fp32_to_real;
        input [31:0] fp;
        reg sign;
        reg [7:0] exp;
        reg [22:0] frac;
        real mant;
        integer exp_val;
        begin
            sign = fp[31];
            exp = fp[30:23];
            frac = fp[22:0];
            
            // Casos especiales
            if (exp == 8'hFF) begin
                if (frac != 0)
                    fp32_to_real = 0.0/0.0; // NaN
                else if (sign)
                    fp32_to_real = -1.0/0.0; // -Inf
                else
                    fp32_to_real = 1.0/0.0; // +Inf
            end
            else if (exp == 0 && frac == 0) begin
                fp32_to_real = sign ? -0.0 : 0.0;
            end
            else begin
                // Normal o denormal
                if (exp == 0)
                    mant = $itor(frac) / $pow(2.0, 23.0);
                else
                    mant = 1.0 + $itor(frac) / $pow(2.0, 23.0);
                
                exp_val = exp - 127;
                fp32_to_real = mant * $pow(2.0, $itor(exp_val));
                if (sign) fp32_to_real = -fp32_to_real;
            end
        end
    endfunction

    // Convierte float16 a real
    function real fp16_to_real;
        input [15:0] fp;
        reg sign;
        reg [4:0] exp;
        reg [9:0] frac;
        real mant;
        integer exp_val;
        begin
            sign = fp[15];
            exp = fp[14:10];
            frac = fp[9:0];
            
            if (exp == 5'h1F) begin
                if (frac != 0)
                    fp16_to_real = 0.0/0.0; // NaN
                else if (sign)
                    fp16_to_real = -1.0/0.0; // -Inf
                else
                    fp16_to_real = 1.0/0.0; // +Inf
            end
            else if (exp == 0 && frac == 0) begin
                fp16_to_real = sign ? -0.0 : 0.0;
            end
            else begin
                if (exp == 0)
                    mant = $itor(frac) / $pow(2.0, 10.0);
                else
                    mant = 1.0 + $itor(frac) / $pow(2.0, 10.0);
                
                exp_val = exp - 15;
                fp16_to_real = mant * $pow(2.0, $itor(exp_val));
                if (sign) fp16_to_real = -fp16_to_real;
            end
        end
    endfunction

    // Convierte real a float32
    function [31:0] real_to_fp32;
        input real val;
        reg sign;
        reg [7:0] exp;
        reg [22:0] frac;
        real abs_val, mant;
        integer exp_val;
        begin
            if (val != val) begin // NaN
                real_to_fp32 = 32'h7FC00000;
            end
            else if (val == 1.0/0.0) begin // +Inf
                real_to_fp32 = 32'h7F800000;
            end
            else if (val == -1.0/0.0) begin // -Inf
                real_to_fp32 = 32'hFF800000;
            end
            else if (val == 0.0) begin
                real_to_fp32 = 32'h00000000;
            end
            else begin
                sign = (val < 0);
                abs_val = sign ? -val : val;
                
                // Calcular exponente
                exp_val = 0;
                mant = abs_val;
                while (mant >= 2.0) begin
                    mant = mant / 2.0;
                    exp_val = exp_val + 1;
                end
                while (mant < 1.0 && exp_val > -126) begin
                    mant = mant * 2.0;
                    exp_val = exp_val - 1;
                end
                
                // Manejar underflow
                if (exp_val < -126) begin
                    real_to_fp32 = {sign, 31'b0};
                end
                // Manejar overflow
                else if (exp_val > 127) begin
                    real_to_fp32 = sign ? 32'hFF800000 : 32'h7F800000;
                end
                else begin
                    exp = exp_val + 127;
                    frac = $rtoi((mant - 1.0) * $pow(2.0, 23.0));
                    real_to_fp32 = {sign, exp, frac};
                end
            end
        end
    endfunction

    // Convierte real a float16
    function [31:0] real_to_fp16;
        input real val;
        reg sign;
        reg [4:0] exp;
        reg [9:0] frac;
        real abs_val, mant;
        integer exp_val;
        begin
            if (val != val) begin
                real_to_fp16 = 32'h00007E00;
            end
            else if (val == 1.0/0.0) begin
                real_to_fp16 = 32'h00007C00;
            end
            else if (val == -1.0/0.0) begin
                real_to_fp16 = 32'h0000FC00;
            end
            else if (val == 0.0) begin
                real_to_fp16 = 32'h00000000;
            end
            else begin
                sign = (val < 0);
                abs_val = sign ? -val : val;
                
                exp_val = 0;
                mant = abs_val;
                while (mant >= 2.0) begin
                    mant = mant / 2.0;
                    exp_val = exp_val + 1;
                end
                while (mant < 1.0 && exp_val > -14) begin
                    mant = mant * 2.0;
                    exp_val = exp_val - 1;
                end
                
                if (exp_val < -14) begin
                    real_to_fp16 = {16'b0, sign, 15'b0};
                end
                else if (exp_val > 15) begin
                    real_to_fp16 = sign ? 32'h0000FC00 : 32'h00007C00;
                end
                else begin
                    exp = exp_val + 15;
                    frac = $rtoi((mant - 1.0) * $pow(2.0, 10.0));
                    real_to_fp16 = {16'b0, sign, exp, frac};
                end
            end
        end
    endfunction

    // ==========================================
    // TASK PARA VERIFICAR OPERACIONES
    // ==========================================
    task test_operation;
        input [127:0] desc;
        input real val_a, val_b;
        input is_sub;
        input is_single;
        input rnd_mode;
        real expected_real;
        reg [31:0] expected_fp;
        real result_real;
        real error;
        begin
            test_num = test_num + 1;
            
            mode_fp = is_single;
            op_sel = is_sub;
            round_mode = rnd_mode;
            
            // Convertir valores a formato float
            if (is_single) begin
                op_a = real_to_fp32(val_a);
                op_b = real_to_fp32(val_b);
            end else begin
                op_a = real_to_fp16(val_a);
                op_b = real_to_fp16(val_b);
            end
            
            // Calcular resultado esperado
            if (is_sub)
                expected_real = val_a - val_b;
            else
                expected_real = val_a + val_b;
            
            if (is_single)
                expected_fp = real_to_fp32(expected_real);
            else
                expected_fp = real_to_fp16(expected_real);
            
            #10;
            
            // Convertir resultado a real para comparar
            if (is_single)
                result_real = fp32_to_real(result);
            else
                result_real = fp16_to_real(result[15:0]);
            
            $display("\n=== Test %0d: %s ===", test_num, desc);
            $display("Mode: %s | Op: %s | Round: %s", 
                     is_single ? "SINGLE" : "HALF",
                     is_sub ? "SUB" : "ADD",
                     rnd_mode ? "+INF" : "NEAR");
            $display("Input:    %.10f %s %.10f", val_a, is_sub ? "-" : "+", val_b);
            $display("Expected: %.10f (0x%h)", expected_real, expected_fp);
            $display("Got:      %.10f (0x%h)", result_real, result);
            $display("Flags:    %b", flags);
            
            // Verificar resultado (con tolerancia para redondeo)
            if (expected_real != expected_real) begin // NaN
                if (result_real != result_real) begin
                    $display("✓ PASS - NaN detected correctly");
                    pass_count = pass_count + 1;
                end else begin
                    $display("✗ FAIL - Expected NaN");
                    fail_count = fail_count + 1;
                end
            end
            else if (expected_real == 1.0/0.0 || expected_real == -1.0/0.0) begin // Inf
                if (result_real == expected_real) begin
                    $display("✓ PASS - Infinity detected correctly");
                    pass_count = pass_count + 1;
                end else begin
                    $display("✗ FAIL - Expected Infinity");
                    fail_count = fail_count + 1;
                end
            end
            else begin
                error = (result_real - expected_real);
                if (error < 0) error = -error;
                
                // Tolerancia: 1 ULP aproximadamente
                if (result == expected_fp || error < 1e-6) begin
                    $display("✓ PASS");
                    pass_count = pass_count + 1;
                end else begin
                    $display("✗ FAIL - Error: %.10e", error);
                    fail_count = fail_count + 1;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("addsub_floating.vcd");
        $dumpvars(0, tb_fpu_addsub);

        $display("\n========================================");
        $display("   FPU ADD/SUB ROBUST TESTBENCH");
        $display("========================================");

        // ==========================================
        // SINGLE PRECISION TESTS
        // ==========================================
        $display("\n--- SINGLE PRECISION BASIC OPERATIONS ---");
        test_operation("1.0 + 2.0", 1.0, 2.0, 0, 1, 0);
        test_operation("5.0 - 3.0", 5.0, 3.0, 1, 1, 0);
        test_operation("1.0 + 0.5", 1.0, 0.5, 0, 1, 0);
        test_operation("2.5 - 2.5", 2.5, 2.5, 1, 1, 0);
        test_operation("0.1 + 0.2", 0.1, 0.2, 0, 1, 0);
        test_operation("10.5 + 20.25", 10.5, 20.25, 0, 1, 0);
        
        $display("\n--- SINGLE PRECISION NEGATIVE NUMBERS ---");
        test_operation("-1.0 + -2.0", -1.0, -2.0, 0, 1, 0);
        test_operation("3.0 + -1.0", 3.0, -1.0, 0, 1, 0);
        test_operation("-5.0 - -3.0", -5.0, -3.0, 1, 1, 0);
        test_operation("1.0 - 2.0", 1.0, 2.0, 1, 1, 0);
        
        $display("\n--- SINGLE PRECISION SMALL/LARGE VALUES ---");
        test_operation("0.00001 + 0.00002", 0.00001, 0.00002, 0, 1, 0);
        test_operation("1000.0 + 2000.0", 1000.0, 2000.0, 0, 1, 0);
        test_operation("1e10 + 1e10", 1.0e10, 1.0e10, 0, 1, 0);
        
        $display("\n--- SINGLE PRECISION SPECIAL CASES ---");
        test_operation("0.0 + 0.0", 0.0, 0.0, 0, 1, 0);
        test_operation("1.0 + 0.0", 1.0, 0.0, 0, 1, 0);
        test_operation("0.0 - 0.0", 0.0, 0.0, 1, 1, 0);
        
        // ==========================================
        // HALF PRECISION TESTS
        // ==========================================
        $display("\n--- HALF PRECISION BASIC OPERATIONS ---");
        test_operation("HALF: 1.0 + 2.0", 1.0, 2.0, 0, 0, 0);
        test_operation("HALF: 3.0 - 1.0", 3.0, 1.0, 1, 0, 0);
        test_operation("HALF: 1.0 + 0.5", 1.0, 0.5, 0, 0, 0);
        test_operation("HALF: 4.0 + 4.0", 4.0, 4.0, 0, 0, 0);
        
        $display("\n--- HALF PRECISION NEGATIVE NUMBERS ---");
        test_operation("HALF: -1.0 + -2.0", -1.0, -2.0, 0, 0, 0);
        test_operation("HALF: 2.0 - 3.0", 2.0, 3.0, 1, 0, 0);
        
        $display("\n--- HALF PRECISION SMALL VALUES ---");
        test_operation("HALF: 0.5 + 0.25", 0.5, 0.25, 0, 0, 0);
        test_operation("HALF: 0.1 + 0.1", 0.1, 0.1, 0, 0, 0);
        
        // ==========================================
        // RESUMEN
        // ==========================================
        $display("\n========================================");
        $display("   TEST SUMMARY");
        $display("========================================");
        $display("Total tests:  %0d", test_num);
        $display("Passed:       %0d", pass_count);
        $display("Failed:       %0d", fail_count);
        $display("Success rate: %.1f%%", (pass_count * 100.0) / test_num);
        $display("========================================\n");
        
        if (fail_count == 0)
            $display("🎉 ALL TESTS PASSED! 🎉");
        else
            $display("⚠️  SOME TESTS FAILED");
        
        $finish;
    end

endmodule
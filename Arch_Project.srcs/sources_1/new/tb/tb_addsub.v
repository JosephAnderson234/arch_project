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

    // Task para mostrar resultados y verificar
    task display_test;
        input [127:0] desc;
        input [31:0] expected_result;
        input [4:0]  expected_flags;
        begin
            test_num = test_num + 1;
            $display("\n=== Test %0d: %s ===", test_num, desc);
            $display("Mode: %s | Op: %s | Round: %s", 
                     mode_fp ? "SINGLE" : "HALF",
                     op_sel ? "SUB" : "ADD",
                     round_mode ? "+INF" : "NEAR");
            $display("A = %h | B = %h", op_a, op_b);
            #5;
            $display("Result = %h | Expected = %h", result, expected_result);
            $display("Flags  = %b | Expected = %b", flags, expected_flags);
            if (result === expected_result && flags === expected_flags) begin
                $display("PASS");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL");
            end
        end
    endtask

    initial begin
        $dumpfile("addsub_floating.vcd");
        $dumpvars(0, tb_fpu_addsub);

        $display("======================================");
        $display("   FPU ADD/SUB TESTBENCH");
        $display("======================================");

        // =========================
        // TESTS DEFINIDOS
        // =========================
        // SINGLE PRECISION
        mode_fp = 1;
        round_mode = 0;
        
        op_sel = 0; op_a = 32'h3F800000; op_b = 32'h40000000; display_test("1.0 + 2.0", 32'h40e00000, 5'b00000);
        op_sel = 1; op_a = 32'h40A00000; op_b = 32'h40400000; display_test("5.0 - 3.0", 32'h40c00000, 5'b00000);
        op_sel = 0; op_a = 32'h3F800000; op_b = 32'h3F000000; display_test("1.0 + 0.5", 32'h40600000, 5'b00000);
        op_sel = 1; op_a = 32'h40200000; op_b = 32'h40200000; display_test("2.5 - 2.5", 32'h00000000, 5'b01000);
        op_sel = 0; op_a = 32'hBF800000; op_b = 32'hC0000000; display_test("-1.0 + -2.0", 32'hC0E00000, 5'b00000);
        op_sel = 0; op_a = 32'h40400000; op_b = 32'hBF800000; display_test("3.0 + -1.0", 32'h40C00000, 5'b00000);
        op_sel = 0; op_a = 32'h7FC00000; op_b = 32'h3F800000; display_test("NaN + 1.0", 32'h7FC00000, 5'b00010);
        op_sel = 0; op_a = 32'h7F800000; op_b = 32'h40000000; display_test("+Inf + 2.0", 32'h7F800000, 5'b00000);
        op_sel = 1; op_a = 32'h7F800000; op_b = 32'h7F800000; display_test("+Inf - +Inf", 32'h7FC00000, 5'b00010);
        op_sel = 0; op_a = 32'h00000000; op_b = 32'h00000000; display_test("0.0 + 0.0", 32'h00000000, 5'b00000);
        op_sel = 0; round_mode = 1; op_a = 32'h3F800000; op_b = 32'h33800000; display_test("Rounding toward +Inf", 32'h40400000, 5'b00001);
        op_sel = 0; round_mode = 0; op_a = 32'h7F000000; op_b = 32'h7F000000; display_test("Overflow test", 32'h7F800000, 5'b10000);

        // HALF PRECISION
        mode_fp = 0; round_mode = 0;
        op_sel = 0; op_a = 32'h00003C00; op_b = 32'h00004000; display_test("HALF 1.0 + 2.0", 32'h00004700, 5'b00000);
        op_sel = 1; op_a = 32'h00004200; op_b = 32'h00003C00; display_test("HALF 3.0 - 1.0", 32'h00004600, 5'b00000);
        op_sel = 0; op_a = 32'h00003C00; op_b = 32'h00003800; display_test("HALF 1.0 + 0.5", 32'h00004300, 5'b00000);
        op_sel = 0; op_a = 32'h0000BC00; op_b = 32'h0000C000; display_test("HALF -1.0 + -2.0", 32'h0000C700, 5'b00000);
        op_sel = 0; op_a = 32'h00007E00; op_b = 32'h00003C00; display_test("HALF NaN + 1.0", 32'h00007E00, 5'b00010);
        op_sel = 0; op_a = 32'h00007C00; op_b = 32'h00004000; display_test("HALF +Inf + 2.0", 32'h00007C00, 5'b00000);
        op_sel = 0; round_mode = 1; op_a = 32'h00003C00; op_b = 32'h00000400; display_test("HALF Rounding toward +Inf", 32'h00004200, 5'b00000);
        op_sel = 0; round_mode = 0; op_a = 32'h00000400; op_b = 32'h00000400; display_test("HALF Underflow test", 32'h00000E00, 5'b00000);

        // CORNER CASES SINGLE
        mode_fp = 1; round_mode = 0;
        op_sel = 0; op_a = 32'h00000001; op_b = 32'h00000001; display_test("SINGLE Denormal + Denormal", 32'h00000002, 5'b01000);
        op_sel = 0; op_a = 32'h7F7FFFFF; op_b = 32'h00800000; display_test("SINGLE Max + Min", 32'h7F800000, 5'b10000);
        op_sel = 1; op_a = 32'h3F800000; op_b = 32'h40000000; display_test("SINGLE 1.0 - 2.0 = -1.0", 32'hC0400000, 5'b00000);
        op_sel = 1; op_a = 32'h3F800000; op_b = 32'h34000000; display_test("SINGLE Nearest even edge", 32'h3FFFFFFF, 5'b00000);

        $display("\n======================================");
        $display("Tests completados: %0d / 24", pass_count);
        $display("======================================");
        $finish;
    end

endmodule

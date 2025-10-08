`timescale 1ns/1ps

module tb_input_loader_dual();
    reg clk = 0, rst = 0, load_btn = 0, mode_fp = 0;
    reg [3:0] nibbleA = 0, nibbleB = 0;
    wire [31:0] op_a, op_b;
    wire load_done, loading_a;
    wire [3:0] nibble_count;

    input_loader_dual uut (
        .clk(clk), .rst(rst), .load_btn(load_btn),
        .mode_fp(mode_fp), .nibbleA(nibbleA), .nibbleB(nibbleB),
        .op_a(op_a), .op_b(op_b),
        .load_done(load_done), .loading_a(loading_a), .nibble_count(nibble_count)
    );

    always #5 clk = ~clk;

    task pulse_btn; begin
        load_btn = 1; #10; load_btn = 0; #10;
    end endtask

    initial begin
      $dumpfile("input_loading.vcd");
        $dumpvars(0, tb_input_loader_dual);
        $display("=== Test: modo half (16 bits) ===");
        rst = 1; #10; rst = 0; mode_fp = 0;
        repeat (4) begin
            nibbleA = $random; nibbleB = $random;
            pulse_btn();
        end
        repeat (4) begin
            nibbleA = $random; nibbleB = $random;
            pulse_btn();
        end
        #20;

        $display("=== Test: modo single (32 bits) ===");
        rst = 1; #10; rst = 0; mode_fp = 1;
        repeat (8) begin
            nibbleA = $random; nibbleB = $random;
            pulse_btn();
        end
        repeat (8) begin
            nibbleA = $random; nibbleB = $random;
            pulse_btn();
        end
        #20 $finish;
    end
endmodule

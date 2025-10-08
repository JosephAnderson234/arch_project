`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/08/2025 10:20:55 AM
// Design Name: 
// Module Name: tb_div_min
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


module tb_div_min;
  // reloj y reset
  reg clk = 0;
  reg rst = 1;

  // entradas
  reg        start = 0;
  reg [31:0] A = 32'd0;   // dividendo
  reg [31:0] B = 32'd0;   // divisor

  // salidas
  wire [31:0] Y;
  wire        V;
  wire [4:0]  F; // {invalid, div_by_zero, overflow, underflow, inexact}

  // DUT
  fpu_div_fp32_vivado dut (
    .clk(clk), .rst(rst), .start(start),
    .a(A), .b(B), .result(Y), .valid_out(V), .flags(F)
  );

  // reloj 100 MHz
  always #5 clk = ~clk;

  initial begin
    // reset
    repeat (4) @(negedge clk);
    rst = 0;

    // 1) 7 / 2 = 3.5  (0x40E00000 / 0x40000000 -> 0x40600000)
    A = 32'h40E00000; B = 32'h40000000;
    @(negedge clk) start = 1; @(negedge clk) start = 0;
    @(posedge clk); #1
    $display("1) 7/2 -> Y=%h flags=%b (esperado 40600000)", Y, F);

    // 2) 1 / 0 -> +Inf, div_by_zero=1
    A = 32'h3F800000; B = 32'h00000000;
    @(negedge clk) start = 1; @(negedge clk) start = 0;
    @(posedge clk); #1
    $display("2) 1/0 -> Y=%h flags=%b (Inf, dz=1)", Y, F);

    // 3) 0 / 5 -> 0
    A = 32'h00000000; B = 32'h40A00000;
    @(negedge clk) start = 1; @(negedge clk) start = 0;
    @(posedge clk); #1
    $display("3) 0/5 -> Y=%h flags=%b (0)", Y, F);

    // 4) Inf / 2 -> Inf
    A = 32'h7F800000; B = 32'h40000000;
    @(negedge clk) start = 1; @(negedge clk) start = 0;
    @(posedge clk); #1
    $display("4) Inf/2 -> Y=%h flags=%b (Inf)", Y, F);

    // 5) 6 / Inf -> 0
    A = 32'h40C00000; B = 32'h7F800000;
    @(negedge clk) start = 1; @(negedge clk) start = 0;
    @(posedge clk); #1
    $display("5) 6/Inf -> Y=%h flags=%b (0)", Y, F);

    // 6) 0 / 0 -> NaN (invalid)
    A = 32'h00000000; B = 32'h00000000;
    @(negedge clk) start = 1; @(negedge clk) start = 0;
    @(posedge clk); #1
    $display("6) 0/0 -> Y=%h flags=%b (NaN, invalid=1)", Y, F);

    // 7) Inf / Inf -> NaN (invalid)
    A = 32'h7F800000; B = 32'h7F800000;
    @(negedge clk) start = 1; @(negedge clk) start = 0;
    @(posedge clk); #1
    $display("7) Inf/Inf -> Y=%h flags=%b (NaN, invalid=1)", Y, F);

    // 8) 1 / 3 -> ~0x3EAAAAAB (inexact=1 por redondeo)
    A = 32'h3F800000; B = 32'h40400000;
    @(negedge clk) start = 1; @(negedge clk) start = 0;
    @(posedge clk); #1
    $display("8) 1/3 -> Y=%h flags=%b (~3EAAAAAB, inexact=1)", Y, F);

    #20 $stop;
  end
endmodule

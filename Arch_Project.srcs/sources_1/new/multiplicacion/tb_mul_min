`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/08/2025 10:30:49 AM
// Design Name: 
// Module Name: tb_mul_min
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

`timescale 1ns/1ps

module tb_mul_min;
  // reloj y reset
  reg clk = 0;
  reg rst = 1;

  // entradas al DUT (deben ser reg en TB)
  reg        start = 0;
  reg [31:0] A = 32'd0;
  reg [31:0] B = 32'd0;

  // salidas del DUT (wire en TB)
  wire [31:0] Y;
  wire        V;
  wire [4:0]  F;

  // reloj 100 MHz
  always #5 clk = ~clk;

  // instanciar tu módulo
  fpu_mul_fp32_vivado dut (
    .clk(clk),
    .rst(rst),
    .start(start),
    .a(A),
    .b(B),
    .result(Y),
    .valid_out(V),
    .flags(F)
  );

  initial begin
    // 1) reset
    repeat (4) @(negedge clk);
    rst = 0;

    // 2) vector 1: 1.5 * 2.5 = 3.75
    //    1.5  = 0x3FC00000
    //    2.5  = 0x40200000
    //    3.75 = 0x40700000 (esperado)
    A = 32'h3FC00000;  // 1.5
    B = 32'h40200000;  // 2.5
    @(negedge clk); start = 1'b1;
    @(negedge clk); start = 1'b0;
    @(posedge clk);  // el DUT entrega al ciclo siguiente
    #1 $display("1) 1.5*2.5 -> Y=%h  flags=%b  (esperado 40700000)", Y, F);

    // 3) vector 2: 0 * 5.0 = 0
    A = 32'h00000000;  // 0.0
    B = 32'h40A00000;  // 5.0
    @(negedge clk); start = 1'b1;
    @(negedge clk); start = 1'b0;
    @(posedge clk);
    #1 $display("2) 0*5.0   -> Y=%h  flags=%b  (esperado 00000000)", Y, F);

    // 4) vector 3: Inf * 2.0 = Inf
    A = 32'h7F800000;  // +Inf
    B = 32'h40000000;  // 2.0
    @(negedge clk); start = 1'b1;
    @(negedge clk); start = 1'b0;
    @(posedge clk);
    #1 $display("3) Inf*2.0 -> Y=%h  flags=%b  (esperado 7F800000)", Y, F);

    // 5) vector 4: 0 * Inf = NaN (invalid=1)
    A = 32'h00000000;  // 0.0
    B = 32'h7F800000;  // +Inf
    @(negedge clk); start = 1'b1;
    @(negedge clk); start = 1'b0;
    @(posedge clk);
    #1 $display("4) 0*Inf   -> Y=%h  flags=%b  (NaN, invalid=1)", Y, F);

    // fin
    #20 $stop;
  end
endmodule

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10.10.2025 00:04:02
// Design Name: 
// Module Name: tb_fpu_top
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


module tb_fpu_top;
reg clk;
reg rst;
reg [31:0] op_a;
reg [31:0] op_b;
reg [1:0] op_code; // 00=add,01=sub,10=mul,11=div
reg mode_fp; // 0=half,1=single
reg [1:0] round_mode; // 00=RNE
reg start;
wire [31:0] result;
wire valid_out;
wire [4:0] flags;


// CLK 100 MHz
initial clk = 0;
always #5 clk = ~clk; // 10ns → 100MHz


fpu_top dut (
.clk(clk), .rst(rst), .op_a(op_a), .op_b(op_b), .op_code(op_code),
.mode_fp(mode_fp), .round_mode(round_mode), .start(start),
.result(result), .valid_out(valid_out), .flags(flags)
);


// ---------------------------------------------
// Estímulos
// ---------------------------------------------
task pulse_start; begin
start = 1'b1; @(posedge clk); start = 1'b0;
end endtask


initial begin
// Opcional: activa stubs si aún no existieran módulos reales
//`define USE_DUMMY_DP


rst = 1; start = 0; op_a = 0; op_b = 0; op_code = 2'b00; mode_fp = 1; round_mode = 2'b00;
repeat(5) @(posedge clk);
rst = 0;


// Caso 1: ADD (stub: suma entera)
op_a = 32'h3F800000; // 1.0f (solo simbólico en stub)
op_b = 32'h40000000; // 2.0f
op_code = 2'b00; // add
pulse_start();
@(posedge clk); @(posedge clk);
$display("ADD: result=%h valid=%0d flags=%b", result, valid_out, flags);


// Caso 2: SUB (stub: resta entera)
op_a = 32'h0000000A; // 10
op_b = 32'h00000003; // 3
op_code = 2'b01; // sub
pulse_start();
@(posedge clk); @(posedge clk);


// Caso 3: MUL (stub: mul entera)
op_a = 32'h00000005; // 5
op_b = 32'h00000006; // 6
op_code = 2'b10; // mul
pulse_start();
@(posedge clk); @(posedge clk);


// Caso 4: DIV (stub: div entera con check div0)
op_a = 32'h0000000C; // 12
op_b = 32'h00000003; // 3
op_code = 2'b11; // div
pulse_start();
@(posedge clk); @(posedge clk);


$display("Tests completos.");
#50 $finish;
end
endmodule

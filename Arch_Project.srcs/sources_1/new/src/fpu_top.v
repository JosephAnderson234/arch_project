`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.10.2025 10:53:13
// Design Name: 
// Module Name: fpu_top
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


module fpu_top (
input clk,
input rst,
input [31:0] op_a,
input [31:0] op_b,
input [1:0] op_code, // 00=add, 01=sub, 10=mul, 11=div
input mode_fp, // 0=half, 1=single
input [1:0] round_mode, // 00 = nearest even (único soportado por ahora)
input start, // pulso de 1 ciclo para iniciar
output [31:0] result,
output valid_out,
output [4:0] flags // {overflow, underflow, div0, invalid, inexact}
);
// ------------------------------
// Señales internas
// ------------------------------
localparam IDLE = 3'd0;
localparam LOAD = 3'd1;
localparam EXECUTE = 3'd2;
localparam ROUND = 3'd3;
localparam DONE = 3'd4;


reg [2:0] state, state_n;
reg [31:0] opa_r, opb_r; // latched inputs
reg [1:0] opcode_r;
reg mode_r;
reg [1:0] rmode_r;


// Salidas registradas
reg [31:0] result_r;
reg [4:0] flags_r;
reg valid_r;


assign result = result_r;
assign flags = flags_r;
assign valid_out = valid_r;


// ------------------------------
// Selección de datapath
// ------------------------------
wire use_addsub = (opcode_r[1:0] <= 2'b01);


// Resultados de submódulos
wire [31:0] res_addsub;
wire [4:0] flg_addsub;


wire [31:0] res_muldiv;
wire [4:0] flg_muldiv;
wire v_muldiv;


// Instancia ADD/SUB (combinacional)
fpu_addsub u_addsub (
.op_a(opa_r),
.op_b(opb_r),
.op_sel(opcode_r[0]), // 0=add, 1=sub
.mode_fp(mode_r),
.round_mode(rmode_r[0]), // usamos bit0: 0=RNE,1=+inf
.result(res_addsub),
.flags(flg_addsub)
);


// Instancia MUL/DIV (secuencial con start/valid)
fpu_muldiv u_muldiv (
.clk(clk),
.rst(rst),
.start(state==EXECUTE && !use_addsub),
.op_a(opa_r),
.op_b(opb_r),
.op_sel(opcode_r[0]), // 0=mul, 1=div
.mode_fp(mode_r),
.round_mode(rmode_r),
.result(res_muldiv),
.flags(flg_muldiv),
.valid_out(v_muldiv)
);


wire [31:0] res_sel = use_addsub ? res_addsub : res_muldiv;
wire [4:0] flags_sel = use_addsub ? flg_addsub : flg_muldiv;
wire v_ready = use_addsub ? 1'b1 : v_muldiv;


// ------------------------------
// FSM secuencial
// ------------------------------
always @(posedge clk or posedge rst) begin
if (rst) begin
state <= IDLE;
opa_r <= 32'd0;
opb_r <= 32'd0;
opcode_r <= 2'd0;
opcode_r <= 2'd0;
mode_r <= 1'b1; // por defecto single
rmode_r <= 2'b00; // RNE
result_r <= 32'd0;
flags_r <= 5'd0;
valid_r <= 1'b0;
end else begin
state <= state_n;


// Pulso de valid sólo en DONE
if (state == DONE)
valid_r <= 1'b1;
else
valid_r <= 1'b0;


// Latch de resultado/flags al entrar a ROUND
if (state == ROUND) begin
result_r <= res_sel; // los submódulos ya deben venir redondeados
flags_r <= flags_sel;
end
end
end


// ------------------------------
// FSM combinacional
// ------------------------------
always @* begin
state_n = state;
case (state)
IDLE: begin
if (start) state_n = LOAD;
end
LOAD: begin
state_n = EXECUTE;
end
EXECUTE: begin
// add/sub: listo en el mismo ciclo; mul/div: esperar valid
if (use_addsub) state_n = ROUND;
else if (v_ready) state_n = ROUND;
end
ROUND: begin
state_n = DONE;
end
DONE: begin
state_n = IDLE;
end
default: state_n = IDLE;
endcase
end


// Latch de entradas en LOAD
always @(posedge clk) begin
if (state == IDLE && start) begin
opa_r <= op_a;
opb_r <= op_b;
opcode_r <= op_code;
mode_r <= mode_fp;
rmode_r <= round_mode;
end
end
endmodule
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.10.2025 10:39:53
// Design Name: 
// Module Name: fp_alu_top
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


module fp_alu_top (
input wire clk100,
input wire btnC, // reset síncrono activo en alto
input wire btnU, // botón de carga/start
input wire [15:0] sw, // switches
output wire [15:0] led, // leds
output wire [6:0] seg,
output wire dp,
output wire [3:0] an
);
wire rst = btnC;


// ---------------------------------
// Modo y operación desde switches
// ---------------------------------
// sw[1:0] = op_code (00 add, 01 sub, 10 mul, 11 div)
// sw[2] = mode_fp (0 half, 1 single)
// sw[4:3] = round_mode (00 = RNE)
wire [1:0] op_code = sw[1:0];
wire mode_fp = sw[2];
wire [1:0] round_mode = sw[4:3];


// ---------------------------------
// Carga nibbles con un único botón
// Se asume: sw[7:4] = nibbleA, sw[11:8] = nibbleB (puedes re-mapear)
// ---------------------------------
// Se asume: sw[7:4] = nibbleA, sw[11:8] = nibbleB (puedes re-mapear)
// ---------------------------------
wire [3:0] nibbleA = sw[7:4];
wire [3:0] nibbleB = sw[11:8];


wire [31:0] op_a, op_b;
wire load_done;
wire loading_a;
wire [3:0] nib_cnt;


input_loader_dual u_loader (
.clk(clk100),
.rst(rst),
.load_btn(btnU),
.nibbleA(nibbleA),
.nibbleB(nibbleB),
.op_a(op_a),
.op_b(op_b),
.load_done(load_done),
.loading_a(loading_a),
.nibble_count(nib_cnt)
);


// ---------------------------------
// Arranque de operación: reusa el mismo btnU una vez que load_done=1
// Generamos un pulso start en el flanco de btnU posterior a load_done
// ---------------------------------
reg load_done_d;
always @(posedge clk100 or posedge rst) begin
if (rst) load_done_d <= 1'b0; else load_done_d <= load_done;
end


// Edge detector de btnU
reg btnU_d;
always @(posedge clk100 or posedge rst) begin
if (rst) btnU_d <= 1'b0; else btnU_d <= btnU;
end
wire btnU_rise = btnU & ~btnU_d;


reg armed; // se arma cuando load_done sube por primera vez
always @(posedge clk100 or posedge rst) begin
if (rst) armed <= 1'b0;
else if (load_done & ~load_done_d) armed <= 1'b1; // nuevo paquete listo
else if (btnU_rise && armed) armed <= 1'b0; // consume start
end


wire start_pulse = btnU_rise & armed;
// ---------------------------------
// Instancia de FPU top
// ---------------------------------
wire [31:0] result;
wire valid_out;
wire [4:0] flags;


fpu_top u_fpu (
.clk(clk100),
.rst(rst),
.op_a(op_a),
.op_b(op_b),
.op_code(op_code),
.mode_fp(mode_fp),
.round_mode(round_mode),
.start(start_pulse),
.result(result),
.valid_out(valid_out),
.flags(flags)
);


// ---------------------------------
// Salidas a LEDs y 7 segmentos
// ---------------------------------
// led[4:0] = flags; led[5] = valid_out; led[6] = loading_a; led[7] = load_done
// resto: opcionalmente lower result bits
assign led[4:0] = flags;
assign led[5] = valid_out;
assign led[6] = loading_a;
assign led[7] = load_done;
assign led[15:8] = result[7:0];


// Mostrar result[15:0] en 4 dígitos HEX
sevenseg_driver #(.INPUT_CLK_HZ(100_000_000)) u_7seg (
.clk(clk100),
.rst(rst),
.value(result[15:0]),
.seg(seg),
.dp(dp),
.an(an)
);
endmodule
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.10.2025 10:40:22
// Design Name: 
// Module Name: sevenseg_driver
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


module sevenseg_driver #(
    parameter integer INPUT_CLK_HZ = 100_000_000,
    parameter integer DIGIT_HZ     = 1000  // no se usa en esta versión, se deja por compatibilidad
)(
    input  wire        clk,
    input  wire        rst,        // activo en alto
    input  wire [15:0] value,      // [15:12]|[11:8]|[7:4]|[3:0]
    output reg  [6:0]  seg,        // {a,b,c,d,e,f,g} activo en bajo
    output reg         dp,         // activo en bajo
    output reg  [3:0]  an          // activo en bajo (0 enciende)
);
    // -------------------------------
    // Contador de refresco
    // -------------------------------
    reg [17:0] refresh_cnt = 18'd0;  // 100 MHz / 2^18 ≈ 381 Hz por estado
    wire [1:0] sel = refresh_cnt[17:16];

    always @(posedge clk) begin
        if (rst)
            refresh_cnt <= 18'd0;
        else
            refresh_cnt <= refresh_cnt + 1'b1;
    end

    // -------------------------------
    // Selección de nibble
    // -------------------------------
    reg [3:0] nibble_r;
    always @(posedge clk) begin
        if (rst) begin
            nibble_r <= 4'h0;
        end else begin
            case (sel)
                2'd0: nibble_r <= value[3:0];     // dígito derecho
                2'd1: nibble_r <= value[7:4];
                2'd2: nibble_r <= value[11:8];
                2'd3: nibble_r <= value[15:12];   // dígito izquierdo
            endcase
        end
    end

    // -------------------------------
    // Decoder HEX -> 7 segmentos (CA)
    // -------------------------------
    function [6:0] hex_to_seg_ca;
        input [3:0] x;
        begin
            case (x)
                4'h0: hex_to_seg_ca = 7'b1000000;
                4'h1: hex_to_seg_ca = 7'b1111001;
                4'h2: hex_to_seg_ca = 7'b0100100;
                4'h3: hex_to_seg_ca = 7'b0110000;
                4'h4: hex_to_seg_ca = 7'b0011001;
                4'h5: hex_to_seg_ca = 7'b0010010;
                4'h6: hex_to_seg_ca = 7'b0000010;
                4'h7: hex_to_seg_ca = 7'b1111000;
                4'h8: hex_to_seg_ca = 7'b0000000;
                4'h9: hex_to_seg_ca = 7'b0010000;
                4'hA: hex_to_seg_ca = 7'b0001000;
                4'hB: hex_to_seg_ca = 7'b0000011;
                4'hC: hex_to_seg_ca = 7'b1000110;
                4'hD: hex_to_seg_ca = 7'b0100001;
                4'hE: hex_to_seg_ca = 7'b0000110;
                4'hF: hex_to_seg_ca = 7'b0001110;
            endcase
        end
    endfunction

    // -------------------------------
    // Salidas registradas
    // -------------------------------
    always @(posedge clk) begin
        if (rst) begin
            seg <= 7'b1111111;  // todo apagado
            dp  <= 1'b1;        // apagado
            an  <= 4'b1111;     // todos los dígitos apagados
        end else begin
            seg <= hex_to_seg_ca(nibble_r);
            dp  <= 1'b1;

            // one-hot activo en bajo
            case (sel)
                2'd0: an <= 4'b1110; // D0 (derecha)
                2'd1: an <= 4'b1101; // D1
                2'd2: an <= 4'b1011; // D2
                2'd3: an <= 4'b0111; // D3 (izquierda)
            endcase
        end
    end
endmodule


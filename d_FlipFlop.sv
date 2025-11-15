`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/08/2025 08:12:13 PM
// Design Name: 
// Module Name: d_FlipFlop
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


module d_FlipFlop(
    input clk_in,
    input D,
    output reg Q,
    output reg Q_bar

    );
    
    always_ff @(posedge clk_in)
    begin
      Q <= D;
      Q_bar <= ~Q;
    end 
    
    
endmodule

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/08/2025 08:06:16 PM
// Design Name: 
// Module Name: slow_clock
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


module slow_clock(
    input logic clock_in,
    output logic clock_out

    );
    
    reg [26:0] count = 0;
    
    
    always_ff @(posedge clock_in)
    begin
      count <= count + 1;
      //if (count == 125000000) - 4 Hz clock 
      if (count == 50000) //- 2 Khz clock
      begin 
        count <= 0;
        clock_out <= ~clock_out;
      end 
    end
endmodule

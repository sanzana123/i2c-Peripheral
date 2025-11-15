`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/04/2025 05:56:30 PM
// Design Name: 
// Module Name: fifo
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


module fifo(
 // indexes are 4 bit long because only 4 bits - 1111 are enough to indentify each value in the slot of the fifo   
    
    input clk,
    input reset,
    input [7:0] wr_data,
    input wr_request,
    output reg [7:0] rd_data,
    input rd_request,
    output empty,
    output full,
    output reg overflow,
    input clear_overflow_request,
    output reg [3:0] wr_index,
    output reg [3:0] rd_index
    //input mode
    

    );
    
    logic [7:0] fifo_slot[15:0];
   
    
    // full and empty are combinational logic. Does not depend on the clock
    assign full = ((wr_index + 1) % 16) == rd_index;
    assign empty = (rd_index == wr_index);
    assign rd_data = fifo_slot[rd_index];
   
    
    
    always_ff @(posedge clk)
    begin
      if (reset)
      begin 
        wr_index <= 0;
        rd_index <= 0;
        overflow <= 0;
      end 
    
      else if (clear_overflow_request)
      begin
        overflow <= 0;
      end 
    
      else if(wr_request)
      begin 
        if (!full)
        begin
          fifo_slot[wr_index] <= wr_data;
          wr_index <= wr_index + 1;
        end 
        
        else 
        begin 
          overflow <= 1;
        end 
      end
      
      else if (rd_request)
      begin 
        if (!empty)
        begin 
         // rd_data <= fifo_slot[rd_index];
          rd_index <= rd_index + 1;
        end 
      end
        
    end 
    
    
      
      
endmodule

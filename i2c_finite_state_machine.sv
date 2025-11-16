`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/09/2025 01:14:23 PM
// Design Name: 
// Module Name: i2c_finite_state_machine
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


module i2c_finite_state_machine(


    input axi_clk, // will take in the CLK100
    input axi_resetn, // will take in the axi reset 
    input [31:0]address_reg, // will take the address of device
    input [31:0] register_reg, // will take the address of a specific register within the device 
    input [31:0] data_from_fifo, // will take data and put in 
    output reg [31:0] status_reg, // will take in the bits of the status_register 
    
    output reg clear_start_request,
    
    output reg read_request,
    
    //Bits of control_register - When instantiating this fsm in the axi file, in each one of their ports do, 
    input logic read_write, //read = 1, write = 0, .read_write(control_reg[0])
    input logic [3:0] byte_count, // keeps track of how many bytes have been sent or received, .byte_count(control_reg[4:1]) 
    input logic use_register,     // 1 = if a register is used, 0 = if no register is being used, .use_register(control_reg[5])
    input logic use_repeated_start, // 1 = use repeated start, 0 = regular start, .use_repeated_start(control_reg[6])
    input logic start,              // .start(control_reg[7])
    input logic test_out, // 1 = enable test out, 0 = disable test out, .test_out(control_reg[8]) 
    input logic [7:0] debug_out, 
    
    output reg scl_line, 
    output reg sda_line_out, // used for writing to the sda line
    input wire sda_line_in // used for reading from the sda line 
    
 );

// Create the 200 khz clock from the 100 Mhz clock(axi_clk)
  reg [26:0] clock_count = 0;
  logic clock_out;
  
  wire clk200Khz;

  always_ff @(posedge axi_clk)
  begin 
    //clock_count <= clock_count + 1; 
  
    if (clock_count == 499)
    begin
      clock_out <= 1'b1;
      clock_count <= 0;
    end
    else
    begin
      clock_out <= 1'b0;
      clock_count <= clock_count + 1'b1;
    end
  end 
  
  assign clk200Khz = clock_out;


///////////////////////////////////////////////Start the i2c fsm interface/////////////////////////////////////////////
    
    reg [2:0] state;
    reg [4:0] phase;
    reg [31:0] byte_index;

    parameter IDLE = 3'd0;
    parameter START = 3'd1;
    parameter SEND_DEVICE_ADDRESS = 3'd2;
    parameter SEND_REGISTER_ADDRESS = 3'd3;
    parameter TRANSMIT_DATA = 3'd4;
    parameter SEND_STOP = 3'd5;
    
    logic clk200Khz_d;
    logic scl_enable_rise;
    reg [2:0] bit_index;
    
    reg [1:0] ack_flag;  // 0 = shifting, 1 = just finished last bit, 2 = waiting to sample
    reg ack_error;
    reg [2:0] bit_index_transmit;
    logic [3:0] bytes_internal;
    
    
    
    
    //logic drive_sda_out;
    //logic drive_sda_in;
    //logic drive_scl;
    
//    assign sda_line_out = drive_sda_out? 1'bz: 1'b0; 
//    assign sda_line_in = drive_sda_in? 1'bz: 1'b0;
//    assign scl_line = drive_scl? 1'bz: 1'b0;
    
    
    logic [7:0] complete_device_address;
    //logic [7:0] complete_transmit_data;
    //logic [7:0] complete_register_address;
    
    assign complete_device_address = {address_reg[6:0], read_write};
    //assign complete_transmit_data = {data_from_fifo[7:0]};
    //assign complete_register_address = {register_reg[7:0]};
    
        
    always_ff @(posedge axi_clk)
    begin 
      if (!axi_resetn)
      begin
        clk200Khz_d <= 1'b0;
        scl_enable_rise<=1'b0;
        state <= IDLE;
        phase <= 1'b0;
        scl_line <= 1'b1;
        ack_flag <= 2'd1;
        
        sda_line_out <= 1'b1;   // released by default
        bit_index <= 3'd7;  
        bit_index_transmit <= 3'd7;
 
      end
     // else 
//      begin
//        clk200Khz_d <= clk200Khz;
//      end
      
      // All reads and writes will take place at the rising edge of 200 khz clock 
         // Writes on even edges, Reads on odd edges 
      else if (clk200Khz)
      begin 
        
        // 100Khz clock 
        // Only toggle when we are not at the START and STOP condition 
        
        // increment the phase at every state and as you transition from one state to another, make the phase 0
        
        //start <= 1'b1;
        read_request <= 1'b0;
        phase <= phase + 1;
        
        case (state)
          IDLE, START, SEND_STOP:
             scl_line <= 1'b1;             // Keep SCL high in these states

          SEND_DEVICE_ADDRESS, SEND_REGISTER_ADDRESS, TRANSMIT_DATA:
             scl_line <= phase[0];         
        endcase
        
        case (state)
          IDLE:
          begin
            scl_line <= 1'b1;
            sda_line_out <= 1'b1;
          
            if (start)
            begin
                state <= START;
                status_reg[7] <= 1'b1; //busy bit of status reg
                phase <= 1'b0;
                clear_start_request <= 1'b1;
                bytes_internal <= byte_count;
            end
          end 
          
          START:
          begin 
            bit_index <= 3'd7;
            ack_flag <= 2'd0;
           // scl_line <= 1'b1;
            clear_start_request <= 1'b0;
            sda_line_out <= 1'b0;
            if (phase == 3'd3)
            begin
              phase <= 1'b0;
              state <= SEND_DEVICE_ADDRESS;
            end
          end 
          
          SEND_DEVICE_ADDRESS:
          begin
            // Write data 
         //   scl_line <= ~ scl_line;
            
            if ((phase[0] == 1'b0) && (phase <= 5'd14))
            begin 
              //phase <= phase + 1'b1;
              
              sda_line_out <= (complete_device_address[bit_index]== 1'b1)? 1'b1: 1'b0;
              if (bit_index != 3'd0)
              begin
                bit_index <= bit_index - 3'b1;
              end  
            end
            
            else if (phase == 5'd16)
            begin
              //phase <= phase + 1'b1;
              sda_line_out <= 1'b1;
            end
            
            else if (phase == 5'd17)
            begin
              //phase <= 1'b0;
              if (sda_line_in == 1'b0)
              begin
                ack_error <= 1'b0;
                bit_index <= 3'd7;
                
                if (use_register)
                begin
                  phase <= 1'b0;
                  state <= SEND_REGISTER_ADDRESS;
                end 
                else
                begin
                  phase <= 1'b0;
                  state <= TRANSMIT_DATA;
                end 
              end
              else 
              begin
                ack_error <= 1'b1;
                state <= IDLE;
                phase <= 1'b0;
              end 
            end 
            
          end
            
          
          SEND_REGISTER_ADDRESS:
          begin
        //    scl_line <= ~ scl_line;
            if ((phase[0] == 1'b0) && (phase <= 5'd14))
            begin
              //phase <= phase + 1'b1;
              
              sda_line_out <= (register_reg[bit_index]== 1'b1)? 1'b1: 1'b0;
              if (bit_index != 3'd0)
              begin
                bit_index <= bit_index - 3'b1;
              end
            end
            
            else if(phase == 5'd16)
            begin
              //phase <= phase + 1'b1;
              sda_line_out <= 1'b1;
            end
            
            else if(phase == 5'd17)
            begin 
              if (sda_line_in == 1'b0)
              begin
                ack_error <= 1'b0;
                bit_index <= 3'd7;
                state <= TRANSMIT_DATA;
                phase <= 1'b0;
              end 
              else 
              begin
                ack_error <= 1'b1;
                state <= IDLE;
                phase <= 1'b0;
              end
            end 
          end 
          
          TRANSMIT_DATA:
          begin
          //  scl_line <= ~ scl_line;
            
            if ((phase == 5'd0) && (bytes_internal != 4'd0))
            begin 
              read_request <= 1'b1;
              bit_index_transmit <= 1'b1;
            end
            
            else if ((phase[0] == 1'b0) && (phase < 5'd14))
            begin 
              sda_line_out <= data_from_fifo[bit_index_transmit];

              if (bit_index_transmit != 3'd0)
              begin
                  bit_index_transmit <= bit_index_transmit - 3'd1;
              end
            end 
            
            else if (phase == 5'd16)
            begin
                sda_line_out <= 1'b0;
            end
            
            else if (phase == 5'd17)
            begin
              if (sda_line_in == 1'b0)
              begin
                ack_error <= 1'b0;
                phase <= 1'b0;
                
                if (bytes_internal != 4'd0)
                begin 
                  bytes_internal <= bytes_internal - 4'd1;
                end
                else 
                begin
                  state <= SEND_STOP;
                end
              end
              else 
              begin 
                ack_error <= 1'b1;
                state <= IDLE;
                phase <= 5'b0;
              end 
            end
          end 
          
          SEND_STOP:
          begin
            if (phase == 1'b0)
            begin 
              scl_line <= 1'b0;
              sda_line_out <= 1'b0;
            end 
            
            else if(phase == 1'b1)
            begin
              scl_line <= 1'b1;
              sda_line_out <= 1'b0;
            end
            else if (phase == 2'b01)
            begin 
              sda_line_out <= 1'b1;
              scl_line <= 1'b1;
              state <= IDLE;
              status_reg[7] <= 1'b0;
              phase <= 1'b0;
            end 
            //drive_scl <= 1'b1;
            //drive_sda_out <= 1'b1;
          end 
        endcase
      end
    end
    
    
endmodule
  





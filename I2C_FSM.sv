`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/06/2025 10:26:58 AM
// Design Name: 
// Module Name: I2C_FSM
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

module I2C_FSM(
    
    input logic axi_clk,
    input logic axi_resetn,
    input logic [31:0] control_reg,
    input logic [7:0] address_reg, 
    input logic [7:0] register_reg,
    input logic [7:0] data_from_bus_to_fifo,
    input logic pe_read, 
    input logic [4:0] raddar,
    output logic [7:0] status_reg, 
    
    output logic SCL,
    inout wire SDA
    
    );
    
    //implement the 200Khz clock divider 
    logic need_ratio = (axi_clk/200000);
    logic count_clk = 0;
    logic clk_out;
    
    always_ff @(posedge axi_clk)
    begin
      if (!axi_resetn)
      begin
        count_clk <= 0;
        clk_out <= 0;
      end
      else if (need_ratio == 500)
      begin
        count_clk <= 0;
        clk_out <= ~clk_out;
      end
      else
        count_clk <= count_clk + 1;
    end    
    
    wire final_clock_out;
    assign final_clock_out = clk_out & (control_reg & 32'h100);
    
    reg [4:0] phase;
    reg [2:0] state;
    
    parameter IDLE = 3'd0;
    parameter START = 3'd1;
    parameter SEND_DEVICE_ADDRESS = 3'd2;
    parameter SEND_REGISTER_ADDRESS = 3'd3;
    parameter TRANSMIT_DATA = 3'd4;
    parameter SEND_STOP = 3'd5;
    
    
    
    assign SCL = scl_drive_low? 1'b0 : 1'bz;
    assign SDA = sda_drive_low? 1'b0 : 1'bz;
    
    logic [3:0] bit_count;
    assign bit_count = control_reg[4:1];
    
    
    always_ff @(posedge CLK100)
    begin
      if (!axi_resetn)
      begin
          phase <= 5'b0;
          state <= IDLE;
      end
      else
      begin 
        if (final_clock_out)
        begin 
            phase <= phase + 1;
            
          
          //During the even phases - write to the i2c bus
          //During the odd phases - read from the i2c bus
            case(state)
            IDLE:
            begin
              if (phase == 2'd3)
                control_reg[7] <= 1'b1;
                state <= START;
                phase <= 1'b0;
            end
            
            START:
            begin
              if (phase == 1'b0)
              begin
                SCL <= 1'b1;
                SDA <= 1'b1;
              end
              else if(phase == 1'b1)
                SDA <= 0;
              else if (phase == 2'b10)
              begin 
                SCL <= 1'bz;
                SDA <= 1'bz;
                if (control_reg & ~(1'b1))
                   state <= SEND_DEVICE_ADDRESS;
              end 
            end  
            
            
            SEND_DEVICE_ADDRESS:
            begin
              if (phase % 2 == 0) 
              begin
              // When phase is even, send data_from_bus_to_fifo to the sda 
                 SCL <= 1'b0;
                 
                 transmit_byte <= {address_reg[6:0], 1'b0}; // Send all 8 bits together - 7 (7 address bits + 0 (write bit))
                 bit_index <= 3'd7; // MSB will be sent first 
                 bit_count <= 1'b0; // bit count == 0, cuz no bit sent yet 
                 status_reg [7] <= 1'b1; // Busy bit of status register is set 
              
                 if (bit_count < 8) 
                 begin
                   SDA <= transmit_byte[bit_index];
                   bit_index <= bit_index - 3'b1;
                   bit_count <= bit_count + 1'b1;
                 end
                   // SLAVE now needs to send an ack
                   // IF THE CLOCK LINE IS high, thats when slave can send a write
                 else  
                 begin
                   if (phase == 5'd16)
                     SCL <= 1'bz;
                   if (phase == 5'd17)
                   begin 
                     if (SDA == 1'b0)
                       status_reg[7] = 1'b0;
                       if (control_reg[5])  // control_reg[5] == USE_REGISTER Bit of control register 
                       begin
                         state <= SEND_REGISTER_ADDRESS;
                       end
                       else 
                       begin
                         state <= TRANSMIT_DATA;
                       end 
                   end
                   else
                     begin 
                       status_reg[6] = 1'b1;
                       state <= IDLE;
                     end
                   end
              end
              else
                
              if (phase % 2 != 0) 
              begin 
                SCL <= 1'bz;
                transmit_byte <= {address_reg[6:0], 1'b1} //Send the device address again but this time with the LSB as 1 (read) 
              end
            end
            
            
            
            SEND_REGISTER_ADDRESS:
            begin
              if (phase % 2 == 0) 
              begin
                SCL <= 1'b0;
                if ((status_reg[7] == 1'b1)) //the scl_drive_low = 100Khz clock, status_reg[7] = busy bit, status_reg[6] = ACK_ERROR
                 begin 
                   transmit_byte <= {register_reg[6:0], 1'b0}; // Send all 8 bits together - 7 (7 address bits + 0 (write bit))
                   bit_index <= 3'b111; // MSB will be sent first 
                   bit_count <= 1'b0; // bit count == 0, cuz no bit sent yet 
                   status_reg [7] <= 1'b1; // Busy bit of status register is set 
                 end
                 
                 if (bit_count < 8) 
                 begin
                   SDA <= transmit_byte[bit_index];
                   bit_index <= bit_index - 3'b1;
                   bit_count <= bit_count + 1'b1;
                 end
                   
                   // SLAVE now needs to send an ack
                   // IF THE CLOCK LINE IS high, thats when slave can send a write
                  else  
                  begin
                  if (phase == 5'd16)
                     SCL <= 1'bz;
                   if (phase == 5'd17)
                   begin 
                   if (SDA == 1'b0) 
                      status_reg[7] <= 1'b0; //status_reg[7] = BUSY bit
                      state <= SEND_REGISTER_ADDRESS;
                   end  
                     end
                       status_reg[6] = 1'b1;
                       state <= IDLE;
                   end    
              end
              else 
              begin
                SCL <= 1'bz;
              end
            end
            
            
            TRANSMIT_DATA:
            begin
              if (phase % 2 == 0)
              begin 
                   SCL <= 1'b0;
                // Put the 8 bits of data in a register first and initialize all variables 
                   if ((pe_read && (raddr[4:2] == DATA_REG)
                   begin
                     transmit_byte <= {data_from_bus_to_fifo[6:0], 1'b0}; // Send all 8 bits together - 7 (7 address bits + 0 (write bit))
                     bit_index <= 3'd7; // MSB will be sent first 
                     bit_count <= 1'd0; // bit count == 0, cuz no bit sent yet 
                     status_reg [7] <= 1'b1; // Busy bit of status register is set 
                   end
                
                   ///////Transmit the data bits one at a time to the SDA line and continue until the bit count hits 8
                   if (status_reg[7])
                   begin
                     if (bit_count < 8)
                     begin 
                       SDA <= transmit_byte[bit_index];
                       bit_index <= bit_index - 3'b1;
                       bit_count <= bit_count + 1'b1
                     end                   
                  // Receive the ack from the slave to end transmission 
                  // On the 16th phase, make the SDA high impedence 
                     if (phase == 5'd16)
                       SCL <= 1'bz;
                     if (phase == 5'd17)
                     begin 
                       if (SDA == 1'b0)
                       begin
                         status_reg[7] <= 1'b0; //status_reg[7] = BUSY Bit
                         state <= STOP;
                       end
                       else 
                       begin 
                         status_reg[6] = 1'b1;
                         state <= IDLE;
                       end
                     end 
                   end  
                 end    
              end
              else
                SCL <= 1'bz;
            end
            
            STOP:
            begin
              SCL <= 1'bz;
              SDA <= 1'b1;
            end
              

endmodule

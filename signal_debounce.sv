`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/08/2025 08:15:22 PM
// Design Name: 
// Module Name: signal_debounce
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


module signal_debounce(
    input logic slow_clock_input,
    input logic signal_in,
    output logic single_pulse_out
    );
    
    logic clock_to_DFF;
    logic Q1;
    logic wire_to_single_pulse;
    
    
    slow_clock inst1(
      .clock_in(slow_clock_input),
      .clock_out(clock_to_DFF)
    );
    
    
    d_FlipFlop dd1
    (
      .clk_in(clock_to_DFF),
      .D(signal_in),
      .Q(Q1),
      .Q_bar()
    );
    
    
    d_FlipFlop dd2
    (
      .clk_in(clock_to_DFF),
      .D(Q1),
      .Q(),
      .Q_bar(wire_to_single_pulse)
    );
    
    assign single_pulse_out = Q1 & wire_to_single_pulse;
    
endmodule

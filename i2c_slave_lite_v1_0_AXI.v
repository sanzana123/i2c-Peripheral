`timescale 1 ns / 1 ps

    module  i2c_slave_lite_v1_0_AXI #
    (
        // Bit width of S_AXI address bus
        parameter integer C_S_AXI_DATA_WIDTH	= 32,
        parameter integer C_S_AXI_ADDR_WIDTH = 5
    )
    (
        // Ports to top level module (what makes this the GPIO IP module)
//        input wire [31:0] gpio_data_in,
//        output wire [31:0] gpio_data_out,
//        output wire [31:0] gpio_data_oe,
//        output wire intr,

        // AXI clock and reset        
        input wire S_AXI_ACLK,
        input wire S_AXI_ARESETN,

        // AXI write channel
        // address:  add, protection, valid, ready
        // data:     data, byte enable strobes, valid, ready
        // response: response, valid, ready 
        input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
        input wire [2:0] S_AXI_AWPROT,
        input wire S_AXI_AWVALID,
        output wire S_AXI_AWREADY,
        
        input wire [31:0] S_AXI_WDATA,
        input wire [3:0] S_AXI_WSTRB,
        input wire S_AXI_WVALID,
        output wire  S_AXI_WREADY,
        
        output wire [1:0] S_AXI_BRESP,
        output wire S_AXI_BVALID,
        input wire S_AXI_BREADY,
        
        // AXI read channel
        // address: add, protection, valid, ready
        // data:    data, resp, valid, ready
        input wire [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
        input wire [2:0] S_AXI_ARPROT,
        input wire S_AXI_ARVALID,
        output wire S_AXI_ARREADY,
        
        output wire [31:0] S_AXI_RDATA,
        output wire [1:0] S_AXI_RRESP,
        output wire S_AXI_RVALID,
        input wire S_AXI_RREADY, 
        
        // --------------------------------------
        output wire [9:0]leds_indexes_to_top,
        output scl_line,
        output sda_line_out,
        input sda_line_in
    );

    // Internal registers
    reg [31:0] address_reg;
    reg [31:0] register_reg;
    reg [31:0] data_reg;
    reg [31:0] status_reg;
    reg [31:0] control_reg;
    
   
//    reg [31:0] int_negative;
//    reg [31:0] int_edge_mode;
//    reg [31:0] int_status;
//    reg [31:0] int_clear_request;
    
    // Register map
    // ofs  fn
    //   0  data (r/w)
    //   4  out (r/w)
    //   8  od (r/w)
    //  12  int_enable (r/w)
    //  16  int_positive (r/w)
    //  20  int_negative (r/w)
    //  24  int_edge_mode (r/w)
    //  28  int_status_clear (r/w1c)
    
    // Register numbers
    localparam integer ADDRESS_REG          = 3'b000;
    localparam integer REGISTER_REG         = 3'b001;
    localparam integer DATA_REG             = 3'b010;
    localparam integer STATUS_REG           = 3'b011;
    localparam integer CONTROL_REG          = 3'b100;
//    localparam integer INT_NEGATIVE_REG     = 3'b101;
//    localparam integer INT_EDGE_MODE_REG    = 3'b110;
//    localparam integer INT_STATUS_CLEAR_REG = 3'b111;
    
    // AXI4-lite signals
    reg axi_awready;
    reg axi_wready;
    reg [1:0] axi_bresp;
    reg axi_bvalid;
    reg axi_arready;
    reg [31:0] axi_rdata;
    reg [1:0] axi_rresp;
    reg axi_rvalid;
    
    // friendly clock, reset, and bus signals from master
    wire axi_clk           = S_AXI_ACLK;
    wire axi_resetn        = S_AXI_ARESETN;
    wire [31:0] axi_awaddr = S_AXI_AWADDR;
    wire axi_awvalid       = S_AXI_AWVALID;
    wire axi_wvalid        = S_AXI_WVALID;
    wire [3:0] axi_wstrb   = S_AXI_WSTRB;
    wire axi_bready        = S_AXI_BREADY;
    wire [31:0] axi_araddr = S_AXI_ARADDR;
    wire axi_arvalid       = S_AXI_ARVALID;
    wire axi_rready        = S_AXI_RREADY;    
    
    // assign bus signals to master to internal reg names
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;
    
    logic [31:0] data_from_bus_to_fifo;
    logic [7:0] data_to_bus_from_fifo;
    
    logic empty_flag_transmit;
    logic full_flag_transmit;
    logic overflow_flag_transmit;
    
    logic empty_flag_receive;
    logic full_flag_receive;
    logic overflow_flag_receive;
    
    
    
    wire [7:0] leds; 
    assign leds_indexes_to_top = {2'b00, leds};
    
    // Handle gpio input metastability safely
//    reg [31:0] read_port_data;
//    reg [31:0] pre_read_port_data;
//    always_ff @ (posedge(axi_clk))
//    begin
//        pre_read_port_data <= gpio_data_in;
//        read_port_data <= pre_read_port_data;
//    end

    // Assert address ready handshake (axi_awready) 
    // - after address is valid (axi_awvalid)
    // - after data is valid (axi_wvalid)
    // - while configured to receive a write (aw_en)
    // De-assert ready (axi_awready)
    // - after write response channel ready handshake received (axi_bready)
    // - after this module sends write response channel valid (axi_bvalid) 
    wire wr_add_data_valid = axi_awvalid && axi_wvalid;
    reg aw_en;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_awready <= 1'b0;
            aw_en <= 1'b1;
        end
        else
        begin
            if (wr_add_data_valid && ~axi_awready && aw_en)
            begin
                axi_awready <= 1'b1;
                aw_en <= 1'b0;
            end
            else if (axi_bready && axi_bvalid)
                begin
                    aw_en <= 1'b1;
                    axi_awready <= 1'b0;
                end
            else           
                axi_awready <= 1'b0;
        end 
    end

    // Capture the write address (axi_awaddr) in the first clock (~axi_awready)
    // - after write address is valid (axi_awvalid)
    // - after write data is valid (axi_wvalid)
    // - while configured to receive a write (aw_en)
    reg [C_S_AXI_ADDR_WIDTH-1:0] waddr;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
            waddr <= 0;
        else if (wr_add_data_valid && ~axi_awready && aw_en)
            waddr <= axi_awaddr;
    end

    // Output write data ready handshake (axi_wready) generation for one clock
    // - after address is valid (axi_awvalid)
    // - after data is valid (axi_wvalid)
    // - while configured to receive a write (aw_en)
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
            axi_wready <= 1'b0;
        else
            axi_wready <= (wr_add_data_valid && ~axi_wready && aw_en);
    end       

    // Write data to internal registers
    // - after address is valid (axi_awvalid)
    // - after write data is valid (axi_wvalid)
    // - after this module asserts ready for address handshake (axi_awready)
    // - after this module asserts ready for data handshake (axi_wready)
    // write correct bytes in 32-bit word based on byte enables (axi_wstrb)
    // int_clear_request write is only active for one clock
    
    logic read_write;
    logic [4:1] byte_count;
    logic use_register;
    logic use_repeated_start;
    logic start_bit;
    logic test_out;
    logic [7:0] debug_interface;
    
    logic clear_start_request;
    
    
    
    wire wr = wr_add_data_valid && axi_awready && axi_wready;
    
    reg clear_overflow_transmit;
    
    reg clear_overflow_receive;
    
    integer byte_index;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            address_reg[31:0] <= 32'b0;
            register_reg <= 32'b0;
            data_reg <= 32'b0;
            status_reg <= 32'b0;
            control_reg <= 32'b0;
        end 
        else 
        begin
            if (wr)
            begin
                case (axi_awaddr[4:2])
                    ADDRESS_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if ( axi_wstrb[byte_index] == 1) 
                                address_reg[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    REGISTER_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
                                register_reg [(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    DATA_REG: 
                          for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
//                                if (empty_flag && (leds == 8'b0))
                                   data_from_bus_to_fifo[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    STATUS_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1)
                            begin
                                status_reg[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                                if (S_AXI_WDATA[3])
                                  clear_overflow_transmit<= 1;
                                
                                if (S_AXI_WDATA[0])
                                  clear_overflow_receive <= 1;
                                  
                            end
                                
                    CONTROL_REG:
                        for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (axi_wstrb[byte_index] == 1) 
                            begin;      
                                //control_reg <= {debug_interface, 15'b00, test_out, start_bit, use_repeated_start, use_register, byte_count, read_write};
                                // When you write the C program, specify which registers and which bits to work on 
                                
                                control_reg <= S_AXI_WDATA[31:0];
                                
                                if (clear_start_request)
                                begin
                                  control_reg[7] <= 1'b0;
                                end 
                            end
                                 
                endcase
            end
            else
                clear_overflow_transmit <= 1'b0;
                
            
        end
    end    

    // Send write response (axi_bvalid, axi_bresp)
    // - after address is valid (axi_awvalid)
    // - after write data is valid (axi_wvalid)
    // - after this module asserts ready for address handshake (axi_awready)
    // - after this module asserts ready for data handshake (axi_wready)
    // Clear write response valid (axi_bvalid) after one clock
    wire wr_add_data_ready = axi_awready && axi_wready;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_bvalid  <= 0;
            axi_bresp   <= 2'b0;
        end 
        else
        begin    
            if (wr_add_data_valid && wr_add_data_ready && ~axi_bvalid)
            begin
                axi_bvalid <= 1'b1;
                axi_bresp  <= 2'b0;
            end
            else if (S_AXI_BREADY && axi_bvalid) 
                axi_bvalid <= 1'b0; 
        end
    end   

    // In the first clock (~axi_arready) that the read address is valid
    // - capture the address (axi_araddr)
    // - output ready (axi_arready) for one clock
    reg [C_S_AXI_ADDR_WIDTH-1:0] raddr;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_arready <= 1'b0;
            raddr <= 32'b0;
        end 
        else
        begin    
            // if valid, pulse ready (axi_rready) for one clock and save address
            if (axi_arvalid && ~axi_arready)
            begin
                axi_arready <= 1'b1;
                raddr  <= axi_araddr;
            end
            else
                axi_arready <= 1'b0;
        end 
    end       
        
    // Update register read data
    // - after this module receives a valid address (axi_arvalid)
    // - after this module asserts ready for address handshake (axi_arready)
    // - before the module asserts the data is valid (~axi_rvalid)
    //   (don't change the data while asserting read data is valid)
    
    
    wire rd = axi_arvalid && axi_arready && ~axi_rvalid;
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
        begin
            axi_rdata <= 32'b0;
        end 
        else
        begin    
            if (rd)
            begin
		// Address decoding for reading registers
		case (raddr[4:2])
		    ADDRESS_REG: 
		        axi_rdata <= address_reg;
		    REGISTER_REG:
		        axi_rdata <= register_reg;
		    DATA_REG: 
		          axi_rdata <= {24'b0, data_to_bus_from_fifo};
		    STATUS_REG: 
		         // Just directly write the bits to the statuts register. Follow the register layout in the project directory
		         //if (overflow_flag)
		           begin
			         //axi_rdata <= {26'b0, overflow_flag, full_flag, empty_flag, 3'b0};
			         axi_rdata <= {26'b0, empty_flag_transmit, full_flag_transmit, overflow_flag_transmit, empty_flag_receive, full_flag_receive, overflow_flag_receive};
			         
			       end
			     //axi_rdata <= status_reg;
		    CONTROL_REG:
			     //axi_rdata <= control_reg;
			     begin
//			       control_reg <= {debug_interface, 15'b00, test_out, start_bit, use_repeated_start, use_register, byte_count, read_write};
			       axi_rdata <= control_reg;
			     end
			     
		endcase
            end   
        end
    end    

    // Assert data is valid for reading (axi_rvalid)
    // - after address is valid (axi_arvalid)
    // - after this module asserts ready for address handshake (axi_arready)
    // De-assert data valid (axi_rvalid) 
    // - after master ready handshake is received (axi_rready)
    always_ff @ (posedge axi_clk)
    begin
        if (axi_resetn == 1'b0)
            axi_rvalid <= 1'b0;
        else
        begin
            if (axi_arvalid && axi_arready && ~axi_rvalid)
            begin
                axi_rvalid <= 1'b1;
                axi_rresp <= 2'b0;
            end   
            else if (axi_rvalid && axi_rready)
                axi_rvalid <= 1'b0;
        end
    end   

    
    //edge detector for reading 
    reg sig_read;
    reg sig_delay_read;
    wire pe_read;
    
    wire read_to_edgeDetect;
     
   
   
    always_ff @(posedge axi_clk)
    begin
      if (~axi_resetn) 
      begin
        sig_read <= 0;
        sig_delay_read <= 0;
      end 
      else 
      begin 
        sig_read <= rd;
        sig_delay_read <= sig_read;
      end 
     end
        
    assign pe_read = sig_read && ~sig_delay_read;
    
    //edge detector for writing
    reg sig_write;
    reg sig_delay_write;
    wire pe_write;
    
    wire write_to_edgeDetect;
    

    always_ff @(posedge axi_clk)
    begin
      if (~axi_resetn) 
      begin
        sig_write <= 0;
        sig_delay_write <= 0;
      end 
      else 
      begin 
        sig_write <= wr;
        sig_delay_write <= sig_write;
      end 
     end
    
    assign pe_write = sig_write && ~sig_delay_write;
    
    wire capture_read_request;
    
    
    //Transmit Fifo 
    fifo instantiation_tx (
      .clk(axi_clk),
      
      .reset(~axi_resetn),
      
      .wr_data(data_from_bus_to_fifo & 8'hFF),
      
      .wr_request(pe_write && (axi_awaddr[4:2] == DATA_REG)),
      
      //.wr_request(pe_write && (waddr[4:2] == DATA_REG)),

      ///////////////////////////////////////////
      .rd_data(data_to_bus_from_fifo),
      
      //.rd_request(pe_read && (raddr[4:2] == DATA_REG)),
      .rd_request(capture_read_request),
      
      .empty(empty_flag_transmit),
      
      .full(full_flag_transmit),
      
      .overflow(overflow_flag_transmit),
      
      .clear_overflow_request(clear_overflow_transmit),
      
      .wr_index(leds[3:0]),
      
      .rd_index(leds[7:4])
    ); 
    
    
    // Receive Fifo
    fifo instantiation_rx (
      .clk(axi_clk),
      
      .reset(~axi_resetn),
      
      .wr_data(),
      
      .wr_request(),
      
      //.wr_request(pe_write && (waddr[4:2] == DATA_REG)),

      ///////////////////////////////////////////
      .rd_data(data_to_bus_from_fifo),
      
      .rd_request(pe_read && (raddr[4:2] == DATA_REG)),
      
      .empty(empty_flag_receive),
      
      .full(full_flag_receive),
      
      .overflow(overflow_flag_receive),
      
      .clear_overflow_request(clear_overflow_receive),
      
      .wr_index(),
      
      .rd_index()
    ); 
    
    // fsm instantiation 
    i2c_finite_state_machine i2c_finite_state_machine_instantiation (
      .axi_clk(S_AXI_ACLK),
      .axi_resetn(S_AXI_ARESETN),
      .address_reg(address_reg),
      .register_reg(register_reg),
      .data_from_fifo(data_from_bus_to_fifo),
      .status_reg(status_reg),
      .read_write(control_reg[0]),
      .byte_count(control_reg[4:1]),
      .use_register(control_reg[5]),
      .use_repeated_start(control_reg[6]),
      .start(control_reg[7]),
      .test_out(control_reg[8]),
      .debug_out(control_reg[31:24]),
      .read_request(capture_read_request),
      .clear_start_request(),
      .scl_line(scl_line),
      .sda_line_out(sda_line_out),
      .sda_line_in(sda_line_in)
    );
    
endmodule
    
    
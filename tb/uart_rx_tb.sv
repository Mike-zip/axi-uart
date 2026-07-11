//Michael Marquis
//UART_RX_TESTBENCH

`timescale 1ns/1ps

module Test_Bench;
  
  //baud division => Clk_Tb / Baud_Rate_Tb -> 10 : only for the sim.
  //each bit will only be 10 clock cycles instead of 50MHz/ 9600 -> '5208'
  
  localparam	Clk_Frequency_Tb	= 50_000_000;	
  localparam	Baud_Rate_Tb		= 5_000_000;
  localparam	Over_Sample_Tb		= 10;
  localparam	Fifo_Slots_Tb		= 16;
 
  reg 			Clk_Tb;
  reg 			Reset_Tb;
  reg 			Rx_Data_Tb;
  reg 			Pop_Enable_Tb;
  wire			Rx_Ready_Tb;
  wire			Frame_Error_Tb;
  wire  		Over_Run_Error_Tb;
  wire  [7 : 0] Data_Out_Tb;
  
  Uart_Rx #(
    .Clk_Frequency(Clk_Frequency_Tb),
    .Baud_Rate(Baud_Rate_Tb),
    .Over_Sample(Over_Sample_Tb),
    .Fifo_Slots(Fifo_Slots_Tb)
  ) DUT (
    .Clk(Clk_Tb),
    .Reset(Reset_Tb),
    .Rx_Data(Rx_Data_Tb),
    .Pop_Enable(Pop_Enable_Tb),
    .Rx_Ready(Rx_Ready_Tb),
    .Frame_Error(Frame_Error_Tb),
    .Over_Run_Error(Over_Run_Error_Tb),
    .Data_Out(Data_Out_Tb)
  );
  
  
    integer Errors = 0;
  	always #10 Clk_Tb = ~Clk_Tb;
  
  	initial begin
    	Clk_Tb			= 1'b0;
  		Reset_Tb 		= 1'b0;
		Rx_Data_Tb		= 8'd1;
   		Pop_Enable_Tb	= 1'b0;
    	#100;
    	Reset_Tb 		= 1'b1;
    	@(posedge Clk_Tb);
    
      for(integer B = 0; B < 256; B = B + 1) begin
        Recieve_Byte(B [7 : 0]);  
      end
      
      if(Errors == 0)
        $display("\nPASS: all 256 cases passed Erros<%0d>\n", Errors);
      else
        $display("\nFAIL: Erros<%0d>\n", Errors);
    	$finish;
    
  end
  
  
  task Recieve_Byte (input [7 : 0] Bits);
    begin
      @(posedge Clk_Tb);
      $display("START VALUES: Rx_Shift_In: %b State: %s", DUT.Rx_Shift_In, State_Name(DUT.State));
      Rx_Data_Tb = 1'b0;
      repeat(10) @(posedge Clk_Tb);
      for(integer i = 0; i < 8; i = i + 1) begin
        
        Rx_Data_Tb = Bits[i];
        repeat(10) @(posedge Clk_Tb);    
        $display("WORK VALUES:  Rx_Shift_In: %b State: %s, i: %0d", DUT.Rx_Shift_In, State_Name(DUT.State), i);
      end
      Rx_Data_Tb = 1'b1;
      repeat(10) @(posedge Clk_Tb);
      $display("END VALUES:   Rx_Shift_In: %b State: %s", DUT.Rx_Shift_In, State_Name(DUT.State));
    end
    
    wait(Rx_Ready_Tb == 1'b1) begin
      
    	Pop_Enable_Tb = 1'b1;
      @(posedge Clk_Tb);
      
      if(Bits !== Data_Out_Tb) begin
        
      	Errors = Errors + 1;
        $display("bits != data out Bits: %b, Data_Out_Tb: %b", Bits, Data_Out_Tb);
        
      end
      else begin
        $display("Bits: %b,  Data_Out_Tb: %b", Bits, Data_Out_Tb);  
      end
       Pop_Enable_Tb = 1'b0;
    end
  endtask
 
  //This is to simplify FSM states into names for visual purpose
  function [8*5 : 1] State_Name (input [1:0] Name_State);
    case(Name_State)
      2'd0:		State_Name =	"Idle";
      2'd1:		State_Name =	"Start";
      2'd2:		State_Name = 	"Data";
      2'd3:		State_Name = 	"Stop";
      default:	State_Name = 	"ERROR";
    endcase
  endfunction
endmodule

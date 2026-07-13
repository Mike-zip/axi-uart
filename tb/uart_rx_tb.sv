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
  
  	
  
  	initial begin
      $dumpfile("wave.vcd");
      $dumpvars(0, Test_Bench);
	end
  
    integer Errors = 0;
  	always #10 Clk_Tb = ~Clk_Tb;
  
  	initial begin
        integer Latency0, Latency1;
    	Clk_Tb			= 1'b0;
  		Reset_Tb 		= 1'b0;
		Rx_Data_Tb		= 8'd1;
   		Pop_Enable_Tb	= 1'b0;
    	#100;
    	Reset_Tb 		= 1'b1;
      
    	@(posedge Clk_Tb);
     
      for(integer B = 0; B < 256; B = B + 1) begin
        Recieve_Byte	(B [7 : 0]); 
        Send_Bad_Frame	(B [7 : 0]);
      end
      Over_Run_Error_Check();
      
      Measure_Sync_Latency(1'b1, Latency1);
      Measure_Sync_Latency(1'b0, Latency0);
      $display("\nMeasured Synchronizer Latency: Rise= %0d Clocks, Fall= %0d Clocks", Latency1, Latency0);
      
      if(Latency1 == 2 && Latency0 ==2)
        $display("\nPASS: 2-FF Synchronizer Latency Confirmed = 2 clocks");
      else begin
        $display("\nFAIL: 2-FF Unexpected Synchronizer Latency");
      end
      
      if(Errors == 0)
        $display("\nPASS: ALL CASES PASSED");
      else
        $display("\nFAIL: Erros<%0d>\n", Errors);
      	$finish;
    
    end
  
  	
  task Over_Run_Error_Check ();
    begin
      integer visable;
      for(integer i = 0; i < Fifo_Slots_Tb + 1; i = i + 1) begin
        @(posedge Clk_Tb);
        Rx_Data_Tb = 1'b0;
        repeat (10) @(posedge Clk_Tb);
        for(integer k = 0; k < 8; k = k + 1) begin
          Rx_Data_Tb = 1'b1;
        end
        Rx_Data_Tb = 1'b1;
        repeat (10) @(posedge Clk_Tb);
        wait (Rx_Ready_Tb == 1'b1);
      end
      visable = DUT.Over_Run_Error;
      if(DUT.Over_Run_Error != 1'b1) begin
        $display("\nFAIL: 'Over_Run_Error' did not assert to '1' Value= %0b", DUT.Over_Run_Error);
        Errors = Errors + 1;
      end
      else
        $display("\nPASS: 'Over_Run_Error' asserted to : %0b", DUT.Over_Run_Error);
    end
    endtask
  
  
  
  task Send_Bad_Frame (input [7 : 0] Bits);   
    begin
      Rx_Data_Tb = 1'b1;
      repeat (10) @(posedge Clk_Tb);
      Rx_Data_Tb = 1'b0;
      repeat (3)  @(posedge Clk_Tb);
      Rx_Data_Tb = 1'b1;
      repeat (7)  @(posedge Clk_Tb);
      
      
      if(DUT.State !== 2'b00) begin
        $display("\nFAIL: Failed Idle With Bad Start Bit State= %s", State_Name(DUT.State));
        Errors = Errors + 1;
      end
      else
        $display("\nPASS: Bad Start Bit => Idle");
      //Bad Stop Bit Below
      Rx_Data_Tb = 1'b0;
      repeat(10) @(posedge Clk_Tb);
      for(integer i = 0; i < 8; i = i + 1) begin
        Rx_Data_Tb = Bits[i];
        repeat (10) @(posedge Clk_Tb);
      end
      Rx_Data_Tb = 1'b0;
      repeat(10) @(posedge Clk_Tb);
      if(DUT.Frame_Error !== 1'b1) begin
        $display("\nFAIL: Failed To Throw 'Frame_Error' : %0b", DUT.Frame_Error);
        Errors = Errors + 1;
      end
      else
        $display("\nPASS: Threw The 'Frame_Error'");
      
      //clean transition to 'Idle'
      Rx_Data_Tb = 1'b1;
      wait(DUT.State == 2'b00);
      repeat (2) @(posedge Clk_Tb);
    end
  endtask
  
  task Measure_Sync_Latency (input New_Value, output integer Latency);
    integer X;
    reg Found;
    begin
      Found		= 1'b0;
      Latency	= -1;
      
      Rx_Data_Tb = ~New_Value;
      repeat (5) @(posedge Clk_Tb);
      @(posedge Clk_Tb);
      Rx_Data_Tb = New_Value;
      
      for(X = 0; X <= 10 && !Found; X = X + 1) begin
        if(DUT.Rx_Stable_In === New_Value) begin
          Latency 	= X;
          Found		= 1'b1;
        end
        else begin
          @(posedge Clk_Tb);
        end
      end
    end
  endtask
    
    
 
  
  task Recieve_Byte (input [7 : 0] Bits); //Test all cases for recieving a byte
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
      repeat (2) @(posedge Clk_Tb);
      
      if(Bits !== Data_Out_Tb) begin
        
      	Errors = Errors + 1;
        $display("\nFAIL: bits != data out Bits: %b, Data_Out_Tb: %b", Bits, Data_Out_Tb);
         
      end
      else begin
        $display("Bits: %b,  Data_Out_Tb: %b", Bits, Data_Out_Tb);  
      end
       Pop_Enable_Tb = 1'b0;
      
      //clean transition to 'Idle'
      Rx_Data_Tb = 1'b1;
      wait(DUT.State == 2'b00);
      repeat (2) @(posedge Clk_Tb);
    end
  endtask
 
  
  function [8*5 : 1] State_Name (input [1:0] Name_State); //Change our state binary values to make readability easier
    case(Name_State)
      2'd0:		State_Name =	"Idle";
      2'd1:		State_Name =	"Start";
      2'd2:		State_Name = 	"Data";
      2'd3:		State_Name = 	"Stop";
      default:	State_Name = 	"ERROR";
    endcase
  endfunction
endmodule

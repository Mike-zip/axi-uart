//Michael Marquis
//UART_RX_Design

`timescale 1ns/1ps

module Uart_Rx #(
  parameter Clk_Frequency = 50_000_000,
  parameter Baud_Rate	  = 9600,
  parameter Over_Sample   = 16,
  parameter Fifo_Slots    = 16
)(
  input wire 			Clk,
  input wire 			Reset, 		//Active low
  input reg  			Rx_Data,
  input wire 			Pop_Enable,
  output wire 			Rx_Ready,
  output reg    		Frame_Error,
  output reg 			Over_Run_Error,
  output reg [7 : 0] 	Data_Out
);
  
  localparam 	Sample_Division = Clk_Frequency / (Baud_Rate * Over_Sample);
  integer 		Sample_Count;
  reg			Sample_Tick; //Pulses at the oversample rate
  
  always @(posedge Clk or negedge Reset) begin
    if(!Reset) begin
    	Sample_Count	<= 0;
      	Sample_Tick  	<= 1'b0;
    end
    else if(Sample_Count == Sample_Division - 1) begin
    	Sample_Count	<= 0;
      	Sample_Tick  	<= 1'b1;
    end
    else begin
    	Sample_Count	<= Sample_Count + 1'b1;
      	Sample_Tick		<= 1'b0;
    end
  end
  
  reg Stable1, Stable2;
  
  always @(posedge Clk or negedge Reset) begin 
    if(!Reset) begin
    	Stable1		<= 1'b0;
      	Stable2		<= 1'b0;
    end
    else begin
      	Stable1		<= Rx_Data;
      	Stable2		<= Stable1;
    end
  end
  
  wire Rx_Stable_In = Stable2;
  
  localparam    Idle	= 2'd0, Start	= 2'd1, Data 	= 2'd2, Stop	= 2'd3; //0,1,2,3 ___IDLE,START,DATA,STOP
  localparam	Middle_Of_Bit = (Over_Sample / 2) - 1;
  reg [1 : 0] 	State;
  reg [7 : 0]	Rx_Shift_In;
  reg [3 : 0]	Bit_Index;
  reg [4 : 0]	Sample_Index;
  reg [7 : 0]	Stable_Byte;
  reg 			Byte_Valid;
  
  always @(posedge Clk or negedge Reset) begin
    if(!Reset) begin
    	State <= Idle;
      	Rx_Shift_In		<= 8'd0;
      	Bit_Index		<= 4'd0;
      	Sample_Index	<= 5'd0;
      	Stable_Byte		<= 8'd0;
      	Byte_Valid		<= 1'b0;
      	Frame_Error		<= 1'b0;
    end
    
    else begin
    	Byte_Valid		<= 1'b0;
      if(Sample_Tick) begin
        case(State)
          
          Idle: begin
          	Sample_Index	<= 5'd0;
            if(Rx_Stable_In == 1'b0)
            	State	<= Start;
          end
          
          Start: begin
            if(Sample_Index == Middle_Of_Bit) begin
              if(Rx_Stable_In == 1'b0) begin
              	State			<= Data;									//we leave at Middle of the bit 
                Sample_Index	<= 5'd0;									//which means our index zero is
                Bit_Index		<= 4'd0;									//from the middle of the bit
              end															//			^
              else 															//			^
              	State	<= Idle;											//			^
            end																//			^
            else															//			^
              Sample_Index	<= Sample_Index + 1;							//			^
          end																//			^
          																	//			^
          Data: begin														//			^
            if(Sample_Index == Over_Sample - 1) begin 						//pick up at our index zero
            	Sample_Index	<= 5'd0;									//which is from the middle 
              	Rx_Shift_In		<= {Rx_Stable_In, Rx_Shift_In[7:1]};		//of the bit
            	if(Bit_Index == 4'd7)
            		State		<= Stop;
            	else
              		Bit_Index	<= Bit_Index + 1;
            end
            else
            	Sample_Index	<= Sample_Index + 1;
          end
          
          Stop: begin
            if(Sample_Index == Over_Sample) begin
            	Sample_Index	<= 5'd0;
              	State			<= Idle;
              	Byte_Valid		<= 1'b1;
              	Stable_Byte		<= Rx_Shift_In;
              	Frame_Error	    <= (Rx_Stable_In == 1'b0);
            end
            else
              Sample_Index	<= Sample_Index + 1; 
          end
        endcase
      end
    end
  end
  
  localparam Storage_Log = $clog2(Fifo_Slots);
  
  reg [7 : 0] Fifo_Memory_Hold [0 : Fifo_Slots - 1];
  reg [Storage_Log : 0] Write_Pointer;
  reg [Storage_Log : 0] Read_Pointer;
  
  
  
  wire Fifo_Empty 	= (Write_Pointer == Read_Pointer);
  wire Fifo_Full	= (Write_Pointer [Storage_Log - 1 : 0] == Read_Pointer[Storage_Log - 1 : 0]) && (Write_Pointer [Storage_Log] != Read_Pointer [Storage_Log]);
  assign Rx_Ready = !Fifo_Empty;		//This is to tell when there is data waiting in the 'Fifo_Memory_Hold'
  
  always @(posedge Clk or negedge Reset) begin
    if(!Reset) begin
 		Write_Pointer	<= 5'd0;
		Read_Pointer	<= 5'd0;
		Data_Out		<= 8'd0;
      	Over_Run_Error  <= 1'b0;
    end  
    else begin
      if(Byte_Valid) begin
        if(!Fifo_Full) begin
          Fifo_Memory_Hold[Write_Pointer[Storage_Log - 1 : 0]]	<= Stable_Byte;
          Write_Pointer		<= Write_Pointer + 1;
          Over_Run_Error	<= 1'b0;
        end
        else
          Over_Run_Error	<= 1'b1; 
      end
      if(Pop_Enable & !Fifo_Empty) begin
      	Data_Out		<= Fifo_Memory_Hold[Read_Pointer[Storage_Log - 1 : 0]];
        Read_Pointer	<= Read_Pointer + 1;
      end
    end
  end
endmodule

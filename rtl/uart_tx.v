// Michael Marquis

module Uart_Tx #(
  parameter Clk_Frequency = 50_000_000,
  parameter Baud_Rate     = 9600,
  parameter Fifo_Slots    = 16
)(
  input  wire       	Clk,
  input  wire       	Rst_N,

  input  wire [7:0] 	Data_In,
  input  wire       	Push_Enable,
  output wire 	  		Tx_Full,
  output reg        	Tx_Busy,
  output reg        	Tx          //(bytes to bits)
);
  localparam Baud_Division = Clk_Frequency / Baud_Rate;
  integer    Baud_Count;
  wire       Baud_Tick;

  always @(posedge Clk or negedge Rst_N) begin
    if(!Rst_N)
      Baud_Count <= 0;
    else if(!Tx_Busy)                          // held at 0 while idle => synced
      Baud_Count <= 0;
    else if(Baud_Count == Baud_Division - 1)
      Baud_Count <= 0;
    else
      Baud_Count <= Baud_Count + 1;
  end

  assign Baud_Tick = (Baud_Count == Baud_Division - 1);


  reg [3:0] Bit_Index;    //bit counter
  reg [7:0] Tx_Shift;

  localparam Idle = 2'd0, Start = 2'd1, Data = 2'd2, Stop = 2'd3; //0,1,2,3 ___IDLE,START,DATA,STOP
  reg [1:0] State;

  always @(posedge Clk or negedge Rst_N) begin
    if(!Rst_N) begin
      State     <= Idle;
      Tx        <= 1'b1; 
      Tx_Busy   <= 1'b0;
      Bit_Index <= 4'd0;
      Tx_Shift  <= 8'd0;
      Fifo_Pop  <= 1'b0;
    end
    else begin
      Fifo_Pop  <= 1'b0;
      case(State)

        Idle: begin
          Tx      <= 1'b1;
          Tx_Busy <= 1'b0;
          if(!Fifo_Empty) begin
            Tx_Shift <= Fifo_Memory_Hold[Read_Pointer[Storage_Log - 1 : 0]];
            Fifo_Pop <= 1'b1;
            Tx_Busy  <= 1'b1;
            State    <= Start;
          end
        end

        Start: begin
          Tx <= 1'b0;                     //this is that start bit when it drops low
          if(Baud_Tick) begin
            Bit_Index <= 4'd0;
            State     <= Data;
          end
        end

        Data: begin
          Tx <= Tx_Shift[Bit_Index];      //off the lsb side
          if(Baud_Tick) begin
            if(Bit_Index == 4'd7)
              State <= Stop;
            else
              Bit_Index <= Bit_Index + 1'b1;
          end
        end

        Stop: begin
          Tx <= 1'b1;
          if(Baud_Tick) begin
            State   <= Idle;
            Tx_Busy <= 1'b0;
          end
        end
      endcase
    end
  end

  localparam Storage_Log = $clog2(Fifo_Slots);

  reg [7 : 0] Fifo_Memory_Hold [0 : Fifo_Slots - 1];
  reg [Storage_Log : 0] Write_Pointer;
  reg [Storage_Log : 0] Read_Pointer;
  reg Fifo_Pop;
  wire [Storage_Log : 0] Occupancy = Write_Pointer - Read_Pointer;
  wire Fifo_Empty = (Write_Pointer == Read_Pointer);
  assign Tx_Full  = (Write_Pointer[Storage_Log - 1 : 0] == Read_Pointer[Storage_Log - 1 : 0]) && (Write_Pointer[Storage_Log] != Read_Pointer[Storage_Log]);

  always @(posedge Clk or negedge Rst_N) begin
    if(!Rst_N) begin
      Read_Pointer 		<= 0;
      Write_Pointer 	<= 0;
    end
    else begin
      if(!Tx_Full && Push_Enable) begin
        Fifo_Memory_Hold[Write_Pointer[Storage_Log - 1 : 0]]	<= Data_In;
        Write_Pointer <= Write_Pointer + 1;
      end
      if(Fifo_Pop)
        Read_Pointer  <= Read_Pointer + 1;
    end
  end
endmodule

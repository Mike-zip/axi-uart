//Michael Marquis
//Uart_Top

module Uart_Top #(
  parameter Clk_Frequency 	= 100_000_000,
  parameter Baud_Rate		    = 115_200,
  parameter Over_Sample		  = 16,
  parameter Fifo_Slots		  = 16,
  parameter	Address_Width  	= 4,
  parameter Data_Width		  = 32
)(
  input wire	Clk,
  input wire	Rst_N,

  //AXI4-Lite 
  input  wire [Address_Width - 1 : 0] 	Write_Address,
  input  wire                       	  Write_Address_Valid,
  output wire                      		  Write_Address_Ready,
  input  wire [Data_Width - 1 : 0]      Write_Data,
  input  wire                       	  Write_Data_Valid,
  output wire                       	  Write_Data_Ready,
  output wire [1 : 0]                 	Bresp,
  output wire                       	  Bvalid,
  input  wire                       	  Bready,
  input  wire [Address_Width - 1 : 0] 	Read_Address,
  input  wire                       	  Read_Address_Valid,
  output wire                       	  Read_Address_Ready,
  output wire [Data_Width - 1 : 0]    	Read_Data,
  output wire [1 : 0]                 	Rresp,
  output wire                       	  Rvalid,
  input  wire                       	  Rready,

  //UART Pins
  output wire                       Uart_Txd,    
  input  wire                       Uart_Rxd   
);

  //AXI wrapper Tx
  wire [7:0]                        Tx_Data;
  wire                              Tx_Push_Enable;
  wire                              Tx_Full;
  wire                              Tx_Busy;
  wire [$clog2(Fifo_Slots) : 0]     Tx_Occupancy;

  //AXI wrapper Rx
  wire [7:0]                        Rx_Byte;
  wire                              Rx_Pop_Enable;
  wire                              Rx_Ready;
  wire                              Frame_Error;
  wire                              Over_Run_Error;
  wire [$clog2(Fifo_Slots) : 0]     Rx_Occupancy;


  //AXI4-Lite Interface
  Uart_Axi_Lite #(
    .Address_Width(Address_Width),
    .Data_Width(Data_Width)
  ) Axi_Lite (
    .Clk(Clk), 
    .Rst_N(Rst_N),
    .Write_Address(Write_Address), 
    .Write_Address_Valid(Write_Address_Valid), 
    .Write_Address_Ready(Write_Address_Ready),
    .Write_Data(Write_Data), 
    .Write_Data_Valid(Write_Data_Valid), 
    .Write_Data_Ready(Write_Data_Ready),
    .Bresp(Bresp), 
    .Bvalid(Bvalid), 
    .Bready(Bready),
    .Read_Address(Read_Address), 
    .Read_Address_Valid(Read_Address_Valid), 
    .Read_Address_Ready(Read_Address_Ready),
    .Read_Data(Read_Data), 
    .Rresp(Rresp), 
    .Rvalid(Rvalid), 
    .Rready(Rready),
    .Tx_Data(Tx_Data), 
    .Tx_Push_Enable(Tx_Push_Enable), 
    .Tx_Full(Tx_Full), 
    .Tx_Busy(Tx_Busy), 
    .Tx_Occupancy(Tx_Occupancy),
    .Rx_Byte(Rx_Byte), 
    .Rx_Pop_Enable(Rx_Pop_Enable), 
    .Rx_Ready(Rx_Ready),
    .Frame_Error(Frame_Error), 
    .Over_Run_Error(Over_Run_Error), 
    .Rx_Occupancy(Rx_Occupancy)
  );


  //Tx
  Uart_Tx #(
    .Clk_Frequency(Clk_Frequency),
    .Baud_Rate(Baud_Rate),
    .Fifo_Slots(Fifo_Slots)
  ) Transmitter (
    .Clk(Clk), 
    .Rst_N(Rst_N),
    .Data_In(Tx_Data),
    .Push_Enable(Tx_Push_Enable),
    .Tx_Full(Tx_Full),
    .Occupancy(Tx_Occupancy),
    .Tx_Busy(Tx_Busy),
    .Tx(Uart_Txd)
  );

  //Rx
  Uart_Rx #(
    .Clk_Frequency(Clk_Frequency),
    .Baud_Rate(Baud_Rate),
    .Over_Sample(Over_Sample),
    .Fifo_Slots(Fifo_Slots)
  ) Receiver (
    .Clk(Clk), 
    .Reset(Rst_N),            
    .Rx_Data(Uart_Rxd),
    .Pop_Enable(Rx_Pop_Enable),
    .Rx_Ready(Rx_Ready),
    .Occupancy(Rx_Occupancy),
    .Frame_Error(Frame_Error),
    .Over_Run_Error(Over_Run_Error),
    .Data_Out(Rx_Byte)                  
  );


endmodule

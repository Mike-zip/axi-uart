//Michael Marquis
//AXI4-Lite Interface Design


module Uart_Axi_Lite #(
  parameter Address_Width = 4,
  parameter Data_Width	= 32
)(
  input wire Clk,
  input wire Rst_N,

  //AW Channel
  input wire [Address_Width - 1 : 0] 	Write_Address,
  input wire							Write_Address_Valid,
  output reg							Write_Address_Ready,

  //W Channel
  input wire [Data_Width - 1 : 0]		Write_Data,
  input wire 							Write_Data_Valid,
  output reg							Write_Data_Ready,

  //B Channel
  output reg [1 : 0]					Bresp,
  output reg 							Bvalid,
  input wire							Bready,

  //AR Channel
  input wire [Address_Width - 1 : 0]    Read_Address,
  input wire							Read_Address_Valid,
  output reg							Read_Address_Ready,

  //R Channel
  output reg [Data_Width - 1 : 0]		Read_Data,
  output reg [1 : 0]					Rresp,
  output reg							Rvalid,

  //UART_TX Connections
  output reg [7 : 0]					Tx_Data,
  output reg							Tx_Push_Enable,
  input wire							Tx_Full,
  input wire							Tx_Busy,
  input wire [4 : 0]			     	Tx_Occupancy,

  //UART_RX Connections
  input wire [7 : 0]					Rx_Byte,
  output reg							Rx_Pop_Enable,
  input wire							Rx_Ready,
  input wire							Frame_Error,
  input wire							Over_Run_Error,
  input wire [4 : 0]					Rx_Occupancy
);

  //Register Map
  localparam Address_Tx_Data 	= 4'h0;
  localparam Address_Rx_Data 	= 4'h4;
  localparam Address_Status  	= 4'h8;
  localparam Address_Control 	= 4'hC;

  //Control Register
  reg [Data_Width - 1 : 0]  	Control_Register;
  reg Write_Address_Done;
  reg Write_Data_Done;
  //Status Register : Purely Combinational to show live Status
  wire [Data_Width - 1 : 0] 		  Status_Register;
  assign Status_Register[0]			= Tx_Busy;
  assign Status_Register[1]			= Rx_Ready;
  assign Status_Register[2]			= Frame_Error;
  assign Status_Register[3]			= 1'b0; //Null for now
  assign Status_Register[4]			= Over_Run_Error;
  assign Status_Register[5]			= Tx_Full;
  assign Status_Register[10 : 6] 	= Tx_Occupancy;
  assign Status_Register[15 : 11] 	= Rx_Occupancy;
  assign Status_Register[31 : 16] 	= 16'd0; //Null for now

  //Write Channel (AW - W - B)
  always @(posedge Clk or negedge Rst_N) begin
    if(!Rst_N) begin
      Write_Address_Ready	<= 1'b0;
      Write_Data_Ready		<= 1'b0;
      Bvalid				<= 1'b0;
      Bresp					<= 2'b00;
      Tx_Data				<= 8'd0;
      Tx_Push_Enable		<= 1'b0;
      Control_Register		<= {Data_Width{1'b0}};
      Write_Address_Done	<= 1'b0;
      Write_Data_Done		<= 1'b0;
    end
    else begin
      Tx_Push_Enable		<= 1'b0;
      if(Write_Address_Valid && !Write_Address_Done) begin
        Write_Address_Ready	<= 1'b1;
        Write_Address_Done	<= 1'b1;
      end
      else
        Write_Address_Ready	<= 1'b0;

      if(Write_Data_Valid && !Write_Data_Done) begin
        Write_Data_Ready	<= 1'b1;
        Write_Data_Done		<= 1'b1;
      end
      else
        Write_Data_Ready		<= 1'b0;
      if(Write_Address_Done && Write_Data_Done && !Bvalid) begin
        case(Write_Address)
          Address_Tx_Data : begin
            Tx_Data				<= Write_Data[7 : 0];
            Tx_Push_Enable		<= 1'b1;
          end
          Address_Control :  	
            Control_Register 	<= Write_Data;
          default :				
            Bresp 	<= 2'b00; 
        endcase
        Bvalid	<= 1'b1;
        Bresp	<= 2'b00;
      end
      if(Bvalid && Bready) begin
        Bvalid				<= 1'b0;
        Write_Address_Done	<= 1'b0;
        Write_Data_Done		<= 1'b0;
      end
    end
  end

  //Read Channel (AR - R)
  always @(posedge Clk or negedge Rst_N) begin
    if(!Rst_N) begin
      Read_Address_Ready	<= 1'b0;
      Rvalid				<= 1'b0;
      Rresp					<= 2'b00;
      Read_Data				<= {Data_Width{1'b0}};
      Rx_Pop_Enable			<= 1'b0;
    end
    else begin
      Rx_Pop_Enable			<= 1'b0;
      Read_Address_Ready	<= 1'b0;

      if(Read_Address_Valid && !Rvalid) begin
        Read_Address_Ready	<= 1'b1;
        Rresp				<= 2'b00;
        case(Read_Address)
          Address_Status  	:
            Read_Data	<= Status_Register;
          Address_Control 	:
            Read_Data	<= Control_Register;
          default 			: 
            Read_Data 	<= {Data_Width{1'b0}};
        endcase
        Rvalid	<= 1'b1;
      end
      if(Rvalid && Rready)
        Rvalid	<= 1'b0;

    end

    endmodule





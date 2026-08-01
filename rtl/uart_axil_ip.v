//Michael Marquis
//AXI4-Lite named wrapper for block design integration.
//This file only renames pins. The verified core is untouched - the AXI spec
//names face Vivado on the outside, my own names face Uart_Top on the inside.

module Uart_Axi_Lite_Ip #(
  parameter Clk_Frequency = 100_000_000,
  parameter Baud_Rate     = 115_200,
  parameter Over_Sample   = 16,
  parameter Fifo_Slots    = 16
)(
  input  wire        s_axi_aclk,
  input  wire        s_axi_aresetn,

  input  wire [11:0] s_axi_awaddr,
  input  wire [2:0]  s_axi_awprot,     //accepted, unused
  input  wire        s_axi_awvalid,
  output wire        s_axi_awready,

  input  wire [31:0] s_axi_wdata,
  input  wire [3:0]  s_axi_wstrb,      //accepted, unused - writes are full word
  input  wire        s_axi_wvalid,
  output wire        s_axi_wready,

  output wire [1:0]  s_axi_bresp,
  output wire        s_axi_bvalid,
  input  wire        s_axi_bready,

  input  wire [11:0] s_axi_araddr,
  input  wire [2:0]  s_axi_arprot,     //accepted, unused
  input  wire        s_axi_arvalid,
  output wire        s_axi_arready,

  output wire [31:0] s_axi_rdata,
  output wire [1:0]  s_axi_rresp,
  output wire        s_axi_rvalid,
  input  wire        s_axi_rready,

  output wire        Uart_Txd,
  input  wire        Uart_Rxd
);

  Uart_Top #(
    .Clk_Frequency  (Clk_Frequency),
    .Baud_Rate      (Baud_Rate),
    .Over_Sample    (Over_Sample),
    .Fifo_Slots     (Fifo_Slots),
    .Address_Width  (4),
    .Data_Width     (32)
  ) Core (
    .Clk    (s_axi_aclk),
    .Rst_N  (s_axi_aresetn),

    .Write_Address        (s_axi_awaddr[3:0]),
    .Write_Address_Valid  (s_axi_awvalid),
    .Write_Address_Ready  (s_axi_awready),

    .Write_Data        (s_axi_wdata),
    .Write_Data_Valid  (s_axi_wvalid),
    .Write_Data_Ready  (s_axi_wready),

    .Bresp    (s_axi_bresp),
    .Bvalid   (s_axi_bvalid),
    .Bready   (s_axi_bready),

    .Read_Address        (s_axi_araddr[3:0]),
    .Read_Address_Valid  (s_axi_arvalid),
    .Read_Address_Ready  (s_axi_arready),

    .Read_Data  (s_axi_rdata),
    .Rresp      (s_axi_rresp),
    .Rvalid     (s_axi_rvalid),
    .Rready     (s_axi_rready),

    .Uart_Txd  (Uart_Txd),
    .Uart_Rxd  (Uart_Rxd)
  );

endmodule

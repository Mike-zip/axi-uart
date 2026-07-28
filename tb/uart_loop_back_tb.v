//Michael Marquis
//UART Loopback Test Bench

`timescale 1ns/1ps

module Test_Bench;

  //Baud divider = 50MHz / 5MHz -> 10 clocks per bit (sim only)
  localparam	Clk_Frequency_Tb  = 50_000_000;
  localparam	Baud_Rate_Tb      = 5_000_000;
  localparam	Over_Sample_Tb    = 10;
  localparam	Fifo_Slots_Tb     = 16;
  localparam	Address_Width_Tb  = 4;
  localparam	Data_Width_Tb     = 32;
  localparam	Timeout_Ns        = 2_000_000;

  //Register map
  localparam Address_Tx_Data   = 4'h0;
  localparam Address_Rx_Data   = 4'h4;
  localparam Address_Status    = 4'h8;
  localparam Address_Control   = 4'hC;

  reg Clk_Tb;
  reg Rst_N_Tb;

  //AW - W - B
  reg [Address_Width_Tb - 1 : 0]  Write_Address_Tb;
  reg                             Write_Address_Valid_Tb;
  wire                            Write_Address_Ready_Tb;

  reg [Data_Width_Tb - 1 : 0]  Write_Data_Tb;
  reg                          Write_Data_Valid_Tb;
  wire                         Write_Data_Ready_Tb;

  wire [1 : 0]  Bresp_Tb;
  wire          Bvalid_Tb;
  reg           Bready_Tb;

  //AR - R
  reg [Address_Width_Tb - 1 : 0]  Read_Address_Tb;
  reg                             Read_Address_Valid_Tb;
  wire                            Read_Address_Ready_Tb;

  wire [Data_Width_Tb - 1 : 0]  Read_Data_Tb;
  wire [1 : 0]                  Rresp_Tb;
  wire                          Rvalid_Tb;
  reg                           Rready_Tb;

  //Loopback wire : Tx out tied to Rx in
  wire Uart_Loop;


  Uart_Top #(
    .Clk_Frequency  (Clk_Frequency_Tb),
    .Baud_Rate      (Baud_Rate_Tb),
    .Over_Sample    (Over_Sample_Tb),
    .Fifo_Slots     (Fifo_Slots_Tb),
    .Address_Width  (Address_Width_Tb),
    .Data_Width     (Data_Width_Tb)
  ) DUT (
    .Clk                  (Clk_Tb),
    .Rst_N                (Rst_N_Tb),
    .Write_Address        (Write_Address_Tb),
    .Write_Address_Valid  (Write_Address_Valid_Tb),
    .Write_Address_Ready  (Write_Address_Ready_Tb),
    .Write_Data           (Write_Data_Tb),
    .Write_Data_Valid     (Write_Data_Valid_Tb),
    .Write_Data_Ready     (Write_Data_Ready_Tb),
    .Bresp                (Bresp_Tb),
    .Bvalid               (Bvalid_Tb),
    .Bready               (Bready_Tb),
    .Read_Address         (Read_Address_Tb),
    .Read_Address_Valid   (Read_Address_Valid_Tb),
    .Read_Address_Ready   (Read_Address_Ready_Tb),
    .Read_Data            (Read_Data_Tb),
    .Rresp                (Rresp_Tb),
    .Rvalid               (Rvalid_Tb),
    .Rready               (Rready_Tb),
    .Uart_Txd             (Uart_Loop),
    .Uart_Rxd             (Uart_Loop)
  );


  initial begin
    $dumpfile("uart_loopback_tb.vcd");
    $dumpvars(0, Test_Bench);
  end

  integer Error_Loopback  = 0;
  integer Error_Status    = 0;
  integer Error_Timeout   = 0;
  integer i;

  reg [7 : 0]					Test_Bytes [0 : 7];
  reg [Data_Width_Tb - 1 : 0]	Read_Back;
  reg [Data_Width_Tb - 1 : 0]	Status_Word;

  always #10 Clk_Tb = ~Clk_Tb;


  //Timeout Watch : ends the sim if hanging
  task Timeout_Watch(input integer Limit_Ns);
    begin
      #(Limit_Ns);
      $display("\n**TIMEOUT** : exceeded %0d ns - a byte never looped back", Limit_Ns);
      Error_Timeout = 1;
      Print_Summary();
      $finish;
    end
  endtask

  initial Timeout_Watch(Timeout_Ns);


  initial begin
    Test_Bytes[0]	= 8'h41;
    Test_Bytes[1]	= 8'h55;
    Test_Bytes[2]	= 8'hAA;
    Test_Bytes[3]	= 8'h01;
    Test_Bytes[4]	= 8'h80;
    Test_Bytes[5]	= 8'hFF;
    Test_Bytes[6]	= 8'h00;
    Test_Bytes[7]	= 8'hC3;

    Clk_Tb                  = 1'b0;
    Rst_N_Tb                = 1'b1;
    Write_Address_Tb        = 4'd0;
    Write_Address_Valid_Tb  = 1'b0;
    Write_Data_Tb           = 32'd0;
    Write_Data_Valid_Tb     = 1'b0;
    Bready_Tb               = 1'b0;
    Read_Address_Tb         = 4'd0;
    Read_Address_Valid_Tb   = 1'b0;
    Rready_Tb               = 1'b0;

    Reset_DUT();

    for(i = 0; i < 8; i = i + 1) begin

      //CPU writes the byte to transmit
      Axi_Write(Address_Tx_Data, {24'd0, Test_Bytes[i]});

      //Tx -> loop -> Rx into the FIFO
      wait(DUT.Rx_Ready == 1'b1);

      //Status should now show Rx_Ready '1'
      Axi_Read(Address_Status, Status_Word);
      if(Status_Word[1] !== 1'b1) begin
        $display("\nFAIL Status: Rx_Ready bit not set after 0x%02h (status = 0x%08h)", Test_Bytes[i], Status_Word);
        Error_Status = Error_Status + 1;
      end

      //CPU reads the received byte and we compare
      Axi_Read(Address_Rx_Data, Read_Back);
      if(Read_Back[7 : 0] !== Test_Bytes[i]) begin
        $display("\nFAIL Loopback: sent 0x%02h got 0x%02h", Test_Bytes[i], Read_Back[7 : 0]);
        Error_Loopback = Error_Loopback + 1;
      end
      else
        $display("\nPASS Loopback: 0x%02h -> Tx -> Rx -> 0x%02h", Test_Bytes[i], Read_Back[7 : 0]);
    end

    Print_Summary();
    $finish;
  end


  task Axi_Write(input [Address_Width_Tb - 1 : 0] Address, input [Data_Width_Tb - 1 : 0] Data);
    begin
      @(posedge Clk_Tb);
      #1;

      Write_Address_Tb        = Address;
      Write_Address_Valid_Tb  = 1'b1;
      Write_Data_Tb           = Data;
      Write_Data_Valid_Tb     = 1'b1;
      Bready_Tb               = 1'b1;

      wait(Write_Address_Ready_Tb	== 1'b1);
      wait(Write_Data_Ready_Tb		== 1'b1);

      @(posedge Clk_Tb);
      #1;

      Write_Address_Valid_Tb  = 1'b0;
      Write_Data_Valid_Tb     = 1'b0;

      wait(Bvalid_Tb == 1'b1);
      @(posedge Clk_Tb);
      #1;

      Bready_Tb = 1'b0;
    end
  endtask


  task Axi_Read(input [Address_Width_Tb - 1 : 0] Address, output [Data_Width_Tb - 1 : 0] Data);
    begin
      @(posedge Clk_Tb);
      #1;

      Read_Address_Tb        = Address;
      Read_Address_Valid_Tb  = 1'b1;
      Rready_Tb              = 1'b1;

      @(posedge Clk_Tb);
      #1;

      Data					= Read_Data_Tb;
      Read_Address_Valid_Tb	= 1'b0;

      @(posedge Clk_Tb);
      #1;

      Rready_Tb = 1'b0;
    end
  endtask


  task Reset_DUT ();
    begin
      Rst_N_Tb                = 1'b0;
      Write_Address_Valid_Tb  = 1'b0;
      Write_Data_Valid_Tb     = 1'b0;
      Read_Address_Valid_Tb   = 1'b0;
      Bready_Tb               = 1'b0;
      Rready_Tb               = 1'b0;
      repeat (3) @(posedge Clk_Tb);
      Rst_N_Tb                = 1'b1;
      @(posedge Clk_Tb);
    end
  endtask


  task Print_Result (input [8*20 : 1] Name, input integer Error_Count);
    begin
      if(Error_Count == 0)
        $display("  [ PASS ]  %0s", Name);
      else
        $display("  [ FAIL ]  %0s  (%0d errors)", Name, Error_Count);
    end
  endtask


  task Print_Summary ();
    begin
      $display("\n==================================================");
      $display("              UART LOOPBACK SUMMARY");
      $display("==================================================");
      Print_Result("Loopback_Data       ", Error_Loopback);
      Print_Result("Status_Rx_Ready     ", Error_Status);
      Print_Result("Timeout             ", Error_Timeout);
      $display("==================================================");
      if(Error_Loopback + Error_Status + Error_Timeout == 0)
        $display("  OVERALL: ALL TESTS PASSED");
      else
        $display("  OVERALL: FAILURES DETECTED");
      $display("==================================================");
    end
  endtask

endmodule

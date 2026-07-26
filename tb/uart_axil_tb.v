//Michael Marquis
//AXI4-Lite Interface Test Bench

`timescale 1ns/1ps

module Test_Bench;

  localparam Address_Width_Tb	= 4;
  localparam Data_Width_Tb		= 32;
  localparam Timeout_Ns			  = 100_000;

  //Register map
  localparam Address_Tx_Data	= 4'h0;
  localparam Address_Rx_Data	= 4'h4;
  localparam Address_Status		= 4'h8;
  localparam Address_Control	= 4'hC;

  reg Clk_Tb;
  reg Rst_N_Tb;

  //AW - W - B
  reg [Address_Width_Tb - 1 : 0] 	Write_Address_Tb;
  reg								              Write_Address_Valid_Tb;
  wire								            Write_Address_Ready_Tb;

  reg [Data_Width_Tb - 1 : 0]		  Write_Data_Tb;
  reg								              Write_Data_Valid_Tb;
  wire								            Write_Data_Ready_Tb;

  wire [1 : 0]			Bresp_Tb;
  wire							Bvalid_Tb;
  reg								Bready_Tb;

  //AR - R
  reg [Address_Width_Tb - 1 : 0]	Read_Address_Tb;
  reg								              Read_Address_Valid_Tb;
  wire								            Read_Address_Ready_Tb;

  wire [Data_Width_Tb - 1 : 0]		Read_Data_Tb;
  wire [1 : 0]						        Rresp_Tb;
  wire								            Rvalid_Tb;
  reg								              Rready_Tb;

  //Tx
  wire [7 : 0]			Tx_Data_Tb;
  wire							Tx_Push_Enable_Tb;
  reg								Tx_Full_Tb;
  reg								Tx_Busy_Tb;
  reg [4 : 0]				Tx_Occupancy_Tb;

  //Rx
  reg [7 : 0]				Rx_Byte_Tb;
  wire							Rx_Pop_Enable_Tb;
  reg								Rx_Ready_Tb;
  reg								Frame_Error_Tb;
  reg								Over_Run_Error_Tb;
  reg [4 : 0]				Rx_Occupancy_Tb;


  Uart_Axi_Lite #(
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
    .Tx_Data              (Tx_Data_Tb),
    .Tx_Push_Enable       (Tx_Push_Enable_Tb),
    .Tx_Full              (Tx_Full_Tb),
    .Tx_Busy              (Tx_Busy_Tb),
    .Tx_Occupancy         (Tx_Occupancy_Tb),
    .Rx_Byte              (Rx_Byte_Tb),
    .Rx_Pop_Enable        (Rx_Pop_Enable_Tb),
    .Rx_Ready             (Rx_Ready_Tb),
    .Frame_Error          (Frame_Error_Tb),
    .Over_Run_Error       (Over_Run_Error_Tb),
    .Rx_Occupancy         (Rx_Occupancy_Tb)
  );


  initial begin
    $dumpfile("uart_axi_lite_tb.vcd");
    $dumpvars(0, Test_Bench);
  end

  integer Error_Tx_Write			      = 0;
  integer Error_Control_Read_Write  = 0;
  integer Error_Status_Read			    = 0;
  integer Error_Rx_Read				      = 0;
  integer Error_Address_Latch		    = 0;
  integer Error_Timeout				      = 0;

  reg 			Saw_Tx_Push;
  reg [7 : 0] 	Pushed_Byte;
  reg			Saw_Rx_Pop;


  always @(posedge Clk_Tb) begin
    if(Tx_Push_Enable_Tb) begin
      Saw_Tx_Push	<= 1'b1;
      Pushed_Byte	<= Tx_Data_Tb;
    end
    if(Rx_Pop_Enable_Tb)
      Saw_Rx_Pop	<= 1'b1;
  end

  reg [Data_Width_Tb - 1 : 0] Read_Back;

  always #10 Clk_Tb = ~Clk_Tb;

  //Timeout Watch : testbench must finish within certain time or else this task ends it. Stops TestBench from hanging
  task Timeout_Watch(input integer Limit_Ns);
    begin
      #(Limit_Ns);
      $display("\n**TIMEOUT** : exceeded %0d ns", Limit_Ns);
      Error_Timeout = 1;
      Print_Summary();
      $finish;
    end
  endtask

  initial Timeout_Watch(Timeout_Ns);


  initial begin
    Clk_Tb                 = 1'b0;
    Rst_N_Tb               = 1'b1;
    Write_Address_Tb       = 4'd0;
    Write_Address_Valid_Tb = 1'b0;
    Write_Data_Tb          = 32'd0;
    Write_Data_Valid_Tb    = 1'b0;
    Bready_Tb              = 1'b0;
    Read_Address_Tb        = 4'd0;
    Read_Address_Valid_Tb  = 1'b0;
    Rready_Tb              = 1'b0;
    Tx_Full_Tb             = 1'b0;
    Tx_Busy_Tb             = 1'b0;
    Tx_Occupancy_Tb        = 5'd0;
    Rx_Byte_Tb             = 8'd0;
    Rx_Ready_Tb            = 1'b0;
    Frame_Error_Tb         = 1'b0;
    Over_Run_Error_Tb      = 1'b0;
    Rx_Occupancy_Tb        = 5'd0;
    Saw_Tx_Push            = 1'b0;
    Saw_Rx_Pop             = 1'b0;

    Reset_DUT();

    //1: Write Tx_Data
    Saw_Tx_Push = 1'b0;
    Axi_Write(Address_Tx_Data, 32'h0000_0041);

    if(!Saw_Tx_Push || Pushed_Byte !== 8'h41) begin
      $display("\nFAIL Tx_Write: Saw_Push= %0b Pushed= 0x%02h 'expected push of 0x41'", Saw_Tx_Push, Pushed_Byte);
      Error_Tx_Write = Error_Tx_Write + 1;
    end
    else
      $display("\nPASS Tx_Write: pushed 0x%02h to TX", Pushed_Byte);

    //2: Write then read Control
    Axi_Write(Address_Control, 32'hBADD_BAAD);
    Axi_Read(Address_Control, Read_Back);

    if(Read_Back !== 32'hBADD_BAAD) begin
      $display("\nFAIL Control_Read_Write: read 0x%08h 'expected 0xBADDBAAD'", Read_Back);
      Error_Control_Read_Write = Error_Control_Read_Write + 1;
    end
    else
      $display("\nPASS Control_Read_Write: 0x%08h", Read_Back);

    //3: Read Status & make sure live inputs land in the right fields
    Tx_Busy_Tb 			  = 1;
    Rx_Ready_Tb 		  = 1;
    Frame_Error_Tb 		= 1;
    Over_Run_Error_Tb	= 1;
    Tx_Full_Tb			  = 1;
    Tx_Occupancy_Tb		= 5'h05;
    Rx_Occupancy_Tb		= 5'h0A;
    @(posedge Clk_Tb);

    Axi_Read(Address_Status, Read_Back);
    if(Read_Back !== 32'h0000_5177) begin
      $display("\nFAIL Status_Read: read 0x%08h (expected 0x00005177)", Read_Back);
      Error_Status_Read = Error_Status_Read + 1;
    end
    else 
      $display("\nPASS Status_Read: 0x%08h", Read_Back);
    Tx_Busy_Tb 			  = 0;
    Rx_Ready_Tb 		  = 0;
    Frame_Error_Tb 		= 0;
    Over_Run_Error_Tb = 0;
    Tx_Full_Tb 			  = 0;
    Tx_Occupancy_Tb 	= 0;
    Rx_Occupancy_Tb 	= 0;

    //4: Read Rx_Data 
    Rx_Byte_Tb = 8'h5A;
    Saw_Rx_Pop = 1'b0;
    @(posedge Clk_Tb);

    Axi_Read(Address_Rx_Data, Read_Back);
    if(Read_Back[7 : 0] !== 8'h5A || !Saw_Rx_Pop) begin
      $display("\nFAIL Rx_Read: Data= 0x%02h Saw_Pop= %0b 'expected 0x5A + pop'", Read_Back[7 : 0], Saw_Rx_Pop);
      Error_Rx_Read = Error_Rx_Read + 1;
    end
    else
      $display("\nPASS Rx_Read: 0x%02h with pop", Read_Back[7 : 0]);

    //5: Address Latch : Master drops the address after AW handshake
    Reset_DUT();
    Saw_Tx_Push = 1'b0;
    Axi_Write_Drop_Address(Address_Tx_Data, Address_Control, 32'h0000_0099);
    if(!Saw_Tx_Push || Pushed_Byte !== 8'h99 || DUT.Control_Register !== 0) begin
      $display("\nFAIL Address_Latch: Saw_Push= %0b Pushed= 0x%02h Control= 0x%08h", Saw_Tx_Push, Pushed_Byte, DUT.Control_Register);
      Error_Address_Latch = Error_Address_Latch + 1;
    end
    else
      $display("\nPASS Address_Latch: byte reached TX despite dropped address");

    Print_Summary();
    $finish;
  end


  //Master drops | refuses the @ bus after AW but before W -> Testing the AW Latch
  //Decoy represents the  master moving on 
  task Axi_Write_Drop_Address (input [Address_Width_Tb-1:0] Intended, input [Address_Width_Tb-1:0] Decoy, input [Data_Width_Tb-1:0] Data);
    begin
      @(posedge Clk_Tb);
      #1;

      Write_Address_Tb			= Intended;
      Write_Address_Valid_Tb	= 1'b1;

      wait(Write_Address_Ready_Tb == 1'b1); 
      @(posedge Clk_Tb);
      #1;

      Write_Address_Valid_Tb	= 1'b0;
      Write_Address_Tb			= Decoy;

      repeat (3) @(posedge Clk_Tb);
      #1;

      Write_Data_Tb				= Data;
      Write_Data_Valid_Tb		= 1'b1;
      Bready_Tb					= 1'b1;

      wait(Write_Data_Ready_Tb == 1'b1);
      @(posedge Clk_Tb);
      #1;

      Write_Data_Valid_Tb		= 1'b0;

      wait(Bvalid_Tb == 1'b1);
      @(posedge Clk_Tb);
      #1;

      Bready_Tb	= 1'b0;
    end
  endtask


  task Axi_Read(input [Address_Width_Tb - 1 : 0] Address, output [Data_Width_Tb - 1 : 0] Data);
    begin
      @(posedge Clk_Tb);
      #1;

      Read_Address_Tb		= Address;
      Read_Address_Valid_Tb = 1'b1;
      Rready_Tb				= 1'b1;

      @(posedge Clk_Tb);
      #1;

      Data					= Read_Data_Tb;
      Read_Address_Valid_Tb = 1'b0;

      @(posedge Clk_Tb);
      #1;

      Rready_Tb = 1'b0;
    end
  endtask


  task Axi_Write(input [Address_Width_Tb - 1 : 0] Address, input [Data_Width_Tb - 1 : 0] Data);
    begin
      @(posedge Clk_Tb);
      #1;

      Write_Address_Tb			= Address;
      Write_Address_Valid_Tb	= 1'b1;
      Write_Data_Tb				= Data;
      Write_Data_Valid_Tb		= 1'b1;
      Bready_Tb					= 1'b1;
      wait(Write_Address_Ready_Tb 	== 1'b1);
      wait(Write_Data_Ready_Tb    	== 1'b1);

      @(posedge Clk_Tb);
      #1;

      Write_Address_Valid_Tb	= 1'b0;
      Write_Data_Valid_Tb		= 1'b0;

      wait(Bvalid_Tb == 1'b1);
      @(posedge Clk_Tb);
      #1;

      Bready_Tb = 1'b0;
    end
  endtask



  task Reset_DUT ();
    begin
      Rst_N_Tb               = 1'b0;
      Write_Address_Valid_Tb = 1'b0;
      Write_Data_Valid_Tb    = 1'b0;
      Read_Address_Valid_Tb  = 1'b0;
      Bready_Tb              = 1'b0;
      Rready_Tb              = 1'b0;
      repeat (3) @(posedge Clk_Tb);
      Rst_N_Tb               = 1'b1;
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
      $display("              AXI4-LITE TEST SUMMARY");
      $display("==================================================");
      Print_Result("Tx_Data_Write       ", Error_Tx_Write);
      Print_Result("Control_ReadWrite   ", Error_Control_Read_Write);
      Print_Result("Status_Read         ", Error_Status_Read);
      Print_Result("Rx_Data_Read        ", Error_Rx_Read);
      Print_Result("Write_Addr_Latch    ", Error_Address_Latch);
      Print_Result("Watchdog_Timeout    ", Error_Timeout);
      $display("==================================================");
      if(Error_Tx_Write + Error_Control_Read_Write + Error_Status_Read + Error_Rx_Read + Error_Address_Latch + Error_Timeout == 0)
        $display("  OVERALL: ALL TESTS PASSED");
      else
        $display("  OVERALL: FAILURES DETECTED");
      $display("==================================================");
    end
  endtask
endmodule

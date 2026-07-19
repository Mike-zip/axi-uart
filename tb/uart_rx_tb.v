//Michael Marquis
//UART_RX_TESTBENCH

`timescale 1ns/1ps

module Test_Bench;

  //Baud division => Clk_Tb / Baud_Rate_Tb -> 10 : only for the sim.
  //Each bit will only be 10 clock cycles instead of 50MHz/ 9600 -> '5208'

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
  wire 			Over_Run_Error_Tb;
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

  integer Error_Recieve = 0;
  integer Error_Bad_Frame = 0;
  integer Error_Over_Run = 0;
  integer Error_Pop_Read = 0;
  integer Error_Sync_Latency = 0;
  integer Error_Simultaneous_Push_Pop = 0;
  integer Error_Reset_Mid_Frame = 0;

  integer Latency0, Latency1;
  integer B;

  always #10 Clk_Tb = ~Clk_Tb;

  initial begin
    Clk_Tb			= 1'b0;
    Reset_Tb 		= 1'b0;
    Rx_Data_Tb		= 8'd1;
    Pop_Enable_Tb	= 1'b0;
    #100;
    Reset_Tb 		= 1'b1;

    @(posedge Clk_Tb);
    Reset_DUT();
    for(B = 0; B < 256; B = B + 1) begin
      Recieve_Byte	(B [7 : 0]); 
      Send_Bad_Frame	(B [7 : 0]);
    end
    Reset_DUT();
    Over_Run_Error_Check();
    Reset_DUT();
    Reset_Mid_Frame_Check();
    Reset_DUT();
    Pop_And_Read_Check();
    Reset_DUT();
    Simultaneous_Push_Pop_Check();
    Reset_DUT();
    Measure_Sync_Latency(1'b1, Latency1);
    Measure_Sync_Latency(1'b0, Latency0);
    $display("\nMeasured Synchronizer Latency: Rise= %0d Clocks, Fall= %0d Clocks", Latency1, Latency0);

    if(Latency1 == 2 && Latency0 == 2)
      $display("\nPASS: 2-FF Synchronizer Latency Confirmed = 2 clocks");
    else begin
      $display("\nFAIL: 2-FF Unexpected Synchronizer Latency");
      Error_Sync_Latency = Error_Sync_Latency + 1; 
    end

    if(Error_Recieve + Error_Bad_Frame + Error_Over_Run + Error_Pop_Read + Error_Sync_Latency + Error_Simultaneous_Push_Pop + Error_Reset_Mid_Frame == 0)
      $display("\nPASS: ALL CASES PASSED\n");
    else
      $display("\nFAIL: Erros<%0d>\n", Error_Recieve + Error_Bad_Frame + Error_Over_Run + Error_Pop_Read + Error_Sync_Latency + Error_Simultaneous_Push_Pop + Error_Reset_Mid_Frame);
    Print_Summary();
    $finish;
  end 


  task Reset_Mid_Frame_Check ();
    reg [7 : 0] Byte_Value;
    begin
      Byte_Value = 8'hA5;

      Rx_Data_Tb = 1'b0;
      repeat (Over_Sample_Tb) @(posedge Clk_Tb);
      Rx_Data_Tb = Byte_Value[0];
      repeat (Over_Sample_Tb / 2) @(posedge Clk_Tb);
      Reset_Tb = 1'b0;
      repeat (2) @(posedge Clk_Tb);
      Reset_Tb = 1'b1;
      @(posedge Clk_Tb);

      if(DUT.State !== 2'd0) begin
        $display("\nFAIL Reset_Mid_Frame_Check: State did not return to idle: State = %0s", State_Name(DUT.State));
        Error_Reset_Mid_Frame = Error_Reset_Mid_Frame + 1;
      end

      if(DUT.Read_Pointer !== 0 || DUT.Write_Pointer !== 0) begin
        $display("\nFail Reset_Mid_Frame_Check: Read_Pointer or Write_Pointer not cleared on Reset_Tb: WP = %0d, RP = %0d", DUT.Write_Pointer, DUT.Read_Pointer);
        Error_Reset_Mid_Frame = Error_Reset_Mid_Frame + 1;
      end

      if(DUT.Frame_Error !== 1'b0 || DUT.Over_Run_Error !== 1'b0) begin
        $display("\nFAIL Reset_Mid_Frame_Check: Frame or Over_Run flags not cleared on Reset_Tb: Frame = %0b, Over_Run = %0b", DUT.Frame_Error, DUT.Over_Run_Error);
        Error_Reset_Mid_Frame = Error_Reset_Mid_Frame + 1;
      end

      if(Error_Reset_Mid_Frame == 0) 
        $display("\nPASS Reset_Mid_Frame_Check");


      Rx_Data_Tb = 1'b1;
      repeat (2) @(posedge Clk_Tb);
      Recieve_Byte (8'h3C);

    end

  endtask


  task Simultaneous_Push_Pop_Check;
    reg [7 : 0] Byte_Value;
    integer Pushed;
    integer Popped;
    integer Occ_Prev;
    integer Occ_Now;
    reg 	Saw_Concurrent;
    integer i; 
    integer j; 
    integer k; 
    begin
      Pop_Enable_Tb = 1'b0;
      Pushed = 0;
      Popped = 0;
      Saw_Concurrent = 1'b0;

      for (i = 0; i < 6; i = i + 1) begin
        Byte_Value = 8'hA0 + i;
        @(posedge Clk_Tb);
        Rx_Data_Tb = 1'b0;
        repeat (Over_Sample_Tb) @(posedge Clk_Tb);
        for (k = 0; k < 8; k = k + 1) begin
          Rx_Data_Tb = Byte_Value[k];
          repeat (Over_Sample_Tb) @(posedge Clk_Tb);
        end
        Rx_Data_Tb = 1'b1;
        repeat (Over_Sample_Tb) @(posedge Clk_Tb);
        Pushed = Pushed + 1;
      end

      Pop_Enable_Tb = 1'b1;

      for (j = 0; j < 6; j = j + 1) begin
        Byte_Value = 8'hB0 + j;
        @(posedge Clk_Tb);
        Rx_Data_Tb = 1'b0;
        repeat (Over_Sample_Tb) @(posedge Clk_Tb);
        for (k = 0; k < 8; k = k + 1) begin
          Rx_Data_Tb = Byte_Value[k];
          repeat (Over_Sample_Tb) @(posedge Clk_Tb);
        end
        Rx_Data_Tb = 1'b1;

        Occ_Prev = DUT.Write_Pointer - DUT.Read_Pointer;
        @(posedge Clk_Tb);

        while (DUT.Byte_Valid !== 1'b1)
          @(posedge Clk_Tb);

        Occ_Now = DUT.Write_Pointer - DUT.Read_Pointer;

        if ((DUT.Pop_Enable === 1'b1) && (Occ_Now == Occ_Prev))
          Saw_Concurrent = 1'b1;

        Pushed = Pushed + 1;
        repeat (Over_Sample_Tb) @(posedge Clk_Tb);
      end

      while (DUT.Read_Pointer !== DUT.Write_Pointer)
        @(posedge Clk_Tb);

      Pop_Enable_Tb = 1'b0;
      Popped = Pushed;

      if (Saw_Concurrent !== 1'b1) begin
        $display("\nFAIL: never observed a same-edge push and pop");
        Error_Simultaneous_Push_Pop = Error_Simultaneous_Push_Pop + 1;
      end else if ((DUT.Over_Run_Error === 1'b1) || (DUT.Write_Pointer !== DUT.Read_Pointer)) begin
        $display("\nFAIL: fifo not drained or overrun Wr=%0d Rd=%0d OverRun=%0b", 
                 DUT.Write_Pointer, DUT.Read_Pointer, DUT.Over_Run_Error);
        Error_Simultaneous_Push_Pop = Error_Simultaneous_Push_Pop + 1;
      end else
        $display("\nPASS: Simultaneous push and pop, Pushed=%0d Popped=%0d", Pushed, Popped);
    end
  endtask

  task Pop_And_Read_Check;
    reg [7 : 0] Byte_Value;
    integer i; 
    integer k; 
    integer o; 
    begin
      Pop_Enable_Tb = 1'b0;

      for(i = 0; i < Fifo_Slots_Tb; i = i + 1) begin
        Byte_Value = i[7 : 0];
        @(posedge Clk_Tb);
        Rx_Data_Tb = 1'b0;
        repeat (Over_Sample_Tb) @(posedge Clk_Tb);
        for(k = 0; k < 8; k = k + 1) begin
          Rx_Data_Tb = Byte_Value[k];
          repeat (Over_Sample_Tb) @(posedge Clk_Tb);
        end
        Rx_Data_Tb = 1'b1;
        repeat (Over_Sample_Tb) @(posedge Clk_Tb);
      end

      for(o = 0; o < 16; o = o + 1) begin
        Pop_Enable_Tb = 1'b1;
        @(posedge Clk_Tb);
        Pop_Enable_Tb = 1'b0;
        if(Data_Out_Tb !== o[7 : 0]) begin
          $display("\nFAIL: %0b", Data_Out_Tb);
          Error_Pop_Read = Error_Pop_Read + 1;
        end
        else 
          $display("PASS: Index %0b = %0b", o, Data_Out_Tb);
      end
    end
  endtask

  task Over_Run_Error_Check;
    integer Visible;
    reg [7 : 0] Fifo_Visible [0 : 16];
    integer i; 
    integer k; 
    integer m; 
    integer p; 
    begin
      Pop_Enable_Tb = 1'b0;
      for(i = 0; i < Fifo_Slots_Tb + 1; i = i + 1) begin
        @(posedge Clk_Tb);
        Rx_Data_Tb = 1'b0;
        repeat (Over_Sample_Tb) @(posedge Clk_Tb);
        for(k = 0; k < 8; k = k + 1) begin
          Rx_Data_Tb = 1'b1;
          repeat (Over_Sample_Tb) @(posedge Clk_Tb);
        end
        Rx_Data_Tb = 1'b1;
        repeat (Over_Sample_Tb) @(posedge Clk_Tb);
      end

      Visible = DUT.Over_Run_Error;
      for(m = 0; m < 16; m = m + 1) begin
        for(p = 0; p < 8; p = p + 1) begin
          Fifo_Visible[m] [p] = DUT.Fifo_Memory_Hold[m][p];
        end
        $display("Input Into FIFO Slots= %0b|Index= %0d ", Fifo_Visible[m], m);
      end

      if(DUT.Over_Run_Error != 1'b1) begin
        $display("\nFAIL: 'Over_Run_Error' did not assert to '1' Value= %0b", DUT.Over_Run_Error);
        Error_Over_Run = Error_Over_Run + 1;
      end
      else
        $display("\nPASS: 'Over_Run_Error' asserted to : %0b", DUT.Over_Run_Error);
    end
  endtask

  task Send_Bad_Frame (input [7 : 0] Bits);   
    integer i; 
    integer Write_Pointer_Before;
    begin
      Rx_Data_Tb = 1'b1;
      repeat (Over_Sample_Tb) @(posedge Clk_Tb);
      Rx_Data_Tb = 1'b0;
      repeat (3)  @(posedge Clk_Tb);
      Rx_Data_Tb = 1'b1;
      repeat (7)  @(posedge Clk_Tb);

      if(DUT.State !== 2'b00) begin
        $display("\nFAIL: Failed Idle With Bad Start Bit State= %s", State_Name(DUT.State));
        Error_Bad_Frame = Error_Bad_Frame + 1;
      end
      else
        $display("\nPASS: Bad Start Bit => Idle");

      //Bad Stop Bit Below
      Write_Pointer_Before = DUT.Write_Pointer;
      Rx_Data_Tb = 1'b0;
      repeat(Over_Sample_Tb) @(posedge Clk_Tb);
      for(i = 0; i < 8; i = i + 1) begin
        Rx_Data_Tb = Bits[i];
        repeat (Over_Sample_Tb) @(posedge Clk_Tb);
      end
      Rx_Data_Tb = 1'b0;
      repeat(Over_Sample_Tb) @(posedge Clk_Tb);
      if(DUT.Frame_Error !== 1'b1) begin
        $display("\nFAIL: Failed To Throw 'Frame_Error' : %0b", DUT.Frame_Error);
        Error_Bad_Frame = Error_Bad_Frame + 1;
      end
      else
        $display("\nPASS: Threw The 'Frame_Error'");

      //clean transition to 'Idle'
      Rx_Data_Tb = 1'b1;
      wait(DUT.State == 2'b00);
      repeat (2) @(posedge Clk_Tb);

      if(DUT.Write_Pointer !== Write_Pointer_Before) begin
        $display("\nFAIL: bad frame was pushed into the FIFO: WP_Before = %0d, WP_After = %0d", Write_Pointer_Before, DUT.Write_Pointer);
        Error_Bad_Frame = Error_Bad_Frame + 1;
      end
      else
        $display("\nPASS: bad frame did not enter FIFO");
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

  task Recieve_Byte (input [7 : 0] Bits); 
    integer i; 
    begin
      @(posedge Clk_Tb);
      $display("START VALUES: Rx_Shift_In: %b State: %s", DUT.Rx_Shift_In, State_Name(DUT.State));
      Rx_Data_Tb = 1'b0;
      repeat(Over_Sample_Tb) @(posedge Clk_Tb);
      for(i = 0; i < 8; i = i + 1) begin
        Rx_Data_Tb = Bits[i];
        repeat(Over_Sample_Tb) @(posedge Clk_Tb);    
        $display("WORK VALUES:  Rx_Shift_In: %b State: %s, i: %0d", DUT.Rx_Shift_In, State_Name(DUT.State), i);
      end
      Rx_Data_Tb = 1'b1;
      repeat(Over_Sample_Tb) @(posedge Clk_Tb);
      $display("END VALUES:   Rx_Shift_In: %b State: %s", DUT.Rx_Shift_In, State_Name(DUT.State));

      wait(Rx_Ready_Tb == 1'b1);
      begin
        Pop_Enable_Tb = 1'b1;
        repeat (2) @(posedge Clk_Tb);

        if(Bits !== Data_Out_Tb) begin
          Error_Recieve = Error_Recieve + 1;
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
    end
  endtask

  task Reset_DUT ();
    begin
      Rx_Data_Tb 	= 1'b1;
      Pop_Enable_Tb	= 1'b0;
      Reset_Tb		= 1'b0;
      repeat (2) @(posedge Clk_Tb);
      Reset_Tb		= 1'b1;
      @(posedge Clk_Tb);
    end
  endtask

  function [8*5 : 1] State_Name (input [1:0] Name_State); 
    case(Name_State)
      2'd0:		State_Name =	"Idle";
      2'd1:		State_Name =	"Start";
      2'd2:		State_Name = 	"Data";
      2'd3:		State_Name = 	"Stop";
      default:	State_Name = 	"ERROR";
    endcase
  endfunction

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
      $display("                  TEST SUMMARY");
      $display("==================================================");
      Print_Result("Recieve_Byte        ", Error_Recieve);
      Print_Result("Send_Bad_Frame      ", Error_Bad_Frame); 
      Print_Result("Over_Run_Error_Check", Error_Over_Run);
      Print_Result("Pop_And_Read_Check  ", Error_Pop_Read);
      Print_Result("Sync_Latency        ", Error_Sync_Latency);
      Print_Result("Simul_Push_Pop      ", Error_Simultaneous_Push_Pop);
      Print_Result("Reset_Mid_Frame     ", Error_Reset_Mid_Frame);
      $display("==================================================");
      if(Error_Recieve + Error_Bad_Frame + Error_Over_Run + Error_Pop_Read + Error_Sync_Latency + Error_Simultaneous_Push_Pop + Error_Reset_Mid_Frame == 0)
        $display("  OVERALL: ALL TESTS PASSED");
      else
        $display("  OVERALL: FAILURES DETECTED");
      $display("==================================================\n");
    end
  endtask

endmodule

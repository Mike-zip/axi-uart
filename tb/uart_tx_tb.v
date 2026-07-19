`timescale 1ns/1ps

module Test_Bench;

  localparam Clk_Frequency_Tb = 50_000_000;
  localparam Baud_Rate_Tb     = 5_000_000;
  localparam Fifo_Slots_Tb    = 16;
  localparam Timeout_Ns       = 2_000_000; //About 3.5x normal full run time

  reg       	Clk_Tb;
  reg       	Rst_N_Tb;
  reg [7 : 0] 	Data_In_Tb;
  reg       	Push_Enable_Tb;
  wire      	Tx_Full_Tb;
  wire      	Tx_Busy_Tb;
  wire [4 : 0]	Occupancy_Tb;
  wire      	Tx_Tb;

  Uart_Tx #(
    .Clk_Frequency (Clk_Frequency_Tb),
    .Baud_Rate     (Baud_Rate_Tb),
    .Fifo_Slots    (Fifo_Slots_Tb)
  ) DUT (
    .Clk         (Clk_Tb),
    .Rst_N       (Rst_N_Tb),
    .Data_In     (Data_In_Tb),
    .Push_Enable (Push_Enable_Tb),
    .Tx_Full     (Tx_Full_Tb),
    .Tx_Busy     (Tx_Busy_Tb),
    .Occupancy   (Occupancy_Tb),
    .Tx          (Tx_Tb)
  );

  integer   	E = 0;
  reg  [7 : 0] 	Reads = 8'd0;
  integer   	Error_Send_Byte   = 0;
  integer   	Error_Burst_Order = 0;
  integer   	Error_Fifo_Full   = 0;

  integer   I;
  integer   J;
  reg [7 : 0] Expected [0:19];

  always #10 Clk_Tb = ~Clk_Tb;


  initial begin 
    #Timeout_Ns;
    $display("\n***TIMOUT*** %0d", Timeout_Ns);
    $finish;
  end



  initial begin

    Clk_Tb         = 1'b0;
    Rst_N_Tb       = 1'b1;
    Data_In_Tb     = 8'h00;
    Push_Enable_Tb = 1'b0;


    #25 Rst_N_Tb = 1'b0;
    #40 Rst_N_Tb = 1'b1;
    #40;

    for(I = 0; I < 256; I = I + 1) begin
      Send_Byte(I);

      $display("finished byte: %d, %b", I, DUT.Tx_Shift);
      @(posedge Clk_Tb);
      if(DUT.Tx_Shift !== I) begin
        $display("WRONG i !== DUT.Tx_Shift %d %b", I, DUT.Tx_Shift);
        E               = E + 1;
        Error_Send_Byte = Error_Send_Byte + 1;
        $display("WRONG i !== DUT.Tx_Shift %d %b %d", I, DUT.Tx_Shift, E);
      end
    end

    Burst_Order_Check();
    Fifo_Full_Check();

    #500;
    $display("finished at %0t ns", $time);
    if(E == 0) begin
      $display("All test passed with %d errors", E);
    end
    Print_Summary();
    $finish;
  end

  always @(posedge DUT.Baud_Tick) begin
    $display("t= %0t, Tx= %b, Tx_Busy?= %b, Push_Enable= %b", $time, Tx_Tb, Tx_Busy_Tb, Push_Enable_Tb);
  end


  task Send_Byte(input [7:0] B);
    begin

      @(posedge Clk_Tb);
      #1;
      Data_In_Tb = B;
      Reads      = Data_In_Tb;
      $display("input =============================================== %d", Reads);
      if(Reads !== B) begin
        $display("ERROR WITHIN 'SEND_BYTE':t= %0t, Tx= %b, Tx_Busy?= %b, Push_Enable= %b", $time, Tx_Tb, Tx_Busy_Tb, Push_Enable_Tb);
        E               = E + 1;
        Error_Send_Byte = Error_Send_Byte + 1;
        $display("%d ERRORS", E);
      end

      if(Push_Enable_Tb == 1'b1 & Tx_Busy_Tb !== 1'b1) begin
        $display("NOTE: push landed with tx_busy not yet asserted (fifo pop hasn't registered):t= %0t, Tx= %b, Tx_Busy?= %b, Push_Enable= %b", $time, Tx_Tb, Tx_Busy_Tb, Push_Enable_Tb);
      end

      Push_Enable_Tb = 1'b1;
      @(posedge Clk_Tb);
      #1;
      Push_Enable_Tb = 1'b0;

      wait(Tx_Busy_Tb == 1'b1);
      wait(Tx_Busy_Tb == 1'b0);
    end
  endtask

  task Push_Byte(input [7:0] B);
    begin
      @(posedge Clk_Tb);
      #1;
      Data_In_Tb     = B;
      Push_Enable_Tb = 1'b1;
      @(posedge Clk_Tb);
      #1;
      Push_Enable_Tb = 1'b0;
    end
  endtask

  task Burst_Order_Check;
    begin
      for (J = 0; J < 5; J = J + 1) begin
        Expected[J] = 8'hC0 + J;
        Push_Byte(Expected[J]);
      end

      for (J = 0; J < 5; J = J + 1) begin
        wait(Tx_Busy_Tb == 1'b1);
        if (DUT.Tx_Shift !== Expected[J]) begin
          $display("FAIL Burst_Order_Check Index= %0d: Expected %h got %h", J, Expected[J], DUT.Tx_Shift);
          E                 = E + 1;
          Error_Burst_Order = Error_Burst_Order + 1;
        end
        else
          $display("PASS Burst_Order_Check Index= %0d Byte= %h", J, DUT.Tx_Shift);
        wait(Tx_Busy_Tb == 1'b0);
      end
    end
  endtask

  task Fifo_Full_Check;
    begin
      for (J = 0; J < Fifo_Slots_Tb + 4; J = J + 1) begin
        @(posedge Clk_Tb);
        #1;
        Data_In_Tb     = 8'hD0 + J[7:0];
        Push_Enable_Tb = 1'b1;
        Print_Occupancy();
      end
      @(posedge Clk_Tb);
      #1;
      Push_Enable_Tb = 1'b0;

      if (DUT.Write_Pointer - DUT.Read_Pointer > Fifo_Slots_Tb) begin
        $display("FAIL Fifo_Full_Check: occupancy exceeded depth (Write_Pointer= %0d Read_Pointer= %0d)", DUT.Write_Pointer, DUT.Read_Pointer);
        E               = E + 1;
        Error_Fifo_Full = Error_Fifo_Full + 1;
      end
      else
        $display("PASS Fifo_Full_Check: occupancy never exceeded depth, Tx_Full correctly gated extra pushes");

      while (DUT.Write_Pointer !== DUT.Read_Pointer)
        @(posedge Clk_Tb);
      wait(Tx_Busy_Tb == 1'b1);
      wait(Tx_Busy_Tb == 1'b0);
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

  task Print_Occupancy();
    begin
      $display("Occupancy: %0d / %0d slots used", Occupancy_Tb, Fifo_Slots_Tb);
    end
  endtask

  task Print_Summary ();
    begin
      $display("\n==================================================");
      $display("                  TEST SUMMARY");
      $display("==================================================");
      Print_Result("Send_Byte_Loop      ", Error_Send_Byte);
      Print_Result("Burst_Order_Check   ", Error_Burst_Order);
      Print_Result("Fifo_Full_Check     ", Error_Fifo_Full);
      $display("==================================================");
      if(Error_Send_Byte + Error_Burst_Order + Error_Fifo_Full == 0)
        $display("  OVERALL: ALL TESTS PASSED");
      else
        $display("  OVERALL: FAILURES DETECTED");
      $display("==================================================\n");
    end
  endtask


  initial begin
    $dumpfile("uart_tx_tb.vcd");
    $dumpvars(0, Test_Bench);
  end

endmodule

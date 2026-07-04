// Michael Marquis
// Test Bench for TX module

`timescale 1ns/1ps

module Test_Bench;

    //baud division => Clk_Tb / Baud_Rate_Tb -> 10 : only for the sim.
    //each bit will only be 10 clock cycles instead of 50MHz/ 9600 -> '5208'
    localparam Clk_Frequency_Tb = 50_000_000;
    localparam Baud_Rate_Tb     = 5_000_000;

    //DUT connections
    reg       Clk_Tb;
    reg       Rst_N_Tb;
    reg [7:0] Data_In_Tb;
    reg       Tx_Start_Tb;
    wire      Tx_Busy_Tb;
    wire      Tx_Tb;

    Uart_Tx #(
        .Clk_Frequency (Clk_Frequency_Tb),
        .Baud_Rate     (Baud_Rate_Tb)
    ) DUT (
        .Clk      (Clk_Tb),
        .Rst_N    (Rst_N_Tb),
        .Data_In  (Data_In_Tb),
        .Tx_Start (Tx_Start_Tb),
        .Tx_Busy  (Tx_Busy_Tb),
        .Tx       (Tx_Tb)
    );

    integer   E = 0;
    reg [7:0] Reads = 8'd0;

    always #10 Clk_Tb = ~Clk_Tb;

    task Send_Byte(input [7:0] B);
        begin

            @(posedge Clk_Tb);
            #1;
            Data_In_Tb = B;
            Reads      = Data_In_Tb;
            $display("input =============================================== %d", Reads);
            if(Reads !== B) begin
                $error("ERROR WITHIN 'SEND_BYTE':t=%0t, tx=%b, tx_busy?=%b, tx_start=%b", $time, Tx_Tb, Tx_Busy_Tb, Tx_Start_Tb);
                E = E + 1;
                $display("%d ERRORS", E);
            end

            if(Tx_Start_Tb == 1'b1 & Tx_Busy_Tb !== 1'b1) begin
                $error("ERROR WITHIN 'SEND_BYTE | start bit high when tx busy is not':t=%0t, tx=%b, tx_busy?=%b, tx_start=%b", $time, Tx_Tb, Tx_Busy_Tb, Tx_Start_Tb);
                E = E + 1;
                $display("%d ERRORS", E);
            end

            Tx_Start_Tb = 1'b1;
            @(posedge Clk_Tb);
            #1;
            Tx_Start_Tb = 1'b0;

            wait(Tx_Busy_Tb == 1'b1);
            wait(Tx_Busy_Tb == 1'b0);
        end
    endtask

    initial begin

        Clk_Tb      = 1'b0;
        Rst_N_Tb    = 1'b1;
        Data_In_Tb  = 8'h00;
        Tx_Start_Tb = 1'b0;

        //active low reset to begin

        #25 Rst_N_Tb = 1'b0;
        #40 Rst_N_Tb = 1'b1;
        #40;

        for(int I = 0; I < 256; I = I + 1) begin
            Send_Byte(I);

            $display("finished byte: %d, %b", I, DUT.Tx_Shift);
            @(posedge Clk_Tb);
            if(DUT.Tx_Shift !== I) begin
                $display("WRONG i !== DUT.Tx_Shift %d %b", I, DUT.Tx_Shift);
                E = E + 1;
                $error("WRONG i !== DUT.Tx_Shift %d %b %d", I, DUT.Tx_Shift, E);
            end
        end


        #500;
        $display("finished at %0t ns", $time);
        if(E == 0) begin
            $display("All test passed with %d errors", E);
        end
        $finish;
    end



    always @(posedge DUT.Baud_Tick) begin
        $display("t=%0t, tx=%b, tx_busy?=%b, tx_start=%b", $time, Tx_Tb, Tx_Busy_Tb, Tx_Start_Tb);
    end


    initial begin
        $dumpfile("uart_tx_tb.vcd");
        $dumpvars(0, Test_Bench);
    end

endmodule

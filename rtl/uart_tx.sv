// Michael Marquis

module Uart_Tx #(
    parameter Clk_Frequency = 50_000_000,
    parameter Baud_Rate     = 9600
)(
    input  wire       Clk,
    input  wire       Rst_N,

    input  wire [7:0] Data_In,
    input  wire       Tx_Start,
    output reg        Tx_Busy,
    output reg        Tx          //(bytes to bits)
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
        end
        else begin
            case(State)

                Idle: begin
                    Tx      <= 1'b1;
                    Tx_Busy <= 1'b0;
                    if(Tx_Start) begin
                        Tx_Shift <= Data_In;
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
endmodule

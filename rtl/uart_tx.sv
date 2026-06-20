// Michael Marquis
// 6/19/2026

module uart_tx #(
    parameter CLK_FREQ  = 50_000_000,   // 50MHz
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       rst_n,        //active low
    input  wire [7:0] data_in,
    input  wire       tx_start,     //pulse for one cycle
    output reg        tx_busy,
    output reg        tx
);

  //baud divider (int division)
    localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;
    reg [$clog2(BAUD_DIV)-1:0] baud_cnt;
    reg baud_rst;
    wire baud_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            baud_cnt <= 0;
        else if (baud_rst || baud_cnt == BAUD_DIV - 1)
            baud_cnt <= 0;
        else if (tx_busy)
            baud_cnt <= baud_cnt + 1;
    end

    assign baud_tick = (baud_cnt == BAUD_DIV - 1);

    reg [3:0] bit_idx;
    reg [7:0] tx_shift;

    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            tx       <= 1'b1;
            tx_busy  <= 1'b0;
            bit_idx  <= 4'd0;
            tx_shift <= 8'd0;
            baud_rst <= 1'b0;
        end 
      	else begin
            baud_rst <= 1'b0;   //defualt
            case (state)
                IDLE: begin
                    tx      <= 1'b1;
                    tx_busy <= 1'b0;
                    if (tx_start) begin
                        tx_shift <= data_in;
                        tx_busy  <= 1'b1;
                        baud_rst <= 1'b1;   //this is to syncronise the counter
                        state    <= START;
                    end
                end
                START: begin
                    tx <= 1'b0;
                    if (baud_tick) begin
                        bit_idx <= 4'd0;
                        state   <= DATA;
                    end
                end
                DATA: begin
                  tx <= tx_shift[bit_idx];    //LSB first
                    if (baud_tick) begin
                        if (bit_idx == 4'd7)
                            state <= STOP;
                        else
                            bit_idx <= bit_idx + 1;
                    end
                end
                STOP: begin
                    tx <= 1'b1;
                    if (baud_tick) begin
                        state   <= IDLE;
                        tx_busy <= 1'b0;
                    end
                end
                //error if not here
                default: state <= IDLE;
            endcase
        end
    end

endmodule

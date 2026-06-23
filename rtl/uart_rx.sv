// Michael Marquis
// UART RX path with 16x oversampling, shift register, FIFO + error detection

module uart_rx #(
    parameter clk_frequency = 50_000_000,
    parameter baud_rate     = 9600,
    parameter OVERSAMPLE    = 16,   // samples per bit
    parameter FIFO_DEPTH    = 16    // how many bytes we can buffer
)(
    input  wire       clk,
    input  wire       rst_n,        // active low
    input  wire       rx,           // serial rx line (bits coming in)

    input  wire       rd_en,        // pulse high to pop a byte from fifo
    output reg  [7:0] data_out,     // byte out
    output wire       rx_ready,     // high when fifo has a byte waiting
    output reg        frame_err,    // bad stop bit
    output reg        parity_err,   // parity mismatch
    output reg        overrun_err   // fifo was full when a byte arrived
);

    //--------------------------------------------------------
    // oversample baud gen : tick OVERSAMPLE times per bit
    //--------------------------------------------------------
    localparam SAMPLE_DIV = clk_frequency / (baud_rate * OVERSAMPLE);
    integer    samp_count;
    reg        samp_tick;          // pulse at oversample rate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            samp_count <= 0;
            samp_tick  <= 1'b0;
        end
        else if (samp_count == SAMPLE_DIV - 1) begin
            samp_count <= 0;
            samp_tick  <= 1'b1;     // one clk wide pulse
        end
        else begin
            samp_count <= samp_count + 1;
            samp_tick  <= 1'b0;
        end
    end

    //--------------------------------------------------------
    // double flop the rx line to kill metastability
    //--------------------------------------------------------
    reg rx_sync1, rx_sync2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;       // idle line is high
            rx_sync2 <= 1'b1;
        end
        else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end
    wire rx_in = rx_sync2;          // clean rx to use everywhere

    //--------------------------------------------------------
    // rx state machine + shift register
    //--------------------------------------------------------
    localparam IDLE  = 2'd0,
               START = 2'd1,
               DATA  = 2'd2,
               STOP  = 2'd3;
    reg [1:0] state;

    reg [7:0] rx_shift;            // shift reg, data lands here lsb first
    reg [3:0] bit_index;          // which data bit we are on
    reg [4:0] samp_idx;           // counts oversamples within a bit
    reg       parity_bit;         // the parity bit we sampled
    reg [7:0] rx_byte;            // finished byte to push into fifo
    reg       byte_valid;         // pulse high when a byte is ready

    localparam MID = (OVERSAMPLE/2) - 1;   // sample point mid bit

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            rx_shift   <= 8'd0;
            bit_index  <= 4'd0;
            samp_idx   <= 5'd0;
            parity_bit <= 1'b0;
            rx_byte    <= 8'd0;
            byte_valid <= 1'b0;
            frame_err  <= 1'b0;
            parity_err <= 1'b0;
        end
        else begin
            byte_valid <= 1'b0;     // default, only pulse for 1 clk

            if (samp_tick) begin
                case (state)

                    IDLE: begin
                        samp_idx <= 5'd0;
                        if (rx_in == 1'b0)     // saw a falling edge = start bit
                            state <= START;
                    end

                    START: begin
                        if (samp_idx == MID) begin
                            if (rx_in == 1'b0) begin   // still low at mid = real start
                                samp_idx  <= 5'd0;
                                bit_index <= 4'd0;
                                state     <= DATA;
                            end
                            else
                                state <= IDLE;   // false start, glitch
                        end
                        else
                            samp_idx <= samp_idx + 1;
                    end

                    DATA: begin
                        if (samp_idx == OVERSAMPLE - 1) begin
                            samp_idx <= 5'd0;
                            rx_shift <= {rx_in, rx_shift[7:1]};  // shift in lsb first
                            if (bit_index == 4'd7)
                                state <= STOP;
                            else
                                bit_index <= bit_index + 1;
                        end
                        else
                            samp_idx <= samp_idx + 1;
                    end

                    STOP: begin
                        if (samp_idx == OVERSAMPLE - 1) begin
                            samp_idx   <= 5'd0;
                            state      <= IDLE;
                            rx_byte    <= rx_shift;
                            byte_valid <= 1'b1;             // got a full byte
                            frame_err  <= (rx_in != 1'b1);  // stop bit should be high
                            parity_err <= (^rx_shift) != 1'b0; // even parity check
                        end
                        else
                            samp_idx <= samp_idx + 1;
                    end

                endcase
            end
        end
    end

    //--------------------------------------------------------
    // rx FIFO : buffers finished bytes so cpu can read when ready
    //--------------------------------------------------------
    reg  [7:0] fifo_mem [0:FIFO_DEPTH-1];
    reg  [$clog2(FIFO_DEPTH):0] wr_ptr;   // extra bit for full/empty
    reg  [$clog2(FIFO_DEPTH):0] rd_ptr;

    wire fifo_empty = (wr_ptr == rd_ptr);
    wire fifo_full  = (wr_ptr[$clog2(FIFO_DEPTH)-1:0] == rd_ptr[$clog2(FIFO_DEPTH)-1:0]) &&
                      (wr_ptr[$clog2(FIFO_DEPTH)] != rd_ptr[$clog2(FIFO_DEPTH)]);

    assign rx_ready = !fifo_empty;        // data waiting to be read

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr      <= 0;
            rd_ptr      <= 0;
            data_out    <= 8'd0;
            overrun_err <= 1'b0;
        end
        else begin
            // --- write side : push new byte from the state machine ---
            if (byte_valid) begin
                if (!fifo_full) begin
                    fifo_mem[wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= rx_byte;
                    wr_ptr <= wr_ptr + 1;
                    overrun_err <= 1'b0;
                end
                else
                    overrun_err <= 1'b1;   // no room, byte dropped
            end

            // --- read side : pop a byte when cpu asks ---
            if (rd_en && !fifo_empty) begin
                data_out <= fifo_mem[rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
                rd_ptr   <= rd_ptr + 1;
            end
        end
    end

endmodule

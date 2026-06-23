// Michael Marquis
// AXI-Lite interface + register file for the UART (ties tx and rx together)

module uart_axil #(
    parameter ADDR_WIDTH = 4,          // 4 regs worth of address
    parameter DATA_WIDTH = 32
)(
    input  wire                    clk,        // axi aclk
    input  wire                    rst_n,      // axi aresetn (active low)

    //--- AXI-Lite write address channel ---
    input  wire [ADDR_WIDTH-1:0]   awaddr,
    input  wire                    awvalid,
    output reg                     awready,

    //--- AXI-Lite write data channel ---
    input  wire [DATA_WIDTH-1:0]   wdata,
    input  wire [DATA_WIDTH/8-1:0] wstrb,
    input  wire                    wvalid,
    output reg                     wready,

    //--- AXI-Lite write response channel ---
    output reg  [1:0]              bresp,
    output reg                     bvalid,
    input  wire                    bready,

    //--- AXI-Lite read address channel ---
    input  wire [ADDR_WIDTH-1:0]   araddr,
    input  wire                    arvalid,
    output reg                     arready,

    //--- AXI-Lite read data channel ---
    output reg  [DATA_WIDTH-1:0]   rdata,
    output reg  [1:0]              rresp,
    output reg                     rvalid,
    input  wire                    rready,

    //--- side that talks to the uart core ---
    output reg  [7:0]              tx_data,      // byte to send
    output reg                     tx_start,     // pulse to kick off a tx
    input  wire                    tx_busy,      // tx still sending
    input  wire [7:0]              rx_data,      // byte from rx fifo
    input  wire                    rx_ready,     // rx fifo has a byte
    output reg                     rx_rd_en,     // pop the rx fifo
    input  wire                    frame_err,    // rx errors
    input  wire                    parity_err,
    input  wire                    overrun_err
);

    // register map (byte addresses, word aligned)
    //   0x0 TXDATA  (w)  write a byte to send [7:0]
    //   0x4 RXDATA  (r)  read a byte from rx fifo [7:0]
    //   0x8 STATUS  (r)  {overrun,parity,frame,rx_ready,tx_busy}
    //   0xC CONTROL (rw) spare control bits for later
    //--------------------------------------------------------
    localparam ADDR_TXDATA  = 4'h0,
               ADDR_RXDATA  = 4'h4,
               ADDR_STATUS  = 4'h8,
               ADDR_CONTROL = 4'hC;

    reg [DATA_WIDTH-1:0] control_reg;   // the one real storage reg

    //--------------------------------------------------------
    // write channel : latch aw + w, then push into the regfile
    //--------------------------------------------------------
    reg aw_done, w_done;
    wire [ADDR_WIDTH-1:0] wr_addr = awaddr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awready     <= 1'b0;
            wready      <= 1'b0;
            bvalid      <= 1'b0;
            bresp       <= 2'b00;
            aw_done     <= 1'b0;
            w_done      <= 1'b0;
            tx_data     <= 8'd0;
            tx_start    <= 1'b0;
            control_reg <= {DATA_WIDTH{1'b0}};
        end
        else begin
            tx_start <= 1'b0;          // default, only pulse 1 clk

            // latch the write address
            if (awvalid && !aw_done) begin
                awready <= 1'b1;
                aw_done <= 1'b1;
            end
            else
                awready <= 1'b0;

            // latch the write data
            if (wvalid && !w_done) begin
                wready <= 1'b1;
                w_done <= 1'b1;
            end
            else
                wready <= 1'b0;

            // once both sides are in, do the actual register write
            if (aw_done && w_done && !bvalid) begin
                case (wr_addr)
                    ADDR_TXDATA: begin
                        tx_data  <= wdata[7:0];
                        tx_start <= 1'b1;     // kick the transmitter
                    end
                    ADDR_CONTROL: control_reg <= wdata;
                    default: ;             // read-only or unused regs
                endcase
                bvalid <= 1'b1;
                bresp  <= 2'b00;          // OKAY
            end

            // finish the write handshake
            if (bvalid && bready) begin
                bvalid  <= 1'b0;
                aw_done <= 1'b0;
                w_done  <= 1'b0;
            end
        end
    end

    //--------------------------------------------------------
    // read channel : accept araddr, drive rdata back
    //--------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arready  <= 1'b0;
            rvalid   <= 1'b0;
            rresp    <= 2'b00;
            rdata    <= {DATA_WIDTH{1'b0}};
            rx_rd_en <= 1'b0;
        end
        else begin
            rx_rd_en <= 1'b0;          // default, only pulse 1 clk

            // accept a read address
            if (arvalid && !arready && !rvalid) begin
                arready <= 1'b1;
                rvalid  <= 1'b1;
                rresp   <= 2'b00;        // OKAY
                case (araddr)
                    ADDR_RXDATA: begin
                        rdata    <= {24'd0, rx_data};
                        rx_rd_en <= 1'b1;    // pop the fifo on a read
                    end
                    ADDR_STATUS:
                        rdata <= {27'd0, overrun_err, parity_err,
                                  frame_err, rx_ready, tx_busy};
                    ADDR_CONTROL:
                        rdata <= control_reg;
                    default:
                        rdata <= {DATA_WIDTH{1'b0}};
                endcase
            end
            else
                arready <= 1'b0;

            // finish the read handshake
            if (rvalid && rready)
                rvalid <= 1'b0;
        end
    end

endmodule

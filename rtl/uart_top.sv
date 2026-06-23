//============================================================
// Michael Marquis
// TOP LEVEL : glues axi-lite regfile + uart_tx + uart_rx
//============================================================
module uart_top #(
    parameter clk_frequency = 50_000_000,
    parameter baud_rate     = 9600
)(
    input  wire        clk,
    input  wire        rst_n,

    //--- axi-lite slave port ---
    input  wire [3:0]  awaddr,
    input  wire        awvalid,
    output wire        awready,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,
    input  wire        wvalid,
    output wire        wready,
    output wire [1:0]  bresp,
    output wire        bvalid,
    input  wire        bready,
    input  wire [3:0]  araddr,
    input  wire        arvalid,
    output wire        arready,
    output wire [31:0] rdata,
    output wire [1:0]  rresp,
    output wire        rvalid,
    input  wire        rready,

    // the actual serial pins
    output wire        tx,           // uart transmit pin
    input  wire        rx            // uart receive pin
);

    //--- wires between axi block and the uart cores ---
    wire [7:0] tx_data;
    wire       tx_start;
    wire       tx_busy;
    wire [7:0] rx_data;
    wire       rx_ready;
    wire       rx_rd_en;
    wire       frame_err;
    wire       parity_err;
    wire       overrun_err;

    //--------------------------------------------------------
    // axi-lite interface + register file
    //--------------------------------------------------------
    uart_axil #(
        .ADDR_WIDTH (4),
        .DATA_WIDTH (32)
    ) u_axil (
        .clk         (clk),
        .rst_n       (rst_n),
        .awaddr      (awaddr),
        .awvalid     (awvalid),
        .awready     (awready),
        .wdata       (wdata),
        .wstrb       (wstrb),
        .wvalid      (wvalid),
        .wready      (wready),
        .bresp       (bresp),
        .bvalid      (bvalid),
        .bready      (bready),
        .araddr      (araddr),
        .arvalid     (arvalid),
        .arready     (arready),
        .rdata       (rdata),
        .rresp       (rresp),
        .rvalid      (rvalid),
        .rready      (rready),
        .tx_data     (tx_data),
        .tx_start    (tx_start),
        .tx_busy     (tx_busy),
        .rx_data     (rx_data),
        .rx_ready    (rx_ready),
        .rx_rd_en    (rx_rd_en),
        .frame_err   (frame_err),
        .parity_err  (parity_err),
        .overrun_err (overrun_err)
    );

    //--------------------------------------------------------
    // transmitter core
    //--------------------------------------------------------
    uart_tx #(
        .clk_frequency (clk_frequency),
        .baud_rate     (baud_rate)
    ) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .data_in  (tx_data),
        .tx_start (tx_start),
        .tx_busy  (tx_busy),
        .tx       (tx)
    );

    //--------------------------------------------------------
    // receiver core
    //--------------------------------------------------------
    uart_rx #(
        .clk_frequency (clk_frequency),
        .baud_rate     (baud_rate),
        .OVERSAMPLE    (16),
        .FIFO_DEPTH    (16)
    ) u_rx (
        .clk         (clk),
        .rst_n       (rst_n),
        .rx          (rx),
        .rd_en       (rx_rd_en),
        .data_out    (rx_data),
        .rx_ready    (rx_ready),
        .frame_err   (frame_err),
        .parity_err  (parity_err),
        .overrun_err (overrun_err)
    );

endmodule

//============================================================
// KNOWN BOTTLENECKS / TODO
//------------------------------------------------------------
// 1. TX won't compile : t'b0 typo, missing ; on bit_index, STOP empty
// 2. TX baud_count never increments -> baud_tick may never fire
// 3. TX has no FIFO : one byte at a time, sw must poll tx_busy
// 4. AXI-Lite single-outstanding : no pipelining (throughput limit)
// 5. wstrb byte strobes ignored on writes
// 6. parity/frame format not pinned : TX sends no parity bit
// 7. no CDC if axi clk != uart sample clk
//============================================================

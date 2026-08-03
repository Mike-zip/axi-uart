# Figures

Visuals for this project. Each one is referenced from the main
[README](../README.md)

## axi_uart_Block_Design.png

The Vivado block design. The Zynq7 Processing System drives my UART over
`M_AXI_GP0`, through an AXI SmartConnect that converts AXI3 to AXI4-Lite and does
the address decode. The fabric clock `FCLK_CLK0` runs at 100 MHz and feeds both
the interconnect and my core. The peripheral is mapped at `0x4000_0000` with a
4 KB range.

Only `Uart_Txd` and `Uart_Rxd` leave the chip. All 88 AXI signals stay inside the
PL, which is what took the design from 90 unconstrained package pins down to 2.

The whole block design can be rebuilt from [reports/axi_uart.tcl](../reports/axi_uart.tcl).

## Loop_Back_Waveform.png

The loopback testbench running the full path. `Test_Bytes` holds the eight
patterns (`41 55 aa 01 80 ff 00 c3`), `Write_Data_Tb` shows each one going in over
AXI, and `Read_Back` shows the same byte coming back out after it has been
serialized, looped through the receiver, and read out through the AXI read port.

`Read_Back` starts as `xxxxxxxx` because the RX FIFO storage is deliberately not
reset. The pointers decide which slots are valid, so an unwritten slot is
unreachable and there is nothing to clear. Not resetting it is also what lets the
array infer as distributed RAM instead of 128 flip flops per FIFO.

## Implemented_Design.png

The routed design on the die. The dense green fan-out on the left is the PS7
hard block's connections; the small cluster of orange in the middle is my logic.
It occupies 214 slices out of 4400.

# axi-uart

A UART peripheral with TX/RX FIFOs and an AXI4-Lite register interface, written in Verilog. The plan is a small, readable core that a CPU can drive over AXI in a Zynq fpga board, with the UART datapath kept independent of any vendor IP so it can also be used on its own.

This is a work in progress. 

## What's done

- **UART TX & RX** (TestBench and Design for both)
  


## Planned

- UART receiver with 16x oversampling and mid-bit sampling
- Synchronous TX and RX FIFOs
- AXI4-Lite slave wrapper exposing control, status, baud and data registers
- Self-checking loopback testbench (TX into RX, compare against sent bytes)
- Parity and configurable frame format

## TX module notes

Baud rate is set by two parameters, `CLK_FREQ` and `BAUD_RATE`, so changing the line rate is just a parameter override - no edits to the logic. The divider is reset at the start of each frame (`baud_rst`) so the first bit period lines up with `tx_start` instead of wherever the free-running counter happened to be. Reset is active-low (`rst_n`) and the line idles high, which matches standard UART idle.

## Roadmap

- [x] UART transmitter
- [x] UART receiver
- [x] TX/RX FIFOs
- [ ] AXI4-Lite register interface
- [ ] Loopback testbench
- [ ] Parity + configurable framing

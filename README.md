# axi-uart

A UART peripheral with TX/RX FIFOs and an AXI4-Lite register interface, written in SystemVerilog. The plan is a small, readable core that a CPU can drive over AXI in a Zynq/MicroBlaze-style SoC, with the UART datapath kept independent of any vendor IP so it can also be used on its own.

This is a work in progress. Right now the transmit path is done and the rest is being built out module by module (see the roadmap below).

## What's done

- **UART transmitter (`rtl/uart_tx.sv`)** - parameterized by clock frequency and baud rate. Generates its own baud tick from an internal divider, then walks a start / 8 data bits (LSB first) / stop state machine. `tx_busy` is held high for the duration of a frame and a one-cycle `tx_start` pulse kicks off a transfer.

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

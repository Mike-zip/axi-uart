# axi-uart

A UART with independent transmit and receive datapaths, each with its own 16-byte
FIFO, behind an AXI4-Lite slave interface. A CPU drives the whole thing with
register reads and writes. Written in Verilog with no vendor IP, so the TX and RX
blocks also work on their own.

Target part is the Xilinx Zynq-7000 **XC7Z007S**. It closes timing at 100 MHz
with 4.85 ns of slack, using **265 LUTs** and **507 flip flops** (under 2% of the
device). Verified end to end in simulation, from an AXI write all the way through
serial framing and back out an AXI read.

## Project Overview

The UART is parameterizable. Clock frequency, baud rate, oversampling factor and
FIFO depth are all module parameters, so retargeting to a different clock or line
rate is a parameter override instead of a code change.

Everything the CPU needs sits behind four 32-bit registers. Write a byte to send
it, read a byte to pull one out, and check status for FIFO state and errors.

```
CPU  <--AXI4-Lite-->  register block  -->  TX FIFO --> TX FSM --> Uart_Txd
                                      <--  RX FIFO <-- RX FSM <-- Uart_Rxd
```

## Architecture & Design

**Transmitter** [`rtl/uart_tx.v`](`rtl/uart_tx.v`)
- Four state FSM: Idle, Start, Data, Stop. 8N1 framing.
- Baud counter is held at zero while the line is idle, so the first bit period
  lines up with the start of the frame instead of wherever a free running counter
  happened to be.
- 16-byte FIFO in front of the FSM. The FSM pops a byte whenever it goes idle and
  the FIFO is not empty.
- Line idles high, reset is active low.

**Receiver** [`rtl/uart_rx.v`](`rtl/uart_rx.v`)
- Two flip flop synchronizer on the incoming line before anything else looks at it.
- 16x oversampling. The FSM finds the start bit, waits half a bit to get to the
  middle, then samples every 16 ticks from there so it reads each bit at its center.
- Re-checks the start bit at mid-bit and returns to idle if it went high, which
  throws out glitches.
- Flags a frame error if the stop bit is not high, and drops that byte instead of
  pushing it into the FIFO.
- Flags an overrun if a byte arrives with the FIFO already full.

**FIFOs**
- 16 deep, 8 bits wide, one per direction. Depth is a parameter with a
  power-of-two check at elaboration.
- Pointers carry one extra MSB so full and empty are distinguishable when the
  pointers otherwise match.
- The RX FIFO read output is combinational (first word fall through), so the AXI
  read can return the head byte and pop the FIFO on the same cycle.

**AXI4-Lite interface** [`rtl/uart_axil.v`](`rtl/uart_axil.v`)
- Full AW/W/B and AR/R channel handshaking.
- Write address and write data are both latched at their handshakes. The register
  decode uses the latched copies, so a master that drops the address after AWREADY
  and sends the data later still writes the right register.
- The status register is combinational, so a read always returns live hardware
  state rather than something stale.

### Register map

| Offset | Name | Access | Description |
|---|---|---|---|
| `0x0` | TX_DATA | W | Byte in `[7:0]` is pushed into the TX FIFO |
| `0x4` | RX_DATA | R | Returns head of RX FIFO in `[7:0]` and pops it |
| `0x8` | STATUS | R | Live status, see below |
| `0xC` | CONTROL | R/W | General purpose control register |

STATUS bits:

| Bits | Field |
|---|---|
| 0 | TX busy |
| 1 | RX data ready |
| 2 | Frame error |
| 3 | Reserved |
| 4 | Overrun error |
| 5 | TX FIFO full |
| 10:6 | TX FIFO occupancy |
| 15:11 | RX FIFO occupancy |
| 31:16 | Reserved |

Software should check RX data ready before reading `0x4`. Reading an empty FIFO
returns a stale byte.

## Synthesis Results

Vivado 2024.2, out of context implementation, routed. Full reports and my notes
on them are in [`reports/`](reports/).

| | |
|---|---|
| Part | XC7Z007S (`xc7z007sclg400-1`) |
| Clock constraint | 100 MHz |
| Worst setup slack (WNS) | +4.854 ns |
| Worst hold slack (WHS) | +0.159 ns |
| Max frequency | about 194 MHz |
| LUTs | 265 of 14400 (1.84%) |
| Flip flops | 507 of 28800 (1.76%) |
| Slices | 168 of 4400 (3.82%) |
| Block RAM / DSP | 0 / 0 |

Timing is met on all 892 endpoints. The critical path is in the RX FIFO, from the
read pointer into the write enable decode across the FIFO registers, at three
logic levels.

Both FIFOs synthesized to flip flops with a mux tree instead of block RAM. That
is where most of the 507 registers go. More detail on that in
[`reports/README.md`](reports/README.md).

## Simulation

Every testbench is self-checking and prints a pass/fail summary at the end. 

The loopback test is the one that exercises the whole design. It ties `Uart_Txd`
straight back to `Uart_Rxd`, writes a byte in over AXI, lets the transmitter shift
it out onto that wire, and reads it back through the AXI read port to compare:




What the tests cover:

- **Loopback**: eight byte patterns through the full path, including 0x55 and 0xAA
  for bit ordering, 0x01 and 0x80 for the end bits, and 0x00 and 0xFF for stuck
  bits. Also checks the RX ready flag comes up in the status register before each
  read.
- **TX**: all 256 byte values, burst ordering out of the FIFO, FIFO full behavior,
  and reset in the middle of a frame.
- **RX**: all 256 byte values, bad start bit, bad stop bit raising a frame error,
  overrun, pop and read ordering, synchronizer latency, and a push and pop landing
  on the same clock edge.
- **AXI4-Lite**: all four registers, status bit packing, the TX push pulse, the RX
  pop pulse, and a master that drops the write address after the AW handshake.

Every testbench has a timeout task that ends the run and reports a failure if a
handshake ever deadlocks, so a hang shows up as a failed test instead of a stuck
simulator. They all dump a `.vcd` if you want to look at waveforms.

The testbenches override the baud parameters to run fast in simulation (10 clocks
per bit instead of 868), so a full loopback run finishes in about 18 microseconds
of sim time. The RTL defaults stay at 100 MHz and 115200.



## Still to do


- Bring-up on hardware with the AXI side driven by the Zynq PS

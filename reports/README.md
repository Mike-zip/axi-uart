# Implementation Results

Vivado reports for the routed design. The raw tool output is unedited. This page
is my notes on what it says.

The design here is `axi_uart_wrapper`, which is my UART plus the Zynq PS, the AXI
SmartConnect and the reset block. That means the totals include a lot of
infrastructure that is not my logic. Where it matters I have called out which is
which.

Part is the XC7Z007S (`xc7z007sclg400-1`, speed grade -1), clocked at 100 MHz from
`FCLK_CLK0`.

## The numbers

| | |
|---|---|
| Timing | Met, 0 failing of 1759 endpoints |
| Worst setup slack | +4.141 ns |
| Worst hold slack | +0.047 ns |
| Max clock | about 170 MHz |
| Slice LUTs | 505 of 14400 (3.51%) |
| Slice registers | 716 of 28800 (2.49%) |
| Distributed RAM | 12 LUTs |
| Block RAM | 0 |
| DSP | 0 |
| Bonded IOB | 2 |
| Total on-chip power | 0.746 W |

The 170 MHz comes from the slack, not a separate run. Constrained at 10 ns and it
finished 4.141 ns early, so 10 - 4.141 = 5.859 ns, about 170 MHz.

## The critical path is not mine

```
Source:      processing_system7_0/inst/PS7_i/MAXIGP0ACLK
Destination: an FDRE in the AXI read decode

  slack             +4.141 ns
  data path delay    5.356 ns   (logic 1.928 ns, route 3.428 ns)
  logic levels       4          (LUT4 x2, LUT6 x2)
```

It starts inside the PS7 hard block on the read address bus and ends at a register
in the address decode. Almost two thirds of the delay is routing, which is what
you expect for a small design spread across a mostly empty die.

Earlier for my standalone build the critical path was inside
the RX FIFO, from the read pointer into the write enable decode. That path is gone
now that the FIFO is distributed RAM instead of flip flops with a mux tree.

## The FIFOs are distributed RAM and getting there took a fix

The primitives table shows `RAMD32 20` and `RAMS32 4`, which the utilization
report counts as 12 LUTs of distributed RAM. That is both 16x8 FIFOs, 256 bits
total, sitting in 12 LUTs.

They did not start that way. Synthesis originally threw:

```
WARNING: [Synth 8-4767] Trying to implement RAM 'Fifo_Memory_Hold_reg' in registers.
	1: RAM is sensitive to asynchronous reset signal.
WARNING: [Synth 8-7137] Register Fifo_Memory_Hold_reg has both Set and reset
         with same priority. This may cause simulation mismatches.
```

My FIFO array write lived inside an `always @(posedge Clk or negedge Reset)`
block. The reset branch never touched the array but that doesn't matter. Living
inside a block whose sensitivity list has an async reset is enough for Vivado to
treat every bit of the array as having an asynchronous control input, and no FPGA
memory primitive has one. So it dissolved both arrays into 128 flip flops each.

The second warning is the one I cared about more. Once dissolved, some bits were
inferred with a preset and some with a clear off that same async signal, with no
defined priority against the data path. That is a real simulation versus hardware
mismatch, not just wasted area.

The fix was giving the memory its own block with no reset. Not resetting FIFO
storage is deliberate because the pointers decide what is valid. When the write and read
pointers match the FIFO is empty and nothing in those slots is reachable. There is
nothing to clear.

What changed in the reports:

| | Before | After |
|---|---|---|
| MUXF7 | 32 | 0 |
| MUXF8 | 15 | 0 |
| Distributed RAM | 0 | 12 LUTs |

The `MUXF7`/`MUXF8` were the read mux tree needed to select one of 16 slots out of
a flip flop array. With real memory they are not needed at all.

Block RAM is still 0 and always will be. My first-word-fall-through read is a
combinational array read, and block RAM has no asynchronous read port. Distributed
RAM does, which is why that is the right target here.

There is one place in the timing report where you can see the primitive directly:

```
Low Pulse Width   RAMD32/CLK   Receiver/Fifo_Memory_Hold_reg_0_15_0_5/RAMA/CLK
```

That is my RX FIFO showing up as a `RAMD32` in a pulse width check.

## The counter fix shows up in CARRY4

`CARRY4` is 3. In my earlier build it was 16.

I had declared the baud and sample counters as `integer`, which in Verilog is
32 bits signed. The baud counter only needs 10 bits and the sample counter 6. It
didn't cross my mind to even think about the extra space I wasn't using. I found 
this when I opened the routed timing report and found 
`Baud_Count_reg[25]`, `[27]`, `[30]` and `[31]` sitting there as real flip
flops. It never trimmed them. Two untrimmed 32-bit counters is 8 CARRY4 each,
which was most of that 16.

Sizing them off their dividers dropped it to 3.

## Register types

```
FDRE  474    clock enable, sync reset
FDCE  229    clock enable, async reset
FDSE   12    clock enable, sync set
FDPE    1    clock enable, async preset
```

The single `FDPE` is my favourite detail in the report. `FDPE` presets high on
reset, and it is the only one in the whole design, because `Tx` is the only signal
that has to come out of reset high. UART idles high.

Also worth noting: `Register as Latch` is 0. Nothing in my RTL accidentally
inferred a latch.

## Two warnings, both expected

The methodology report has exactly two checks, both `TIMING-18`:

```
An input delay is missing on Uart_Rxd_0 relative to clk_fpga_0
An output delay is missing on Uart_Txd_0 relative to clk_fpga_0
```

These are asynchronous serial pins. There is no source-synchronous clock to
reference them to, so there is no meaningful delay to constrain. `check_timing`
otherwise comes back clean: 0 unconstrained internal endpoints, 0 combinational
loops, 0 latch loops, 0 registers with no clock.

In my earlier standalone build this was 47 inputs and 38 outputs, because the
whole AXI bus was going to package pins. Putting the design in a block design
took it to 2.

## Power

| | |
|---|---|
| Total on-chip | 0.746 W |
| Dynamic | 0.646 W |
| Static | 0.101 W |
| Junction temperature | 33.6 C |

The hierarchy breakdown is the useful part:

```
processing_system7_0    0.638 W
axi_smc                 0.005 W
Uart_Axi_Lite_Ip_0      0.002 W
```

My peripheral is 2 mW. Essentially all of the power is the ARM core.

Confidence on this report is Low because I did not feed it switching activity from
simulation, so treat it as a rough figure rather than a measurement.

## Files

- [utilization.rpt](utilization.rpt) - report_utilization after routing
- [timing_summary.rpt](timing_summary.rpt) - report_timing_summary after routing
- [axi_uart.tcl](axi_uart.tcl) - rebuilds the block design from scratch

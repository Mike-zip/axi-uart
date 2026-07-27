# Implementation Results

These are the Vivado reports for `Uart_Top` after synthesis and implementation.
Both files in here are the raw tool output, unedited. This page is just my notes
on what they say.

I ran this out of context, meaning I implemented the UART by itself instead of
as part of a full block design with the Zynq PS. That keeps the numbers clean,
since nothing in here is the processor's infrastructure, it's only my logic. The
part is the XC7Z007S (xc7z007sclg400-1, speed grade -1) and I constrained the
clock to 100 MHz.

## The numbers

| | |
|---|---|
| Timing | Met, 0 failing endpoints out of 892 |
| Worst setup slack | +4.854 ns |
| Worst hold slack | +0.159 ns |
| Max clock | about 194 MHz |
| LUTs | 265 of 14400 (1.84%) |
| Flip flops | 507 of 28800 (1.76%) |
| Slices | 168 of 4400 (3.82%) |
| Block RAM | 0 |
| DSP | 0 |

The 194 MHz is worked out from the slack, not from a separate run. I constrained
it at 100 MHz (10 ns) and it finished 4.854 ns early, so 10 - 4.854 = 5.146 ns,
which is about 194 MHz.

## What the critical path turned out to be

The slowest path is inside the RX FIFO. It starts at the read pointer and ends
at the clock enable on one of the FIFO registers:

```
Receiver/Read_Pointer_reg[4]/C  ->  Receiver/Fifo_Memory_Hold_reg[9][4]/CE

  slack              +4.854 ns
  data path delay     4.633 ns   (logic 1.289 ns, routing 3.344 ns)
  logic levels        3          (LUT2, LUT6, LUT5)
```

That's the pointer feeding the decode logic that picks which FIFO slot to write.
Almost three quarters of the delay is routing rather than logic, which makes
sense for something this small since the pieces end up spread out across the
chip with a lot of empty space between them.

## The FIFOs did not become block RAM

This is the part I did not expect. Block RAM is 0 and distributed RAM is 0, but
the flip flop count is 507, which is higher than the control logic on its own
would need. Looking at the primitives table it lines up exactly:

- 256 FDRE, which is 2 FIFOs x 16 deep x 8 bits
- 250 FDCE, the control and datapath registers with the async active low reset
- 1 FDPE, which is the Tx output register

So both FIFOs got built out of plain flip flops with a mux tree to read them
(that's what the 32 MUXF7 and 15 MUXF8 are), instead of using any real memory.
At 16 deep Vivado decides registers are cheaper than a block RAM. This is fine
since it costs flip flops I have plenty of and it gives me a read
with no latency, which is what makes the AXI read able to grab a byte and pop the
FIFO on the same cycle.

The single FDPE is my favorite detail in the whole report. FDPE is a flip flop
that presets high on reset, and it's the only one in the design, because Tx is
the only signal that has to come out of reset high. UART idles high.

## Two things in the raw reports that look wrong but aren't

If you open the utilization report you'll see Bonded IOB is 0 and BUFGCTRL is 0.
That's only because of the out of context run. Nothing gets assigned to real pins
and no clock buffer gets inserted. In a real build the AXI bus stays inside the
chip and the only signals that reach actual pins are Uart_Txd and Uart_Rxd, with
the clock coming from the PS.

The timing report also flags 47 inputs and 38 outputs with no delay specified,
marked HIGH. This is for the same reason I didn't set input or output delays 
because those paths from a pin to a register don't exist once this is wired 
to the processor. The number that actually matters is the register to register 
slack on sys_clk_pin, and that one is constrained and met.

## Files

- `utilization.rpt` - report_utilization after routing
- `timing.rpt` - report_timing_summary after routing

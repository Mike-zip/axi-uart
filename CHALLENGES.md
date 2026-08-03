# Design Challenges

Notes on what broke and what I did about it. Mostly written down so I stop
repeating the same mistakes. The bugs taught me more than the parts that worked
did.

## I did not understand my own architecture as well as I thought

Walking into this I understood what a UART was. I understood the Tx and Rx. I
understood the AXI4-Lite interface and what it did.

Then I sat down to write it and could not turn any of that into Verilog.

I think the problem is this is my first big project where separate modules have to
talk to each other with real timing. Knowing what a handshake is and knowing which
cycle your data is valid on are not the same thing. I found that out the hard way
about four times on this page.

Vivado was the other one. I have used it before but never like this. I never read
summary reports. I never read warnings. If it built a bitstream it was fine in my
eyes.

That mentality absolutely did not work here. Things I would have scrolled straight
past, wasted space, an async reset stopping a RAM from inferring, turned out to be
the actual problems. Learning to read those reports was probably the biggest thing
I got out of this project and it was not even the thing I set out to learn.

## Every read came back one byte behind

Wrote `A1 B2 C3`. Read back `00 A1 B2`.

Off by one. Every single time, no matter what I changed.

I had `Data_Out` in the receiver as an `output reg` assigned inside a clocked
block, which makes it a flip flop. It only updated on the edge *after* `Pop_Enable`
went high. My AXI wrapper captured `Read_Data` and asserted the pop on the same
edge, so it kept grabbing the previous byte.

The FIFO was fine. The pointers were fine. The two halves just disagreed about
which cycle the data was good on.

Fix was making it a wire with a continuous assign straight out of the array:

```verilog
assign Data_Out = Fifo_Memory_Hold[Read_Pointer[Storage_Log - 1 : 0]];
```

First word fall through. The head byte is valid before you pop, so a same cycle
read and pop works.

Cost of that is a 16 to 1 mux now sitting combinationally on the output path
instead of a clean flop to output stage. At 16 deep and 100 MHz it is fine and post
route timing backs that up. Deeper FIFO or a faster clock and I would go back to
the registered version and eat a cycle of latency in the read protocol.

The part I did not think about at all: this also killed block RAM permanently. A
combinational array read is an asynchronous read and block RAM has no asynchronous
read port. That did not come back around until I was reading synthesis warnings
weeks later.

## A write could land in the wrong register and my tests never noticed

Found this one reading the AXI spec. Nothing failed. My testbench was green the
entire time.

AXI lets a master drop `AWADDR` right after the AW handshake, before the write data
turns up. My commit logic ran later and read the address bus at that point. So a
completely legal master that moved the address on would put my byte into whatever
register the bus happened to be showing.

My testbench held the address steady for the whole transaction. Legal, but not
required, so it never went anywhere near the failing case.

Added `Write_Address_Q` and `Write_Data_Q`, each latched at its own handshake. Then
wrote a testbench master that deliberately drops the address early so the test
actually proves something instead of just failing to trip over it.

36 flip flops. Fine by me. I do not get to tell masters to hold the address.

## My test suite could not fail

A sim hung waiting on a `Bvalid` that never came and the run printed
`ALL TESTS PASSED`.

The watchdog called `$finish` on timeout and never set an error flag, so the
summary logic saw zero errors and called it a win.

It sets `Error_Timeout` before printing now.

This one still annoys me. Every other bug on this page I only found because the
tests were capable of failing. For however long that watchdog was broken I was
running on confidence I had not earned.

## The FIFOs turned into 256 flip flops

Synthesis was passing. Zero errors, zero critical warnings, bitstream flow green.
Then, buried in the log:

```
WARNING: [Synth 8-4767] Trying to implement RAM 'Fifo_Memory_Hold_reg' in registers.
	1: RAM is sensitive to asynchronous reset signal.
WARNING: [Synth 8-7137] Register Fifo_Memory_Hold_reg has both Set and reset
         with same priority. This may cause simulation mismatches.
```

I ignored these for a while because everything worked as far as I could tell. Went
back to them later when I started actually reading my reports.

What threw me is that my reset branch never touches the FIFO array. It only clears
the pointers and the overrun flag. Does not matter. Sitting inside a block whose
sensitivity list has `negedge Reset` is enough for Vivado to treat every bit of the
array as having an async control input, and no memory primitive on the chip has
one. So it gave up and built 128 flip flops per FIFO.

The second warning is the one that actually worried me. Once the array is dissolved
some bits get inferred with a preset and some with a clear off that same async
signal, no defined priority against the data path. That is a genuine sim versus
hardware mismatch, not just wasted area.

Fix was giving the memory its own block with no reset:

```verilog
always @(posedge Clk) begin
  if(Byte_Valid & !Frame_Error & !Fifo_Full)
    Fifo_Memory_Hold[Write_Pointer[Storage_Log - 1 : 0]] <= Stable_Byte;
end
```

Taking the reset off storage was on purpose. The pointers decide what is valid.
Write and read pointers match, FIFO is empty, nothing in those slots is reachable.
Nothing to clear. Burning 256 flip flops to initialise data nobody can read is
just waste.

`MUXF7` 32 to 0. `MUXF8` 15 to 0. Both FIFOs now sit in 12 LUTs of distributed RAM.
Nine warnings gone.

Side effect is `Data_Out` reads `X` in simulation until the first byte lands,
because uninitialised memory is `X`. Correct behaviour, the ready flag guards it,
still looks like something exploded if you open the waveform not knowing why.

## I totally forgot that integers are 32 bits of space

I declared the baud and sample counters as `integer` because that is what I always
reach for when I need a counter. Did not know an integer in Verilog is 32 bits
signed.

Baud counter tops out at 867. Sample counter at 53. Ten bits and six bits. I was
building 32 bits of flip flops for each of them without realising.

Saw it in the routed timing report. `Baud_Count_reg[25]`, `[27]`, `[30]` and `[31]`
sitting there as actual flip flops, showing up as reported path endpoints.

Sizing them off their dividers took `CARRY4` from 16 to 3.

The floor is not optional:

```verilog
localparam Sample_Count_Width = (Sample_Division < 2) ? 1 : $clog2(Sample_Division);
```

My RX and loopback testbenches run with a sample divider of 1. `$clog2(1)` is 0,
which gives you `reg [-1:0]` and stops two of my four testbenches from compiling.

Worth fixing anyway because whatever trimming Vivado might have done only works
while the divider is a compile time constant. My control register exists so the CPU
can change the baud rate at runtime. Build that and the constant is gone, and a
real 32 bit counter and comparator become unavoidable unless the width is stated.

## Place and route passed. Bitgen did not.

```
ERROR: [DRC NSTD-1] Unspecified I/O Standard: 90 out of 90 logical ports use
       I/O standard (IOSTANDARD) value 'DEFAULT'
ERROR: [DRC UCIO-1] Unconstrained Logical Port: 90 out of 90 logical ports have
       no user assigned specific location constraint (LOC)
```

I had `Uart_Top` as the top module. All 88 AXI signals plus clock, reset and the
two serial pins became physical package pins. The board's master XDC was getting
parsed but master XDCs ship with everything commented out.

The confusing bit is that place and route **succeeded**. Clean timing, zero
warnings, positive slack, routed checkpoint sitting on disk. The placer will
auto assign I/O just so P&R can finish. Only `write_bitstream` refuses, because a
bitstream has to name real package balls at real voltage standards.

So the whole thing looked healthy right up until the last step.

Fix was building the block design I had been putting off. `Uart_Top` goes inside a
BD with the Zynq PS, AXI connects internally to `M_AXI_GP0`, only `Uart_Txd` and
`Uart_Rxd` get made external. Wrapper comes out with two PL ports instead of
ninety. My XDC went from needing 90 pin assignments to three lines.

## My ports would not connect to the PS

Dropped `Uart_Top` on the block design canvas and got 18 loose pins instead of one
bundled AXI interface. Connection automation had nothing to grab onto.

Vivado works out what an AXI interface is by pattern matching port names against
the ARM AMBA spec. `s_axi_awaddr`, `s_axi_awvalid`, and so on. There is nothing in
Verilog that says "this is an AXI slave." My `Write_Address` describes exactly the
right signal and the tool has no way to know that is `AWADDR`.

Wrote a thin wrapper with the spec names that instantiates `Uart_Top` unchanged.
The renaming happens in the connection list:

```verilog
.Write_Address(s_axi_awaddr[3:0]),
```

I did think about just renaming the ports on `Uart_Top`. That is what I would do if
I started this over. It breaks my loopback testbench though and means reverifying
everything, so the wrapper won. Got me to hardware without touching RTL I had
already verified.

## Board bring up, which ate more time than the rest of the project combined

Bitstream built, bitstream loaded, ARM core would not run anything:

```
Cannot write memory if not stopped. Context ARM Cortex-A9 MPCore #0 state:
APB AP transaction error, DAP status 0xF0000021
```

Checked the boot mode jumper. Moved it to JTAG. Power cycled. Checked the PS
reference clock. Same DAP error every time.

Then I got `failed to download uart_test.elf`, which is a different message, and
download means writing the program into memory over JTAG. So I went and looked at
where the linker was putting it.

All 30 sections targeting `ps7_ddr_0`.

Opened `ps7_init.html` from the platform:

```
DQS to Clock delay [0..3] : 0.0
Board delay [0..3]        : 0.25
```

All four DQS delays zero. All four board delays an identical 0.25. Those are
supposed to be measured per byte lane trace values and every one of them should be
different. All zeros and all identical is Vivado's untouched default.

I did not have vendor board files installed. Block automation had handed me a
generic PS with a guessed memory configuration and DDR training was never going to
work.

Two changes. Disable DDR in the PS config so `ps7_init` stops trying to train
memory that will not train. Point the linker script at `ps7_ram_0` so the program
runs out of the 192 KB of on chip memory instead.

That whole thing was sitting in a file I could have opened at the start.

## The dumbest one

Still could not get a character into a terminal after all that. Checked baud rates.
Flow control. COM ports. Local echo. Swapped the wires.

I do not own a USB to serial adapter.

The only cable going to the board was the programming USB, which gives you JTAG and
power and nothing else. `Uart_Txd` and `Uart_Rxd` are on PmodB pins that were wired
to nothing at all. There was never going to be a character.

The blinking Tx LED I had been treating as proof of life was the adapter side of a
connection that did not exist.

Built a working peripheral. Spent hours on pins. No wire.

## Things I would do differently

Spec port names from the start. The wrapper is fine and I would probably still
write one for a reusable core, but I only *needed* it because I named things for
readability on a boundary where convention matters more.

Write the watchdog properly first. Everything downstream leaned on those tests
being honest and for a while they were not.

Read warnings on builds that pass. The FIFO problem and the counter problem were
both sitting in logs I had scrolled past because there were no errors in them.

Check the cable.

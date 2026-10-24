# Pmod AUDIO check on a DE0-CV

This project checks a Pmod AUDIO v1.2 in a few minutes. It plays a rising
scale through the speaker. If you hear the scale, the Pmod, the RFS socket and
the two audio pins all work. The design is one SystemVerilog file.

## What the design does

The design plays fifteen notes, from C4 to C6, and then repeats. The switches
set the tempo. KEY0 and KEY1 set the volume, and HEX0 shows the level.

A pulse-width modulator drives the amplifier input.

```
NOTE_SW[note] --> phase increment --> 24-bit phase --> sine table
                                                            |
                                                            v
                                                      8-bit sample
                                                            |
                                                            v
                                           PWM against an 8-bit counter
                                                            |
                                                            v
                                            PIN_T17 and PIN_T15
```

One PWM period is 256 clock cycles, so the carrier is 195.3 kHz. One sine
sample is taken per period, so the sample rate is 195312.5 Hz. A note value of
`n` gives this frequency:

```
f = n * 256 * 195312.5 / 2**24 = n * 2.98023 Hz
```

Each note is within 2 Hz of its equal-tempered value. The largest error is
0.35 per cent.

The note length in PWM periods is `8192 + ((1023 - SW) << 7)`. That gives
0.712 s for each note at SW=0, and 0.042 s at SW=1023.

The Pmod input is a coupling capacitor into 22 kohm, which is a high-pass with
no low-pass. The carrier therefore reaches the amplifier at full amplitude. A
fast carrier keeps that power above the band the speaker can move.

The design starts at volume 1 of 15. A board that powers up cannot surprise a
headphone wearer. A full-scale sine clips at this amplifier, and a clipped sine
heats the voice coil.

## The audio pins

| channel | FPGA pin | GPIO_0 lane |
|---|---|---|
| left | `PIN_T17` | 34 |
| right | `PIN_T15` | 35 |

**Do not take these pins from the RFS schematic.** The RFS female header
mirrors each row against the DE0-CV male header, so a net name there does not
give the GPIO lane.

Measurement found the pins on the board:

1. all 36 lanes carried the tone, and the speaker sounded it;
2. lanes 0 to 17 were silent, so the tone was in lanes 18 to 35;
3. lanes 26 to 33 were silent, so the tone was in lane 34 or lane 35;
4. lanes 34 and 35 together carried the tone.

The two lanes must be driven together. A class-D amplifier with one input
floating gives no sound. A test that drives one lane gives silence even when
that lane is correct.

## Build and program

Quartus Prime Lite 18.1 builds this project. The board holds a Cyclone V
`5CEBA4F23C7`.

Quartus 18.1 asks for `libnsl.so.1`, which current distributions no longer
ship. A link of the older name serves:

```sh
mkdir -p quartus-libs
ln -sfn /usr/lib64/libnsl.so.3 quartus-libs/libnsl.so.1
export LD_LIBRARY_PATH=$PWD/quartus-libs
```

Set `Q` to the `bin` directory of your Quartus installation, then run the four
stages and program the board:

```sh
Q=/opt/intelFPGA_lite/18.1/quartus/bin   # your installation path
$Q/quartus_map de0cv_sine
$Q/quartus_fit de0cv_sine
$Q/quartus_asm de0cv_sine
$Q/quartus_sta de0cv_sine
$Q/quartus_pgm -m jtag -o "p;de0cv_sine.sof"
```

## The note bench

`sim/tb_sine.cpp` measures the notes without a board. It counts the high
cycles of each PWM period, which gives the duty. It finds where the duty
crosses its mid value, which gives the tone period. It reads the note index
from the LEDs, which gives the note length.

```sh
cd sim
verilator --cc --exe --build -O2 -Wno-fatal --top-module de0cv_sine_pwm \
    ../de0cv_sine_pwm.sv tb_sine.cpp -o tb_sine --Mdir obj_sine
./obj_sine/tb_sine 1023
```

The argument is the switch value, which sets the tempo.

At `SW=1023` the bench measured every note, with a pitch error below 2 Hz and a
note length of exactly 8192 PWM periods. At `SW=0` it measured a note length of
exactly 139136 PWM periods, which is 0.712 s.

The bench found two faults before the board saw them: the volume register
powered up at zero, and the volume multiply was truncated to 8 bits before the
shift.

## Files

| file | role |
|---|---|
| `de0cv_sine_pwm.sv` | the design |
| `de0cv_sine.qsf` | device, the two audio pins, keys, switches, displays |
| `de0cv_sine.sdc` | the 50 MHz clock |
| `de0cv_sine.qpf` | the Quartus project |
| `sim/tb_sine.cpp` | the bench that measures the notes and the tempo |

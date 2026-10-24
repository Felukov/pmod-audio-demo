# Repeating scale on a DE0-CV with the Pmod AUDIO

This project plays a rising musical scale on the speaker of the Pmod AUDIO
v1.2. The tone plays through the RFS daughter card, which supplies the socket.
The design is one SystemVerilog file.

## What the design does

The design holds a table of fifteen note values, from C4 to C6. A timer moves
through the table, so the scale plays and then repeats. The switches set the
tempo, and KEY0 and KEY1 set the volume.

A pulse-width modulator drives the amplifier input. The amplifier removes the
switching rate and reproduces the average level. That average level follows a
256-entry sine table.

```
NOTE_SW[note_index] --> phase increment --> 24-bit phase --> sine table
                                                                  |
                                                                  v
                                                   8-bit sample, scaled
                                                                  |
                                                                  v
                                             PWM against an 8-bit counter
                                                                  |
                                                                  v
                                                   PIN_T17 and PIN_T15
```

A second counter sets the note length. When it reaches its limit, the note
index moves on, and after the last note it returns to the first.

One PWM period is 256 clock cycles, so the carrier is 195.3 kHz.
One sine sample is taken per period, so the sample rate is 195312.5 Hz.
A note value of `n` gives this frequency:

```
f = n * 256 * 195312.5 / 2**24 = n * 2.98023 Hz
```

The note length in PWM periods, set by the switches, is:

```
length = 8192 + ((1023 - SW) << 7)
```

| SW | note length | tempo |
|---|---|---|
| 0 | 0.712 s | slow |
| 512 | 0.377 s | medium |
| 1023 | 0.042 s | fast |

The reason for the fast carrier: the Pmod input network is a coupling
capacitor into 22 kohm, which is a high-pass with no low-pass. The carrier
therefore reaches the amplifier at full amplitude. A fast carrier sits far
above the band the speaker can move, so little of that power becomes heat.

`LEDR[3:0]` show which note is playing. `LEDR[9]` blinks once in 0.67 s from a
clocked counter, so it shows that the clock reaches the logic.

## The notes

| note | frequency | note value | actual |
|---|---|---|---|
| C4 | 261.63 Hz | 88 | 262.26 Hz |
| D4 | 293.66 Hz | 99 | 295.04 Hz |
| E4 | 329.63 Hz | 111 | 330.81 Hz |
| F4 | 349.23 Hz | 117 | 348.69 Hz |
| G4 | 392.00 Hz | 132 | 393.39 Hz |
| A4 | 440.00 Hz | 148 | 441.07 Hz |
| B4 | 493.88 Hz | 166 | 494.72 Hz |
| C5 | 523.25 Hz | 176 | 524.52 Hz |
| D5 | 587.33 Hz | 197 | 587.11 Hz |
| E5 | 659.25 Hz | 221 | 658.63 Hz |
| F5 | 698.46 Hz | 234 | 697.37 Hz |
| G5 | 783.99 Hz | 263 | 783.80 Hz |
| A5 | 880.00 Hz | 295 | 879.17 Hz |
| B5 | 987.77 Hz | 331 | 986.46 Hz |
| C6 | 1046.50 Hz | 351 | 1046.06 Hz |

The note value is an integer, so each note is off by at most 1.9 Hz. The
largest error is 0.35 per cent, which is below the point where most listeners
hear a note as out of tune. A finer table would shrink it further.

## Volume

KEY0 raises the volume and KEY1 lowers it. HEX0 shows the level as a
hexadecimal digit from 0 to F. The design starts at 1, so a board that powers
up cannot surprise the ears of someone wearing headphones.

| volume | effect |
|---|---|
| 0 | silence |
| 1 | quietly audible at every tone; the power-up level |
| 8 | the loudest comfortable setting |
| 15 | full scale; the amplifier clips and the speaker warms |

A full-scale sine clips at this amplifier, because its gain of about 16 turns
a 3.3 V rail into a rail-limited output. A clipped sine heats the voice coil,
so the level that sounds pleasant is below the top of the range.

Each key press counts once. A key must hold its new state for 2.6 ms before
the design accepts it, which removes contact bounce.

## The audio pins

The Pmod sits in the 2x6 socket of the RFS card. The RFS card sits in the
GPIO_0 header of the DE0-CV. The two audio lanes reach the FPGA on:

| channel | FPGA pin | GPIO_0 lane |
|---|---|---|
| left | `PIN_T17` | 34 |
| right | `PIN_T15` | 35 |

**Do not take these pins from the RFS schematic.** The RFS schematic names
the socket signals `TMD_D0` to `TMD_D7`. Names alone do not give the GPIO
lane, because the RFS female header mirrors each row against the DE0-CV male
header. The table above comes from measurement on the board:

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
ship. The symbols are in `libnsl.so.3`, so a link of the older name serves:

```sh
mkdir -p quartus-libs
ln -sfn /usr/lib64/libnsl.so.3 quartus-libs/libnsl.so.1
export LD_LIBRARY_PATH=$PWD/quartus-libs
```

Then run the four stages and program the board:

```sh
Q=/home/fila/intelFPGA_lite/18.1/quartus/bin
$Q/quartus_map de0cv_sine
$Q/quartus_fit de0cv_sine
$Q/quartus_asm de0cv_sine
$Q/quartus_sta de0cv_sine
$Q/quartus_pgm -m jtag -o "p;de0cv_sine.sof"
```

The last build reported a setup slack of 12.8 ns against a 20 ns period, and
a hold slack of 0.25 ns. It passes timing.

## The note bench

`sim/tb_sine.cpp` measures the notes that the design produces. It counts the
high cycles of each PWM period, which gives the duty. It then finds where the
duty crosses its mid value, which gives the tone period of the note now
playing. It reads the note index from the LED outputs, so it also reports the
length of each note.

```sh
cd sim
verilator --cc --exe --build -O2 -Wno-fatal --top-module de0cv_sine_pwm \
    ../de0cv_sine_pwm.sv tb_sine.cpp -o tb_sine --Mdir obj_sine
./obj_sine/tb_sine 1023
```

The argument is the switch value, which sets the tempo. The bench holds both
keys released, so the design runs at its power-up volume of 1.

At `SW=1023` it measured every note of the scale, with a pitch error below
2 Hz and a note length of exactly 8192 PWM periods. At `SW=0` it measured a
note length of exactly 139136 PWM periods, which is 0.712 s.

The bench found two faults that the board would have shown as silence: the
volume register powered up at zero, and the volume multiply was truncated to
8 bits before the shift.

## Files

| file | role |
|---|---|
| `de0cv_sine_pwm.sv` | the design |
| `de0cv_sine.qsf` | device, the two audio pins, keys, switches, displays |
| `de0cv_sine.sdc` | the 50 MHz clock |
| `de0cv_sine.qpf` | the Quartus project |
| `sim/tb_sine.cpp` | the bench that measures the notes and the tempo |

# Pmod AUDIO on a DE0-CV

This project drives a Pmod AUDIO v1.2 on a DE0-CV. It plays a rising scale
through the speaker. The design is one SystemVerilog file.

## What the design does

The design plays fifteen notes, from C4 to C6, and then repeats. The switches
set the note length. KEY0 and KEY1 set the volume, and HEX0 shows the level.

A pulse-width modulator drives the amplifier input.

```
NOTE_SW[note_index] --> phase increment --> phase accumulator
                                                            |
                                                            v
                                                 sample, scaled
                                                            |
                                                            v
                                              PWM against a counter
                                                            |
                                                            v
                                            PIN_T17 and PIN_T15
```

Each note is within 2 Hz of its equal-tempered value.

The design takes one sine sample per PWM period.

## The audio pins

| channel | FPGA pin | GPIO_0 lane |
|---|---|---|
| left | `PIN_T17` | 34 |
| right | `PIN_T15` | 35 |

The two lanes must be driven together.

## Build and program

Quartus Prime Lite 18.1 builds this project. The board holds a Cyclone V
`5CEBA4F23C7`.

Build the bitstream and program the board:

```sh
./build.sh
./flash.sh
```

Both scripts take `Q` from the environment and default to
`$HOME/intelFPGA_lite/18.1/quartus/bin`.

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

The argument is the switch value, which sets the note length.

The bench measures every note of the scale and the length of each note.

## Files

| file | role |
|---|---|
| `de0cv_sine_pwm.sv` | the design |
| `de0cv_sine.qsf` | device, the two audio pins, keys, switches, displays |
| `de0cv_sine.sdc` | the 50 MHz clock |
| `de0cv_sine.qpf` | the Quartus project |
| `build.sh` | builds the bitstream |
| `flash.sh` | programs the bitstream into the FPGA |
| `sim/tb_sine.cpp` | the bench that measures the notes and the note length |

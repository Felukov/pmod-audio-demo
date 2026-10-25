// Measures the notes that the design produces.
//
// The design outputs a pulse-width modulated square wave. This bench counts the
// high cycles inside each period, which gives the duty. The duty sequence is
// the sine. The bench then finds where the duty crosses its mid value, which
// gives one tone period in clock cycles.
//
// The design plays a scale, so the bench reports the frequency of each note
// and the length of each note. The length comes from the note index on the
// LED outputs, which changes once per note.
//
// The clock is 50 MHz. One tone period of P clock cycles is 50e6 / P Hz.

#include <cstdio>
#include <cstdlib>
#include <vector>
#include "Vde0cv_sine_pwm.h"
#include "verilated.h"

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    // The switch value sets the note length.
    const int switchValue = argc > 1 ? atoi(argv[1]) : 1023;

    Vde0cv_sine_pwm *dut = new Vde0cv_sine_pwm;
    dut->CLOCK_50 = 0;
    dut->SW = switchValue;

    // Both keys are released, which reads high on this board.
    dut->KEY = 0xF;

    const int kPeriod = 256;

    // The bench looks for a crossing at half the peak duty.
    const int kMid = 7;

    // The scale has fifteen notes. The bench runs three passes so that the
    // note lengths of every note show.
    const int kNotes = 15;

    int  high     = 0;
    int  prevDuty = -1;

    long periods = 0;
    long lastChange = 0;

    int  seenIndex  = -1;
    long prevCross  = -1;

    std::vector<double> noteHz(kNotes, 0.0);
    std::vector<long>   noteLength(kNotes, 0);

    // Three passes of the scale give every note a frequency and a length.
    const long maxPeriods = 3L * kNotes * 140000L;

    while (periods < maxPeriods) {
        for (int cycle = 0; cycle < kPeriod; ++cycle) {
            dut->CLOCK_50 = 0;
            dut->eval();
            dut->CLOCK_50 = 1;
            dut->eval();
            if (dut->PMOD_AUDIO_L) {
                ++high;
            }
        }
        ++periods;

        // A change of note index starts a new note. The length of the note
        // that just ended is the distance between the two changes.
        const int index = dut->LEDR & 0xF;
        if (index != seenIndex) {
            if (seenIndex >= 0 && seenIndex < kNotes &&
                    noteLength[seenIndex] == 0 && periods - lastChange > 1) {
                noteLength[seenIndex] = periods - lastChange;
            }
            seenIndex   = index;
            lastChange  = periods;
            prevCross   = -1;
        }

        // The duty of the period that just ended is the sine sample.
        if (prevDuty >= 0 && prevDuty < kMid && high >= kMid) {
            if (prevCross >= 0 && seenIndex >= 0 && seenIndex < kNotes &&
                    noteHz[seenIndex] == 0.0) {
                noteHz[seenIndex] = 50.0e6 / double((periods - prevCross) * kPeriod);
            }
            prevCross = periods;
        }
        prevDuty = high;
        high     = 0;

        // Stop once every note has both a frequency and a length.
        bool done = true;
        for (int note = 0; note < kNotes; ++note) {
            if (noteHz[note] == 0.0 || noteLength[note] == 0) {
                done = false;
            }
        }
        if (done) {
            break;
        }
    }

    // The note length for this switch value, from the design.
    const long expected = 8192L + ((1023L - switchValue) << 7);

    printf("SW (note length) = %d\n", switchValue);
    printf("expected note length = %ld PWM periods (%.3f s)\n",
           expected, double(expected) / 195312.5);

    printf("\n%-5s %11s %11s %10s %10s\n",
           "note", "measured", "expected", "length", "length err");
    static const double kScale[] = {
        261.63, 293.66, 329.63, 349.23, 392.00, 440.00, 493.88,
        523.25, 587.33, 659.25, 698.46, 783.99, 880.00, 987.77, 1046.50
    };
    for (int note = 0; note < kNotes; ++note) {
        printf("%-5d %8.2f Hz %8.2f Hz %10ld %10ld\n",
               note, noteHz[note], kScale[note],
               noteLength[note], noteLength[note] - expected);
    }

    delete dut;
    return 0;
}

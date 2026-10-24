// Measures the tone that the design produces.
//
// The design outputs a pulse-width modulated square wave. One PWM period is
// 256 clock cycles. This bench counts the high cycles inside each period,
// which gives the duty that the amplifier receives as an average level.
// The duty sequence is the sine. The bench then finds where the duty crosses
// its mid value, which gives one tone period in clock cycles.
//
// The clock is 50 MHz. One tone period of P clock cycles is 50e6 / P Hz.

#include <cstdio>
#include <cstdlib>
#include <vector>
#include "Vde0cv_sine_pwm.h"
#include "verilated.h"

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);

    // The switch value under test comes from the command line.
    const int switchValue = argc > 1 ? atoi(argv[1]) : 148;
    const long periods = 4000;

    Vde0cv_sine_pwm *dut = new Vde0cv_sine_pwm;
    dut->CLOCK_50 = 0;
    dut->SW = switchValue;

    // Both keys are released, which reads high on this board.
    dut->KEY = 0xF;

    // The bench looks for the duty crossing its mid value. The design starts
    // at volume 1 of 16, so the peak duty is 254/16, which is 15 of 256.
    const int kMid = 7;

    // One PWM period is 256 clock cycles.
    const int kPeriod = 256;

    int      high    = 0;
    int      inPwm   = 0;
    long     cycle   = 0;
    int      prevDuty = -1;
    long     prevCross = -1;
    long     crossings = 0;
    long     firstCross = -1;
    long     lastCross  = -1;

    // Run until the requested number of PWM periods is complete.
    const long cycles = periods * kPeriod;
    for (cycle = 0; cycle < cycles; ++cycle) {
        // Clock low, clock high: one clock cycle.
        dut->CLOCK_50 = 0;
        dut->eval();
        dut->CLOCK_50 = 1;
        dut->eval();

        if (dut->PMOD_AUDIO_L) {
            ++high;
        }
        ++inPwm;

        if (inPwm == kPeriod) {
            // The duty of the period that just ended is the sine sample.
            if (prevDuty >= 0 && prevDuty < kMid && high >= kMid) {
                // An upward crossing of the mid value starts one tone period.
                ++crossings;
                if (firstCross < 0) {
                    firstCross = cycle;
                }
                lastCross = cycle;
            }
            prevDuty = high;
            high     = 0;
            inPwm    = 0;
        }
    }

    if (crossings < 2) {
        printf("no tone: %ld crossings in %ld PWM periods\n", crossings, periods);
        delete dut;
        return 1;
    }

    // The bench counts one crossing per tone period, so the mean period is
    // the distance between the first and the last crossing over the gaps.
    const double meanPeriod = double(lastCross - firstCross) / double(crossings - 1);
    const double toneHz     = 50.0e6 / meanPeriod;

    printf("SW      = %d\n", switchValue);
    printf("crossings = %ld\n", crossings);
    printf("period  = %.1f clock cycles\n", meanPeriod);
    printf("tone    = %.2f Hz\n", toneHz);
    printf("expect  = %.2f Hz (SW * 2.98023)\n", switchValue * 2.98023);

    delete dut;
    return 0;
}

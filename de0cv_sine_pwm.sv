// Sine tone for the Terasic Pmod AUDIO v1.2 on a DE0-CV board.
//
// The Pmod holds a PAM8403 class-D amplifier. Its input is an analog level,
// so this design drives it with a pulse-width modulated square wave. The
// amplifier does not pass the switching rate, so the speaker receives the
// average level of each PWM period.
//
// The Pmod sits in the 2x6 TMD socket of the RFS card, and the RFS card sits
// in the GPIO_0 header. The two audio lanes reach the FPGA on these pins:
//
//   left  channel: PIN_T17, GPIO_0 lane 34
//   right channel: PIN_T15, GPIO_0 lane 35
//
// These two pins were found by measurement on the board, not from the
// schematic. The RFS header mirrors each row against the DE0-CV header, so a
// net name in the RFS schematic does not give the GPIO lane by itself.
//
// Signal path:
//
//   SW[9:0] --> phase increment --> 24-bit phase --> sine table (64 entries)
//                                                        |
//                                                        v
//                                                  8-bit sample
//                                                        |
//                                                        v
//                                    PWM compare against a 10-bit counter
//                                                        |
//                                                        v
//                                              PIN_T17 and PIN_T15
//
// One PWM period is 2**10 = 1024 clock cycles. The PWM rate is therefore
// 50 MHz / 1024 = 48.83 kHz, which is well above the audio band.
//
// One sine sample is taken per PWM period, so the sample rate is 48828.125 Hz.
// The phase accumulator is 24 bits wide. The increment is SW shifted left by
// 10, so the tone frequency is:
//
//   f = SW * 1024 * 48828.125 / 2**24 = SW * 2.98023 Hz
//
//   SW = 0       silence, because the increment is zero
//   SW = 148     441 Hz, near the musical note A4
//   SW = 1023   3049 Hz
//
// LEDR[9] blinks once in 0.67 s from a clocked counter, so it shows that the
// clock reaches the logic. LEDR[8:0] show SW[8:0].

module de0cv_sine_pwm (
    input  logic       CLOCK_50,
    input  logic [9:0] SW,
    output logic [9:0] LEDR,
    output logic       PMOD_AUDIO_L,
    output logic       PMOD_AUDIO_R
);

    // One PWM period is 2**10 = 1024 clock cycles.
    localparam int PWM_WIDTH = 10;

    // The phase accumulator is 24 bits wide.
    localparam int PHASE_WIDTH = 24;

    // The table has 2**6 = 64 entries.
    localparam int TABLE_INDEX_WIDTH = 6;

    // The heartbeat divides 50 MHz down to 0.75 Hz.
    localparam int HEARTBEAT_WIDTH = 26;

    // The table holds one sine period. Entry k is 128 plus 127.5 times the
    // sine of k/64 turns, rounded to an integer. The range 0..255 uses the
    // whole PWM range, so the tone plays at full volume.
    localparam logic [7:0] SINE [0:63] = '{
        8'd128, 8'd140, 8'd152, 8'd165, 8'd176, 8'd188, 8'd198, 8'd208,
        8'd218, 8'd226, 8'd234, 8'd240, 8'd245, 8'd250, 8'd253, 8'd254,
        8'd255, 8'd254, 8'd253, 8'd250, 8'd245, 8'd240, 8'd234, 8'd226,
        8'd218, 8'd208, 8'd198, 8'd188, 8'd176, 8'd165, 8'd152, 8'd140,
        8'd128, 8'd115, 8'd103, 8'd90,  8'd79,  8'd67,  8'd57,  8'd47,
        8'd37,  8'd29,  8'd21,  8'd15,  8'd10,  8'd5,   8'd2,   8'd1,
        8'd0,   8'd1,   8'd2,   8'd5,   8'd10,  8'd15,  8'd21,  8'd29,
        8'd37,  8'd47,  8'd57,  8'd67,  8'd79,  8'd90,  8'd103, 8'd115
    };

    logic [PWM_WIDTH-1:0]       pwm_count;
    logic [PHASE_WIDTH-1:0]     phase;
    logic [7:0]                 sample;
    logic                       pwm_out;
    logic [HEARTBEAT_WIDTH-1:0] heartbeat;

    // The increment is SW shifted left by 10, so no multiplier is needed.
    logic [PHASE_WIDTH-1:0] increment;

    // The sample is scaled by four, so the compare value fits the 10-bit
    // counter. The largest compare value is 255 * 4 = 1020.
    logic [PWM_WIDTH-1:0] threshold;

    assign increment = {4'b0000, SW, 10'b0000000000};
    assign threshold = {sample, 2'b00};

    always_ff @(posedge CLOCK_50) begin
        pwm_count <= pwm_count + 1'b1;
        pwm_out   <= (pwm_count < threshold);
        heartbeat <= heartbeat + 1'b1;

        // At the start of each PWM period one sine sample is taken, and the
        // phase moves one step.
        if (pwm_count == '0) begin
            phase  <= phase + increment;
            sample <= SINE[phase[PHASE_WIDTH-1 -: TABLE_INDEX_WIDTH]];
        end
    end

    assign PMOD_AUDIO_L = pwm_out;
    assign PMOD_AUDIO_R = pwm_out;

    assign LEDR = {heartbeat[HEARTBEAT_WIDTH-1], SW[8:0]};

endmodule

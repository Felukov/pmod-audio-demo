// Sine tone for the Terasic Pmod AUDIO v1.2 on a DE0-CV board.
//
// The Pmod holds a PAM8403 class-D amplifier. Its input is an analog level,
// so this design drives it with a pulse-width modulated square wave. The
// amplifier does not pass the switching rate, so the speaker receives the
// average level of each PWM period.
//
// Signal path:
//
//   SW[9:0] --> phase increment --> 24-bit phase --> sine table (256 entries)
//                                                        |
//                                                        v
//                                      8-bit sample, scaled by VOLUME
//                                                        |
//                                                        v
//                                   PWM compare against an 8-bit counter
//                                                        |
//                                                        v
//                                             PIN_T17 and PIN_T15
//
// One PWM period is 2**8 = 256 clock cycles. The carrier is therefore
// 50 MHz / 256 = 195.3 kHz. A high carrier keeps the switching power out of
// the band the speaker can move, so that power does not become coil heat.
//
// One sine sample is taken per PWM period, so the sample rate is 195312.5 Hz.
// The phase accumulator is 24 bits wide. The increment is SW shifted left by
// 8, so the tone frequency is:
//
//   f = SW * 256 * 195312.5 / 2**24 = SW * 2.98023 Hz
//
//   SW = 0       silence, because the increment is zero
//   SW = 148     441 Hz, near the musical note A4
//   SW = 1023   3049 Hz
//
// VOLUME runs from 0 to 15 and starts at 8. KEY0 raises it and KEY1 lowers
// it. HEX0 shows the level as a hexadecimal digit.
//
// The volume scales the sample by VOLUME/16, so level 15 is close to full
// scale and level 8 is a quarter of full-scale power. A full-scale sine
// clips at the amplifier, and the clipped signal heats the voice coil.
//
// The two audio lanes reach the FPGA on these pins:
//
//   left  channel: PIN_T17, GPIO_0 lane 34
//   right channel: PIN_T15, GPIO_0 lane 35
//
// These two pins were found by measurement on the board, not from the
// schematic. The RFS header mirrors each row against the DE0-CV header, so a
// net name in the RFS schematic does not give the GPIO lane by itself.
//
// LEDR[9] blinks once in 0.67 s from a clocked counter, so it shows that the
// clock reaches the logic. LEDR[8:0] show SW[8:0].

module de0cv_sine_pwm (
    input  logic       CLOCK_50,
    input  logic [9:0] SW,
    input  logic [3:0] KEY,
    output logic [9:0] LEDR,
    output logic [6:0] HEX0,
    output logic       PMOD_AUDIO_L,
    output logic       PMOD_AUDIO_R
);

    // One PWM period is 2**8 = 256 clock cycles.
    localparam int PWM_WIDTH = 8;

    // The phase accumulator is 24 bits wide.
    localparam int PHASE_WIDTH = 24;

    // The table has 2**8 = 256 entries.
    localparam int TABLE_INDEX_WIDTH = 8;

    // The heartbeat divides 50 MHz down to 0.75 Hz.
    localparam int HEARTBEAT_WIDTH = 26;

    // A key must hold its new state for 2**17 clock cycles, which is 2.6 ms,
    // before the design accepts it.
    localparam int DEBOUNCE_WIDTH = 17;

    // The volume starts at half of its range.
    localparam logic [3:0] VOLUME_START = 4'd8;

    // The table holds one sine period. Entry k is 128 plus 127.5 times the
    // sine of k/256 turns, rounded to an integer. The range stays inside
    // 1..254, so the duty is never 0 per cent or 100 per cent.
    localparam logic [7:0] SINE [0:255] = '{
        8'd128, 8'd131, 8'd134, 8'd137, 8'd140, 8'd143, 8'd146, 8'd149,
        8'd152, 8'd155, 8'd158, 8'd162, 8'd165, 8'd167, 8'd170, 8'd173,
        8'd176, 8'd179, 8'd182, 8'd185, 8'd188, 8'd190, 8'd193, 8'd196,
        8'd198, 8'd201, 8'd203, 8'd206, 8'd208, 8'd211, 8'd213, 8'd215,
        8'd218, 8'd220, 8'd222, 8'd224, 8'd226, 8'd228, 8'd230, 8'd232,
        8'd234, 8'd235, 8'd237, 8'd238, 8'd240, 8'd241, 8'd243, 8'd244,
        8'd245, 8'd246, 8'd248, 8'd249, 8'd250, 8'd250, 8'd251, 8'd252,
        8'd253, 8'd253, 8'd254, 8'd254, 8'd254, 8'd254, 8'd254, 8'd254,
        8'd254, 8'd254, 8'd254, 8'd254, 8'd254, 8'd254, 8'd254, 8'd253,
        8'd253, 8'd252, 8'd251, 8'd250, 8'd250, 8'd249, 8'd248, 8'd246,
        8'd245, 8'd244, 8'd243, 8'd241, 8'd240, 8'd238, 8'd237, 8'd235,
        8'd234, 8'd232, 8'd230, 8'd228, 8'd226, 8'd224, 8'd222, 8'd220,
        8'd218, 8'd215, 8'd213, 8'd211, 8'd208, 8'd206, 8'd203, 8'd201,
        8'd198, 8'd196, 8'd193, 8'd190, 8'd188, 8'd185, 8'd182, 8'd179,
        8'd176, 8'd173, 8'd170, 8'd167, 8'd165, 8'd162, 8'd158, 8'd155,
        8'd152, 8'd149, 8'd146, 8'd143, 8'd140, 8'd137, 8'd134, 8'd131,
        8'd128, 8'd124, 8'd121, 8'd118, 8'd115, 8'd112, 8'd109, 8'd106,
        8'd103, 8'd100, 8'd97, 8'd93, 8'd90, 8'd88, 8'd85, 8'd82,
        8'd79, 8'd76, 8'd73, 8'd70, 8'd67, 8'd65, 8'd62, 8'd59,
        8'd57, 8'd54, 8'd52, 8'd49, 8'd47, 8'd44, 8'd42, 8'd40,
        8'd37, 8'd35, 8'd33, 8'd31, 8'd29, 8'd27, 8'd25, 8'd23,
        8'd21, 8'd20, 8'd18, 8'd17, 8'd15, 8'd14, 8'd12, 8'd11,
        8'd10, 8'd9, 8'd7, 8'd6, 8'd5, 8'd5, 8'd4, 8'd3,
        8'd2, 8'd2, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1,
        8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd1, 8'd2,
        8'd2, 8'd3, 8'd4, 8'd5, 8'd5, 8'd6, 8'd7, 8'd9,
        8'd10, 8'd11, 8'd12, 8'd14, 8'd15, 8'd17, 8'd18, 8'd20,
        8'd21, 8'd23, 8'd25, 8'd27, 8'd29, 8'd31, 8'd33, 8'd35,
        8'd37, 8'd40, 8'd42, 8'd44, 8'd47, 8'd49, 8'd52, 8'd54,
        8'd57, 8'd59, 8'd62, 8'd65, 8'd67, 8'd70, 8'd73, 8'd76,
        8'd79, 8'd82, 8'd85, 8'd88, 8'd90, 8'd93, 8'd97, 8'd100,
        8'd103, 8'd106, 8'd109, 8'd112, 8'd115, 8'd118, 8'd121, 8'd124
    };

    logic [PWM_WIDTH-1:0]       pwm_count;
    logic [PHASE_WIDTH-1:0]     phase;
    logic [7:0]                 sample;
    logic [7:0]                 scaled;
    logic                       pwm_out;
    logic [HEARTBEAT_WIDTH-1:0] heartbeat;

    // The volume holds its start value when the device powers up, so the tone
    // plays without a key press.
    logic [3:0]                 volume = VOLUME_START;
    logic [1:0]                 key_state;
    logic [1:0]                 key_sample;
    logic [DEBOUNCE_WIDTH-1:0]  key_timer;

    // The increment is SW shifted left by 8, so no multiplier is needed.
    logic [PHASE_WIDTH-1:0] increment;

    assign increment = {6'b000000, SW, 8'b00000000};

    // The volume scales the sine sample by VOLUME/16. A sample of 128 with a
    // volume of 8 gives a duty of 64 of 256, a quarter of full scale.
    //
    // The product needs 12 bits: the largest sample is 254 and the largest
    // volume is 15, so the product is at most 3810. Without those 12 bits the
    // multiply would be truncated to 8 bits before the shift.
    logic [11:0] scaled_product;

    assign scaled_product = sample * volume;
    assign scaled = scaled_product[11:4];

    always_ff @(posedge CLOCK_50) begin
        pwm_count <= pwm_count + 1'b1;
        pwm_out   <= (pwm_count < scaled);
        heartbeat <= heartbeat + 1'b1;

        // At the start of each PWM period one sine sample is taken, and the
        // phase moves one step.
        if (pwm_count == '0) begin
            phase  <= phase + increment;
            sample <= SINE[phase[PHASE_WIDTH-1 -: TABLE_INDEX_WIDTH]];
        end
    end

    // KEY0 and KEY1 change the volume. The timer runs only while the pin
    // state differs from the accepted state. When the timer reaches its top,
    // the new state is accepted once and the timer restarts.
    always_ff @(posedge CLOCK_50) begin
        key_sample <= KEY[1:0];

        if (key_sample != key_state) begin
            if (key_timer == '1) begin
                key_state <= key_sample;
                key_timer <= '0;

                // KEY0 raises the volume and KEY1 lowers it. A key reads low
                // while it is pressed, so the old state must be high.
                if (key_state[0] && !key_sample[0] && volume != 4'd15) begin
                    volume <= volume + 1'b1;
                end else if (key_state[1] && !key_sample[1] && volume != 4'd0) begin
                    volume <= volume - 1'b1;
                end
            end else begin
                key_timer <= key_timer + 1'b1;
            end
        end else begin
            key_timer <= '0;
        end
    end

    // HEX0 shows the volume level as a hexadecimal digit. The display is
    // common anode, so a low segment pin lights the segment.
    always_comb begin
        case (volume)
            4'd0:    HEX0 = 7'b1000000;
            4'd1:    HEX0 = 7'b1111001;
            4'd2:    HEX0 = 7'b0100100;
            4'd3:    HEX0 = 7'b0110000;
            4'd4:    HEX0 = 7'b0011001;
            4'd5:    HEX0 = 7'b0010010;
            4'd6:    HEX0 = 7'b0000010;
            4'd7:    HEX0 = 7'b1111000;
            4'd8:    HEX0 = 7'b0000000;
            4'd9:    HEX0 = 7'b0010000;
            4'd10:   HEX0 = 7'b0001000;
            4'd11:   HEX0 = 7'b0000011;
            4'd12:   HEX0 = 7'b1000110;
            4'd13:   HEX0 = 7'b0100001;
            4'd14:   HEX0 = 7'b0000110;
            default: HEX0 = 7'b0001110;
        endcase
    end

    assign PMOD_AUDIO_L = pwm_out;
    assign PMOD_AUDIO_R = pwm_out;

    assign LEDR = {heartbeat[HEARTBEAT_WIDTH-1], SW[8:0]};

endmodule

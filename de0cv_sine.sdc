# Timing constraints for the sine tone on a DE0-CV board.
#
# The design has one clock domain. It holds no clock crossing, no phase-locked
# loop and no source-synchronous interface.
#
# The audio outputs feed an analog amplifier input, not a clocked bus. The
# amplifier does not sample the PWM lane on an edge, so there is no setup or
# hold window to constrain. No false path is declared: the only path the
# analyser must check is the register-to-register path inside the FPGA, and
# that path is bounded by the clock below.

create_clock -period 20 [get_ports CLOCK_50]

derive_clock_uncertainty

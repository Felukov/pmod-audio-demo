# Timing constraints for the sine tone on a DE0-CV board.
#
# The design has one clock domain. It holds no clock crossing, no phase-locked
# loop and no source-synchronous interface.
#
# The audio outputs feed an analog amplifier input, not a clocked bus. No false
# path is declared. The clock below bounds every path the analyser checks.

create_clock -period 20 [get_ports CLOCK_50]

derive_clock_uncertainty

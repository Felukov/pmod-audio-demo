#!/bin/bash
# Programs de0cv_sine.sof into the FPGA. Set Q to the bin directory of your
# Quartus install.
set -euo pipefail
cd "$(dirname "$0")"

Q=${Q:-$HOME/intelFPGA_lite/18.1/quartus/bin}

"$Q/jtagconfig"
"$Q/quartus_pgm" -m jtag -o "p;de0cv_sine.sof"

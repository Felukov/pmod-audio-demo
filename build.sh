#!/bin/bash
# Builds de0cv_sine.sof. Set Q to the bin directory of your Quartus install.
set -euo pipefail
cd "$(dirname "$0")"

Q=${Q:-$HOME/intelFPGA_lite/18.1/quartus/bin}

"$Q/quartus_map" de0cv_sine
"$Q/quartus_fit" de0cv_sine
"$Q/quartus_asm" de0cv_sine
"$Q/quartus_sta" de0cv_sine

ls -l de0cv_sine.sof

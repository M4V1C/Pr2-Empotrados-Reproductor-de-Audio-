#!/usr/bin/env bash
# Regenera el SoC: tools/build_soc.tcl -> hw/quartus/soc_system.qsys
#                  -> HDL de sintesis (soc_system/synthesis/*.qip) + .sopcinfo
# Uso (WSL):  scripts/build-hw.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/scripts/env.sh"
cd "$HERE/hw/quartus"

echo ">> qsys-script: tools/build_soc.tcl -> soc_system.qsys"
qsys-script --script="$HERE/tools/build_soc.tcl"

echo ">> qsys-generate: HDL de sintesis (Verilog)"
qsys-generate soc_system.qsys --synthesis=VERILOG \
              --output-directory="$HERE/hw/quartus/soc_system"

SOPC=$(ls "$HERE"/hw/quartus/soc_system.sopcinfo "$HERE"/hw/quartus/soc_system/soc_system.sopcinfo 2>/dev/null | head -1 || true)
echo ">> Listo."
echo "   .qip     : hw/quartus/soc_system/synthesis/soc_system.qip"
echo "   .sopcinfo: ${SOPC:-NO ENCONTRADO (revisar salida de qsys-generate)}"

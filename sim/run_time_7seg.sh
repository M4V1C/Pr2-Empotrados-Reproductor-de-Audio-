#!/usr/bin/env bash
# Compila y simula tb_time_7seg en Questa.
#
# Uso (desde cualquier carpeta; el script se mueve solo a sim/):
#   sim/run_time_7seg.sh     -> consola, guarda el log en sim/time_7seg.log
#   sim/run_time_7seg.sh gui -> abre Questa con las formas de onda (wave_time_7seg.do)
#
# Requiere vlib/vlog/vsim en el PATH (source scripts/env.sh)

set -euo pipefail
cd "$(dirname "$0")"
rm -rf work
vlib work
vlog -quiet ../hw/ip/audio_dsp/time_7seg.v
vlog -quiet -sv tb_time_7seg.sv

if [ "${1:-}" = "gui" ]; then
    vsim tb_time_7seg -voptargs=+acc -do wave_time_7seg.do
else
    vsim -c tb_time_7seg -do "run -all; quit -f" | tee time_7seg.log
    echo
    grep -E "RESULTADO|FAIL" time_7seg.log || true
fi

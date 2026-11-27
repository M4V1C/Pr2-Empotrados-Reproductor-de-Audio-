#!/usr/bin/env bash
# Compila y simula tb_ganancia en Questa.
#
# Uso (desde cualquier carpeta; el script se mueve solo a sim/):
#   sim/run_ganancia.sh     -> consola, guarda el log en sim/ganancia.log
#   sim/run_ganancia.sh gui -> abre Questa con las formas de onda (wave_ganancia.do)
#
# Requiere vlib/vlog/vsim en el PATH

set -euo pipefail
cd "$(dirname "$0")"
rm -rf work
vlib work
vlog -quiet ../hw/ip/audio_dsp/ganancia.v
vlog -quiet -sv tb_ganancia.sv

if [ "${1:-}" = "gui" ]; then
    vsim tb_ganancia -voptargs=+acc -do wave_ganancia.do
else
    vsim -c tb_ganancia -do "run -all; quit -f" | tee ganancia.log
    echo
    grep -E "RESULTADO|FAIL" ganancia.log || true
fi

#!/usr/bin/env bash
#============================================================================
# run_fir_pbajo.sh - Compila y simula tb_fir_pbajo en Questa (issue F-02).
#
# Uso (desde cualquier carpeta; el script se mueve solo a sim/):
#   sim/run_fir_pbajo.sh -> consola, guarda el log en sim/fir_pbajo.log
#   sim/run_fir_pbajo.sh gui -> abre Questa con las formas de onda
#
# Requiere vlib/vlog/vsim en el PATH 
#============================================================================

set -euo pipefail
cd "$(dirname "$0")"
rm -rf work
vlib work
vlog -quiet ../hw/ip/audio_dsp/fir_pbajo.v
vlog -quiet -sv tb_fir_pbajo.sv
if [ "${1:-}" = "gui" ]; then
    vsim tb_fir_pbajo -voptargs=+acc -do wave_fir_pbajo.do
else
    vsim -c tb_fir_pbajo -do "run -all; quit -f" | tee fir_pbajo.log
    echo
    grep -E "RESULTADO|FAIL" fir_pbajo.log || true
fi

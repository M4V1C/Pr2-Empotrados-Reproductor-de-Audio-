# Compila y simula tb_audio_dsp en Questa 
#
# Uso (desde cualquier carpeta; el script se mueve solo a sim/):
#   sim/run_audio_dsp.sh     -> consola, guarda el log en sim/audio_dsp.log
#   sim/run_audio_dsp.sh gui -> abre Questa con todas las senales del DUT
#
# Requiere vlib/vlog/vsim en el PATH 

set -euo pipefail
cd "$(dirname "$0")"
rm -rf work
vlib work
vlog -quiet ../hw/ip/audio_dsp/fir_pbajo.v
vlog -quiet ../hw/ip/audio_dsp/ganancia.v
vlog -quiet ../hw/ip/audio_dsp/time_7seg.v
vlog -quiet ../hw/ip/audio_dsp/audio_dsp.v
vlog -quiet -sv tb_audio_dsp.sv

if [ "${1:-}" = "gui" ]; then
    vsim tb_audio_dsp -voptargs=+acc -do "add wave -radix hex /tb_audio_dsp/dut/*; run -all"
else
    vsim -c tb_audio_dsp -do "run -all; quit -f" | tee audio_dsp.log
    echo
    grep -E "RESULTADO|FAIL" audio_dsp.log || true
fi

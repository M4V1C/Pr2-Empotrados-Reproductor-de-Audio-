#!/usr/bin/env bash
# =============================================================================================
#           ~~~~~ Recursos y tiempo de audio_dsp compilado SOLO en Quartus ~~~~~
#
# Compila hw/ip/audio_dsp/ como proyecto aparte (Cyclone V de la DE1-SoC):
#   0. Proyecto             -> dispositivo, archivos, reloj y pines virtuales
#   1. Analysis & Synthesis -> latches y critical warnings
#   2. Fitter               -> recursos finales por submodulo
#   3. Timing Analyzer      -> Fmax con reloj de 50 MHz y peores caminos, guarda resumen en:
#                              docs/verifica/recursos_audio_dsp.txt
#
# Uso (desde cualquier carpeta; trabaja relativo a la raiz del repo):
#   tools/recursos_audio_dsp.sh
#
# Requiere quartus_sh/quartus_map/quartus_fit/quartus_sta en el PATH (con WSL: 'qenv')
# Crea un proyecto temporal queda en build/recursos_audio_dsp/ (está en .gitignore)
# Correrlo de nuevo cuando cambie audio_dsp (al completar time_7seg)
# ===========================================================================================

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IP="$ROOT/hw/ip/audio_dsp"
WORK="$ROOT/build/recursos_audio_dsp"
SALIDA="$ROOT/docs/verifica/recursos_audio_dsp.txt"
FAMILY="Cyclone V"
PART="5CSEMA5F31C6" #FPGA de la DE1-SoC
CLK_NS="20.000" #50 MHz, igual al reloj del Nios V

# ~~~ herramientas de Quartus ~~~
if ! command -v quartus_map >/dev/null 2>&1; then
    if [ -f "$HOME/quartus-tools/scripts/general/env.sh" ]; then
        # shellcheck disable=SC1091
        source "$HOME/quartus-tools/scripts/general/env.sh" >/dev/null
    fi
fi
command -v quartus_map >/dev/null 2>&1 || { echo "ERROR: quartus_map no esta en el PATH (correr 'qenv')"; exit 1; }
# correr <herramienta> <args...>: muestra el resultado y se detiene si falla
correr() {
    local salida
    salida=$("$@" 2>&1) || true
    { grep -E "was successful|^Error" <<< "$salida" || true; } | head -5
    if ! grep -q "was successful" <<< "$salida"; then
        echo "ERROR: fallo '$*' (ver los reportes en ${WORK#"$ROOT"/}/)"
        exit 1
    fi
}

# ~~~ proyecto temporal ~~~
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"
cat > audio_dsp.sdc <<EOF_SDC
create_clock -name clk -period $CLK_NS [get_ports clk]
derive_clock_uncertainty
EOF_SDC
# Proyecto completo ANTES de sintetizar. Dentro del sistema, el bus Avalon y los displays
# NO son pines del FPGA de este modulo: se marcan como pines VIRTUALES (conexiones internas).
# Solo el reloj va a un pin real: CLOCK_50 de la DE1-SoC (PIN_AF14). Sin esto, el Fitter da un Critical Warning 169085
cat > crear_proyecto.tcl <<'EOF_TCL'
set ip   [lindex $quartus(args) 0]
set fam  [lindex $quartus(args) 1]
set part [lindex $quartus(args) 2]
project_new audio_dsp -overwrite
set_global_assignment -name FAMILY $fam
set_global_assignment -name DEVICE $part
set_global_assignment -name TOP_LEVEL_ENTITY audio_dsp
foreach f {fir_pbajo.v ganancia.v time_7seg.v audio_dsp.v} {
    set_global_assignment -name VERILOG_FILE [file join $ip $f]
}
set_global_assignment -name SDC_FILE audio_dsp.sdc
set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
set_location_assignment PIN_AF14 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk
foreach p {rst avs_read avs_write avs_waitrequest avs_address[*] avs_readdata[*]
           avs_writedata[*] hex0[*] hex1[*] hex2[*] hex3[*] hex4[*] hex5[*]} {
    set_instance_assignment -name VIRTUAL_PIN ON -to $p
}
export_assignments
project_close
EOF_TCL

cat > peor_camino.tcl <<'EOF_TCL'
project_open audio_dsp
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 5 -detail summary -file peor_camino.txt
delete_timing_netlist
project_close
EOF_TCL

echo "===== Proyecto ====="
correr quartus_sh -t crear_proyecto.tcl "$IP" "$FAMILY" "$PART"
echo "===== 1. Analysis & Synthesis ====="
correr quartus_map audio_dsp
echo "===== 2. Fitter ====="
correr quartus_fit audio_dsp
echo "===== 3. Timing Analyzer ====="
correr quartus_sta audio_dsp
correr quartus_sta -t peor_camino.tcl

# ~~~ reportes (en la carpeta del proyecto o en output_files/) ~~~
rpt() {
    local f
    for f in "audio_dsp.$1.rpt" "output_files/audio_dsp.$1.rpt"; do
        if [ -f "$f" ]; then echo "$f"; return 0; fi
    done
    return 0
}
MAP=$(rpt map); FIT=$(rpt fit); STA=$(rpt sta)
[ -n "$MAP" ] && [ -n "$FIT" ] && [ -n "$STA" ] || { echo "ERROR: faltan reportes de Quartus"; exit 1; }
# seccion "<titulo>" <reporte>: imprime la tabla que empieza con "; <titulo>"
seccion() { sed -n "/^; $1/,/^\$/p" "$2"; }
# (con pipefail, grep sin coincidencias "falla": por eso los '|| true')
LATCHES=$( { grep -ci "latch" "$MAP" || true; } )
CRITICAS=$( { grep -h "^Critical Warning" "$MAP" "$FIT" "$STA" || true; } | wc -l )

# ~~~ resumen ~~~
{
    echo "recursos_audio_dsp | commit $(git -C "$ROOT" rev-parse --short HEAD) | $(date '+%Y-%m-%d %H:%M')"
    { quartus_sh --version | grep -E "Version" || true; } | head -1
    echo "Dispositivo: $FAMILY $PART | Reloj: $CLK_NS ns (50 MHz) en CLOCK_50 | Demas puertos: pines virtuales"
    echo "Lineas con 'latch' en la sintesis: $LATCHES | Critical warnings: $CRITICAS"
    echo
    echo "==================== FITTER: RESUMEN ===================="
    seccion "Fitter Summary" "$FIT"
    echo "========== FITTER: RECURSOS POR SUBMODULO (finales) =========="
    seccion "Fitter Resource Utilization by Entity" "$FIT" | cut -c1-200
    echo "============== TIMING: Fmax (peor caso y 0 C) =============="
    { seccion "Slow 1100mV 85C Model Fmax Summary" "$STA" | grep -v -E "^(This panel|$)"; } || true
    { seccion "Slow 1100mV 0C Model Fmax Summary"  "$STA" | grep -v -E "^(This panel|$)"; } || true
    echo "============== TIMING: SETUP (peor caso) =============="
    seccion "Slow 1100mV 85C Model Setup Summary" "$STA"
    echo "============== TIMING: 5 PEORES CAMINOS =============="
    cat peor_camino.txt
    echo
    echo "============== WARNINGS (sintesis, fitter, timing) =============="
    { grep -h -E "^(Critical )?Warning \(" "$MAP" "$FIT" "$STA" || true; } | cut -c1-200 | sort | uniq -c | sort -rn
} > "$SALIDA"
echo
echo "Resumen guardado en ${SALIDA#"$ROOT"/}"
{ grep -A4 "Slow 1100mV 85C Model Fmax Summary" "$SALIDA" || true; } | tail -1
echo "Latches: $LATCHES | Critical warnings: $CRITICAS"

#===============================================================================
#                 ~~~~~ Formas de onda de tb_audio_dsp ~~~~~
# Se usa desde run_audio_dsp.sh gui (en sim/)
#
# Deja la vista en la PRIMERA transaccion con el FIR encendido (TC3, impulso a 8kHz):
#    escritura de SAMPLE_IN -> lectura de SAMPLE_OUT con waitrequest -> dato listo
# Los cursores marcan cuanto dura el waitrequest.
# Marcadores (View > Bookmarks): 
#    "fir" (esa transaccion) y "bypass" (TC2).
#===============================================================================
onerror {resume}
onbreak {resume}
quietly WaveActivateNextPane {} 0
delete wave *
# ---------------------------------------------------------------------------
# Nombres en lugar de numeros
# ---------------------------------------------------------------------------
# Direccion del bus (palabra): 0..9 registros, 10..31 libres, 32..63 COEF
set nombres {ID CTRL STATUS SAMPLE_IN SAMPLE_OUT GAIN FS TIME TRACK FRAME_CNT}
for {set i 10} {$i < 32} {incr i} { lappend nombres [format "LIBRE_%02d" $i] }
for {set i 0}  {$i < 32} {incr i} { lappend nombres [format "COEF%02d" $i] }
virtual type $nombres reg_type
virtual function -install /tb_audio_dsp { (reg_type)/tb_audio_dsp/avs_address } registro
# Estado del FIR (0, 1, 2)
virtual type { S_IDLE S_MAC S_RND } fsm_type
virtual function -install /tb_audio_dsp/dut/u_fir { (fsm_type)/tb_audio_dsp/dut/u_fir/state } estado
# ---------------------------------------------------------------------------
# Señales
# ---------------------------------------------------------------------------
add wave -noupdate /tb_audio_dsp/clk
add wave -noupdate /tb_audio_dsp/rst

add wave -noupdate -expand -group {Bus Avalon} /tb_audio_dsp/registro
add wave -noupdate -expand -group {Bus Avalon} /tb_audio_dsp/avs_write
add wave -noupdate -expand -group {Bus Avalon} -radix hexadecimal /tb_audio_dsp/avs_writedata
add wave -noupdate -expand -group {Bus Avalon} /tb_audio_dsp/avs_read
add wave -noupdate -expand -group {Bus Avalon} -color {Orange} /tb_audio_dsp/avs_waitrequest
add wave -noupdate -expand -group {Bus Avalon} -radix hexadecimal /tb_audio_dsp/avs_readdata

add wave -noupdate -expand -group {Control interno} /tb_audio_dsp/dut/ctrl_fir_en
add wave -noupdate -expand -group {Control interno} /tb_audio_dsp/dut/hist_clr
add wave -noupdate -expand -group {Control interno} /tb_audio_dsp/dut/wr_sample_in
add wave -noupdate -expand -group {Control interno} /tb_audio_dsp/dut/fir_start
add wave -noupdate -expand -group {Control interno} /tb_audio_dsp/dut/ocupado
add wave -noupdate -expand -group {Control interno} /tb_audio_dsp/dut/load_out
add wave -noupdate -expand -group {Control interno} -radix hexadecimal /tb_audio_dsp/dut/sample_out_q

add wave -noupdate -expand -group {FIR (u_fir)} /tb_audio_dsp/dut/u_fir/estado
add wave -noupdate -expand -group {FIR (u_fir)} /tb_audio_dsp/dut/fir_busy
add wave -noupdate -expand -group {FIR (u_fir)} /tb_audio_dsp/dut/fir_done
add wave -noupdate -expand -group {FIR (u_fir)} -radix unsigned /tb_audio_dsp/dut/u_fir/channel
add wave -noupdate -expand -group {FIR (u_fir)} -radix unsigned /tb_audio_dsp/dut/u_fir/k

configure wave -namecolwidth 200
configure wave -signalnamewidth 1
configure wave -valuecolwidth 100
configure wave -timelineunits ns
update

# ---------------------------------------------------------------------------
# Buscar la primera transaccion con waitrequest
# ---------------------------------------------------------------------------
# Tiempo actual en ns, sin importar la unidad con que lo devuelva Questa.
# $Now trae separador de miles ("81,651 ns"): se quitan las comas antes de leerlo.
proc tiempo_ns {} {
    global Now
    set texto [string map {, ""} $Now]
    scan $texto "%d %s" valor unidad
    switch -- $unidad {
        fs {return [expr {$valor / 1000000}]}
        ps {return [expr {$valor / 1000}]}
        us {return [expr {$valor * 1000}]}
        default {return $valor}
    }
}
# Solo cuenta la espera de una LECTURA: al aceptar la escritura de SAMPLE_IN
# (flanco de subida) el FIR ya esta ocupado y waitrequest sube 1 ns, hasta que
# el maestro baja avs_write. Avalon solo mira waitrequest en los flancos, asi
# que ese pulso no es una espera real.
when -label inicio_wait {/tb_audio_dsp/avs_read == 1 && /tb_audio_dsp/avs_waitrequest == 1} {stop}
run -all
nowhen inicio_wait
quietly set t_ini [tiempo_ns]

when -label fin_wait {/tb_audio_dsp/avs_waitrequest == 0} {stop}
run -all
nowhen fin_wait
quietly set t_fin [tiempo_ns]

run 200 ns

quietly set ciclos [expr {($t_fin - $t_ini) / 20}]
echo "waitrequest: de $t_ini ns a $t_fin ns = [expr {$t_fin - $t_ini}] ns = $ciclos ciclos de 20 ns"

quietly wave cursor add -time "$t_ini ns" -name {waitrequest sube}
quietly wave cursor add -time "$t_fin ns" -name {waitrequest baja}

bookmark add wave fir    "{[expr {$t_ini - 120}] ns} {[expr {$t_fin + 120}] ns}" 0
bookmark add wave bypass {{0 ns} {600 ns}} 0

WaveRestoreZoom "[expr {$t_ini - 120}] ns" "[expr {$t_fin + 120}] ns"

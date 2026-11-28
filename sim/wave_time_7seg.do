#===============================================================================
#                 ~~~~~ Formas de onda de tb_time_7seg ~~~~~
# Se usa desde run_time_7seg.sh gui (en sim/)
#
# Los displays se ven como digitos (radix "seg7"): 7'h40 -> "0", 7'h7F -> "apag", 7'h3F -> "-".
# Deja la vista en T3 (primer segundo con fs = 4). Marcadores (View > Bookmarks):
#    "T3 00:01"        4 pulsos -> 00:01, y los displays cambian un ciclo despues
#    "T4 00:59->01:00" acarreo de segundos a minutos
#    "T5 tope 99:59"   llega a 99:59 y ya no avanza
#    "T6 clr+tick"     time_clr en el mismo ciclo que el pulso que completaria el segundo
#===============================================================================
onerror {resume}
onbreak {resume}
quietly WaveActivateNextPane {} 0
delete wave *

# Segmentos activos en bajo (bit 0 = a ... bit 6 = g) -> digito
radix define seg7 {
    7'h40 "0", 7'h79 "1", 7'h24 "2", 7'h30 "3", 7'h19 "4",
    7'h12 "5", 7'h02 "6", 7'h78 "7", 7'h00 "8", 7'h10 "9",
    7'h7F "apag", 7'h3F "-",
    -default hex
}

set tb  /tb_time_7seg
set dut /tb_time_7seg/dut

add wave -noupdate $tb/clk
add wave -noupdate -expand -group {Entradas} $dut/rst
add wave -noupdate -expand -group {Entradas} $dut/tick_par
add wave -noupdate -expand -group {Entradas} $dut/time_clr
add wave -noupdate -expand -group {Entradas} $dut/hex_en
add wave -noupdate -expand -group {Entradas} -radix unsigned $dut/fs
add wave -noupdate -expand -group {Entradas} -radix unsigned $dut/track

add wave -noupdate -expand -group {Preescalador} -radix unsigned $dut/presc
add wave -noupdate -expand -group {Preescalador} $dut/fin_seg
add wave -noupdate -expand -group {Preescalador} $dut/tope

add wave -noupdate -expand -group {Contadores BCD} -radix unsigned $dut/min_d
add wave -noupdate -expand -group {Contadores BCD} -radix unsigned $dut/min_u
add wave -noupdate -expand -group {Contadores BCD} -radix unsigned $dut/seg_d
add wave -noupdate -expand -group {Contadores BCD} -radix unsigned $dut/seg_u

add wave -noupdate -expand -group {TIME (binario)} -radix hexadecimal $dut/time_mmss
add wave -noupdate -expand -group {TIME (binario)} -radix unsigned $dut/min_bin
add wave -noupdate -expand -group {TIME (binario)} -radix unsigned $dut/seg_bin

add wave -noupdate -expand -group {Displays} -radix seg7 $dut/hex5
add wave -noupdate -expand -group {Displays} -radix seg7 $dut/hex4
add wave -noupdate -expand -group {Displays} -radix seg7 $dut/hex3
add wave -noupdate -expand -group {Displays} -radix seg7 $dut/hex2
add wave -noupdate -expand -group {Displays} -radix seg7 $dut/hex1
add wave -noupdate -expand -group {Displays} -radix seg7 $dut/hex0

configure wave -namecolwidth 200
configure wave -valuecolwidth 70
configure wave -timelineunits ns

# La simulacion completa tarda unos segundos
run -all

bookmark add wave "T3 00:01"        {{60 ns}     {420 ns}}
bookmark add wave "T4 00:59->01:00" {{4890 ns}   {5150 ns}}
bookmark add wave "T5 tope 99:59"   {{480050 ns} {480330 ns}}
bookmark add wave "T6 clr+tick"     {{480800 ns} {481100 ns}}

WaveRestoreCursors {{tick 4 -> 00:01} {270 ns} 0} {{displays} {290 ns} 0}
WaveRestoreZoom {60 ns} {420 ns}
update

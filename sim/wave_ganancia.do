# Wave form de tb_ganancia
# Se usa desde: run_ganancia.sh gui 
# como ganancia es combinacional: el TB cambia la entrada cada 1 ns para hacer las pruebas
onerror {resume}
quietly WaveActivateNextPane {} 0
delete wave *

add wave -noupdate -expand -group {Entrada} -radix hexadecimal /tb_ganancia/dut/x_lr
add wave -noupdate -expand -group {Entrada} -radix decimal     /tb_ganancia/dut/x_l
add wave -noupdate -expand -group {Entrada} -radix decimal     /tb_ganancia/dut/x_r
add wave -noupdate -expand -group {Entrada} -radix unsigned    /tb_ganancia/dut/gain

add wave -noupdate -expand -group {Canal L} -radix decimal /tb_ganancia/dut/prod_l
add wave -noupdate -expand -group {Canal L} -radix decimal /tb_ganancia/dut/shift_l
add wave -noupdate -expand -group {Canal L} -radix decimal /tb_ganancia/dut/y_l

add wave -noupdate -expand -group {Canal R} -radix decimal /tb_ganancia/dut/prod_r
add wave -noupdate -expand -group {Canal R} -radix decimal /tb_ganancia/dut/shift_r
add wave -noupdate -expand -group {Canal R} -radix decimal /tb_ganancia/dut/y_r

add wave -noupdate -expand -group {Salida} -radix hexadecimal /tb_ganancia/dut/y_lr
add wave -noupdate -expand -group {Salida} /tb_ganancia/dut/sat

configure wave -namecolwidth 220
configure wave -valuecolwidth 90
configure wave -timelineunits ns
update

# G1: los 100 casos de borde (gain = 0, 2048, 4096, 8191); 'run -all' para el resto
run 100 ns
wave zoom full

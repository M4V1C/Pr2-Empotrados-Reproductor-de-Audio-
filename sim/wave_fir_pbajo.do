#======================================================================
# ~~~~~ Formas de onda de tb_fir_pbajo (para issues F-02 / F-10) ~~~~~
# Se usa desde run_fir_pbajo.sh gui (el directorio actual es sim/)
#======================================================================
onerror {resume}
quietly WaveActivateNextPane {} 0
delete wave *

# Estado de la maquina con nombre en lugar de numero (0, 1, 2)
virtual type { S_IDLE S_MAC S_RND } fsm_type
virtual function -install /tb_fir_pbajo/dut { (fsm_type)/tb_fir_pbajo/dut/state } estado

add wave -noupdate -divider {Control}
add wave -noupdate /tb_fir_pbajo/dut/clk
add wave -noupdate /tb_fir_pbajo/dut/rst
add wave -noupdate /tb_fir_pbajo/dut/start
add wave -noupdate /tb_fir_pbajo/dut/busy
add wave -noupdate /tb_fir_pbajo/dut/done
add wave -noupdate /tb_fir_pbajo/dut/sat
add wave -noupdate /tb_fir_pbajo/dut/hist_clr
add wave -noupdate /tb_fir_pbajo/dut/estado

add wave -noupdate -divider {Datos}
add wave -noupdate -radix decimal /tb_fir_pbajo/dut/x_l
add wave -noupdate -radix decimal /tb_fir_pbajo/dut/x_r
add wave -noupdate -radix decimal /tb_fir_pbajo/dut/y_l
add wave -noupdate -radix decimal /tb_fir_pbajo/dut/y_r

add wave -noupdate -divider {MAC interno}
add wave -noupdate -radix unsigned /tb_fir_pbajo/dut/channel
add wave -noupdate -radix unsigned /tb_fir_pbajo/dut/k
add wave -noupdate -radix decimal  /tb_fir_pbajo/dut/c_sel
add wave -noupdate -radix decimal  /tb_fir_pbajo/dut/h_sel
add wave -noupdate -radix decimal  /tb_fir_pbajo/dut/producto
add wave -noupdate -radix decimal  /tb_fir_pbajo/dut/acc
add wave -noupdate -radix decimal  /tb_fir_pbajo/dut/acc_shift
add wave -noupdate -radix decimal  /tb_fir_pbajo/dut/y_sat

add wave -noupdate -divider {Coeficientes}
add wave -noupdate /tb_fir_pbajo/dut/coef_we
add wave -noupdate -radix unsigned /tb_fir_pbajo/dut/coef_addr
add wave -noupdate -radix decimal  /tb_fir_pbajo/dut/coef_wdata
add wave -noupdate -radix decimal  /tb_fir_pbajo/dut/coef_rdata

configure wave -namecolwidth 200
configure wave -valuecolwidth 90
configure wave -timelineunits ns
update

# Carga de coeficientes + los primeros pares; luego 'run -all' para el resto
run 5 us
wave zoom full

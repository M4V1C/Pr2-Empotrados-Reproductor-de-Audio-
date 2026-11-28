# =====================================================================
# de1_soc.sdc -- Restricciones de tiempo (Synopsys Design Constraints)
# =====================================================================

# Reloj de la placa: 50 MHz -> periodo de 20 ns
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]

# Reloj del JTAG (lo usan la JTAG UART y el modulo de depuracion del Nios).
# Lo maneja el USB-Blaster II; se restringe a 30 MHz y se declara
# asincrono respecto a CLOCK_50: los IP ya cruzan ese dominio con
# sincronizadores, asi que no tiene sentido analizar rutas entre ambos.
create_clock -name altera_reserved_tck -period 33.333 [get_ports {altera_reserved_tck}]
set_clock_groups -asynchronous -group [get_clocks {altera_reserved_tck}]

# Relojes derivados de PLL (fase 3: reloj del codec) e incertidumbre
derive_pll_clocks
derive_clock_uncertainty

# Entradas y salidas lentas y asincronas: botones (humanos) y LED.
# No tienen relacion de fase con CLOCK_50; se sincronizan dentro.
set_false_path -from [get_ports {KEY[*]}]
set_false_path -to   [get_ports {LEDR[*]}]

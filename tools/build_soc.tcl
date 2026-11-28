# =====================================================================
# tools/build_soc.tcl -- Descripcion del SoC en Platform Designer
# Proyecto II CE-1113: reproductor de audio sobre DE1-SoC
#
# Este script ES la fuente del sistema: soc_system.qsys se regenera
# desde aqui (qsys-script), asi que los cambios se hacen en este archivo
# y no a mano en la GUI. Uso (lo llama scripts/build-hw.sh):
#     cd hw/quartus && qsys-script --script=../../tools/build_soc.tcl
#
# Fase 1: Nios V/m + RAM on-chip + JTAG UART.
# Las fases siguientes agregan bloques al final, SIN mover las bases ya
# asignadas (ver docs/hardware.md), para que system.h no cambie.
# =====================================================================
package require -exact qsys 25.1

create_system soc_system
set_project_property DEVICE_FAMILY {Cyclone V}
set_project_property DEVICE        {5CSEMA5F31C6}

# ---------------------------------------------------------------------
# Reloj y reset del lado FPGA (50 MHz desde CLOCK_50)
# clock_source no genera reloj: solo lo recibe del tope y lo reparte.
# Su reset de entrada (reset_n) pasa por un reset controller que lo
# sincroniza con clk: se activa de inmediato y se libera en un flanco.
# ---------------------------------------------------------------------
add_instance clk_50 clock_source
set_instance_parameter_value clk_50 clockFrequency      50000000
set_instance_parameter_value clk_50 clockFrequencyKnown 1
set_instance_parameter_value clk_50 resetSynchronousEdges DEASSERT

# ---------------------------------------------------------------------
# CPU: Nios V/m (RV32IA, sin cache, pipeline simple)
# ---------------------------------------------------------------------
add_instance cpu intel_niosv_m
set_instance_parameter_value cpu resetSlave  {nios_ram.s1}
set_instance_parameter_value cpu resetOffset 0
set_instance_parameter_value cpu enableDebug 1

# ---------------------------------------------------------------------
# RAM del Nios: 128 KiB de M10K (codigo + datos + pila)
# Se inicializa en la compilacion con nios_ram.hex (imagen del .elf),
# por eso el Nios arranca solo al configurar la FPGA.
# ---------------------------------------------------------------------
add_instance nios_ram altera_avalon_onchip_memory2
set_instance_parameter_value nios_ram memorySize   131072
set_instance_parameter_value nios_ram dataWidth    32
set_instance_parameter_value nios_ram dualPort     0
set_instance_parameter_value nios_ram writable     1
set_instance_parameter_value nios_ram initMemContent        1
set_instance_parameter_value nios_ram useNonDefaultInitFile 1
set_instance_parameter_value nios_ram initializationFileName {nios_ram.hex}

# ---------------------------------------------------------------------
# JTAG UART: stdout/stdin del Nios por el cable USB-Blaster II
# ---------------------------------------------------------------------
add_instance jtag_uart altera_avalon_jtag_uart

# ---- Reloj y reset a todos ----
foreach m {cpu jtag_uart} {
    add_connection clk_50.clk       $m.clk
    add_connection clk_50.clk_reset $m.reset
}
add_connection clk_50.clk       nios_ram.clk1
add_connection clk_50.clk_reset nios_ram.reset1

# ---- Avalon-MM: quien (manager) ve a quien (agent) y en que direccion ----
add_connection cpu.instruction_manager nios_ram.s1
add_connection cpu.data_manager        nios_ram.s1
add_connection cpu.data_manager        jtag_uart.avalon_jtag_slave
add_connection cpu.data_manager        cpu.timer_sw_agent
add_connection cpu.data_manager        cpu.dm_agent

# Mapa de memoria (fijo para todo el proyecto; ver docs/hardware.md)
set_connection_parameter_value cpu.instruction_manager/nios_ram.s1     baseAddress 0x00000000
set_connection_parameter_value cpu.data_manager/nios_ram.s1            baseAddress 0x00000000
set_connection_parameter_value cpu.data_manager/jtag_uart.avalon_jtag_slave baseAddress 0x00030000
set_connection_parameter_value cpu.data_manager/cpu.timer_sw_agent     baseAddress 0x00030040
set_connection_parameter_value cpu.data_manager/cpu.dm_agent           baseAddress 0x00040000

# ---- Interrupciones: platform_irq_rx es el receptor de IRQ del Nios ----
add_connection cpu.platform_irq_rx jtag_uart.irq
set_connection_parameter_value cpu.platform_irq_rx/jtag_uart.irq irqNumber 0

# ---- Exportar al tope: se vuelven puertos de soc_system ----
add_interface clk   clock sink
set_interface_property clk   EXPORT_OF clk_50.clk_in
add_interface reset reset sink
set_interface_property reset EXPORT_OF clk_50.clk_in_reset

save_system soc_system.qsys

# ====================================================================================================
#                    ~~~~~ Descripción de audio_dsp para Platform Designer ~~~~~
#
# El nombre <modulo>_hw.tcl es la convencion de Platform Designer: con ese sufijo aparece solo
# en el IP Catalog agregando la carpeta en donde se encuentre en el IP Search Path (no cambiar nombre)
#
# Interfaces (ver encabezado de audio_dsp.v):
#   clock         clk
#   reset         rst (activo en ALTO)
#   avalon_slave  avs_* : 32 bits, por palabra, 64 palabras (256 bytes),
#                 latencia de lectura 0, con waitrequest, sin byteenable
#   hex           conduit hex0..hex5 (7 bits c/u) -> exportar al top-level
# ====================================================================================================
package require -exact qsys 16.1

# -----------------------------------------------------------------------------
# Modulo
# -----------------------------------------------------------------------------
set_module_property DESCRIPTION "Tiene el FIR pasa-bajos, ganancia y tiempo/7 segmentos del reproductor de audio"
set_module_property NAME audio_dsp
set_module_property VERSION 1.0
set_module_property INTERNAL false
set_module_property OPAQUE_ADDRESS_MAP true
set_module_property GROUP "Proyecto 2"
set_module_property AUTHOR "Grupo 2 - Sistemas Empotrados CE1113 - 2S2026"
set_module_property DISPLAY_NAME audio_dsp
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property REPORT_TO_TALKBACK false
set_module_property ALLOW_GREYBOX_GENERATION false
set_module_property REPORT_HIERARCHY false

# -----------------------------------------------------------------------------
# Archivos (rutas relativas a esta carpeta)
# -----------------------------------------------------------------------------
add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL audio_dsp
set_fileset_property QUARTUS_SYNTH ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property QUARTUS_SYNTH ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file audio_dsp.v VERILOG PATH audio_dsp.v TOP_LEVEL_FILE
add_fileset_file fir_pbajo.v VERILOG PATH fir_pbajo.v
add_fileset_file ganancia.v  VERILOG PATH ganancia.v
add_fileset_file time_7seg.v VERILOG PATH time_7seg.v

add_fileset SIM_VERILOG SIM_VERILOG "" ""
set_fileset_property SIM_VERILOG TOP_LEVEL audio_dsp
set_fileset_property SIM_VERILOG ENABLE_RELATIVE_INCLUDE_PATHS false
set_fileset_property SIM_VERILOG ENABLE_FILE_OVERWRITE_MODE false
add_fileset_file audio_dsp.v VERILOG PATH audio_dsp.v
add_fileset_file fir_pbajo.v VERILOG PATH fir_pbajo.v
add_fileset_file ganancia.v  VERILOG PATH ganancia.v
add_fileset_file time_7seg.v VERILOG PATH time_7seg.v

# -----------------------------------------------------------------------------
# clock
# -----------------------------------------------------------------------------
add_interface clock clock end
set_interface_property clock clockRate 0
set_interface_property clock ENABLED true
add_interface_port clock clk clk Input 1

# -----------------------------------------------------------------------------
# reset (activo en alto, asociado a clock)
# -----------------------------------------------------------------------------
add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
set_interface_property reset ENABLED true
add_interface_port reset rst reset Input 1

# -----------------------------------------------------------------------------
# avalon_slave
# -----------------------------------------------------------------------------
add_interface avalon_slave avalon end
set_interface_property avalon_slave addressUnits WORDS
set_interface_property avalon_slave associatedClock clock
set_interface_property avalon_slave associatedReset reset
set_interface_property avalon_slave bitsPerSymbol 8
set_interface_property avalon_slave burstOnBurstBoundariesOnly false
set_interface_property avalon_slave burstcountUnits WORDS
set_interface_property avalon_slave explicitAddressSpan 0
set_interface_property avalon_slave holdTime 0
set_interface_property avalon_slave linewrapBursts false
set_interface_property avalon_slave maximumPendingReadTransactions 0
set_interface_property avalon_slave maximumPendingWriteTransactions 0
set_interface_property avalon_slave readLatency 0
set_interface_property avalon_slave readWaitTime 1
set_interface_property avalon_slave setupTime 0
set_interface_property avalon_slave timingUnits Cycles
set_interface_property avalon_slave writeWaitTime 0
set_interface_property avalon_slave ENABLED true

add_interface_port avalon_slave avs_address     address     Input  6
add_interface_port avalon_slave avs_read        read        Input  1
add_interface_port avalon_slave avs_readdata    readdata    Output 32
add_interface_port avalon_slave avs_write       write       Input  1
add_interface_port avalon_slave avs_writedata   writedata   Input  32
add_interface_port avalon_slave avs_waitrequest waitrequest Output 1
set_interface_assignment avalon_slave embeddedsw.configuration.isFlash 0
set_interface_assignment avalon_slave embeddedsw.configuration.isMemoryDevice 0
set_interface_assignment avalon_slave embeddedsw.configuration.isNonVolatileStorage 0
set_interface_assignment avalon_slave embeddedsw.configuration.isPrintableDevice 0

# -----------------------------------------------------------------------------
# hex (conduit): exportar y conectar a HEX0..HEX5 en el top-level
# -----------------------------------------------------------------------------
add_interface hex conduit end
set_interface_property hex associatedClock ""
set_interface_property hex associatedReset ""
set_interface_property hex ENABLED true
add_interface_port hex hex0 hex0 Output 7
add_interface_port hex hex1 hex1 Output 7
add_interface_port hex hex2 hex2 Output 7
add_interface_port hex hex3 hex3 Output 7
add_interface_port hex hex4 hex4 Output 7
add_interface_port hex hex5 hex5 Output 7

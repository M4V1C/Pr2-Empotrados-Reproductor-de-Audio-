// ===============================================================================================================
//       ~~~~~ Tiempo de reproduccion MM:SS y displays de 7 segmentos (submodulo de audio_dsp) ~~~~~
//
// ESTADO: ESQUELETO. La interfaz (puertos) es DEFINITIVA y ya esta conectada dentro de audio_dsp.v
// Falta implementar el cuerpo (ver "QUE HAY QUE HACER"). Mientras tanto tenemos: TIME = 00:00 y displays apagados
//
// Manejo directo de los display 7 segmentos (HW) con la visualizacion del tiempo de reproduccion (MM:SS).
//
// Resumen de las señales:
// ---------------------------------------------------------------------------------------
// ENTRADAS (todas sincronas con clk, mismo dominio de reloj que audio_dsp):
//
//   clk       reloj del sistema (50 MHz)
//   rst       reset sincrono activo en ALTO -> tiempo 00:00
//   tick_par  pulso de 1 ciclo por cada par de muestras reproducido.
//             audio_dsp ya lo filtra con CTRL.TIME_EN: en pausa no llegan pulsos.
//             Pueden llegar seguidos (cada 2-3 ciclos): hay que contar TODOS.
//   fs        pares por segundo de la cancion actual: 8000, 16000 o 44100
//             (registro FS). Cambia solo al cargar una cancion.
//   time_clr  pulso de 1 ciclo: tiempo a 00:00 y preescalador a 0
//             (CTRL.TIME_CLR, al cambiar de cancion).
//   hex_en    1 = displays encendidos, 0 = todos apagados (CTRL.HEX_EN)
//   track     numero de cancion 0..99 para HEX5..HEX4 (registro TRACK)
//
// SALIDAS:
//
//   time_mmss [5:0] segundos 0..59, [14:8] minutos 0..99, en BINARIO,
//             [7:6] = 0. Se lee en el registro TIME (0x1C).
//   hex0..hex5 segmentos ACTIVOS EN BAJO, bit 0 = a ... bit 6 = g (DE1-SoC):
//             HEX1..HEX0 = segundos, HEX3..HEX2 = minutos, HEX5..HEX4 = numero de cancion
// ----------------------------------------------------------------------------------------
//===============================================================================================================

//######################### de acá en adelante BORRAR COMENTARIOS cuando esté completo el módulo ###########################
//
// Seguir los pasos del: hw/ip/audio_dsp/README.md, seccion 7 "Guia para time_7seg".
//
// QUE HAY QUE HACER 
//   1. Preescalador: contar tick_par; al llegar a fs pares -> +1 segundo
//   2. Segundos 0..59 y minutos 0..99 (en 99:59 se queda fijo)
//   3. time_clr y rst -> 00:00 y preescalador en 0
//   4. Separar MM, SS y track en decenas y unidades, y decodificar a 7 segmentos
//   5. hex_en = 0 -> todos los segmentos apagados (7'h7F)
//   6. Testbench propio (sim/tb_time_7seg.sv) con un fs pequeno (ej. 4)
//   NO cambiar los nombres ni anchos de los puertos sin avisar: audio_dsp.v, el registro TIME y el software del Nios dependen de ellos

`timescale 1ns/1ps

module time_7seg (
    input wire clk,
    input wire rst,
    input wire tick_par,
    input wire time_clr,
    input wire hex_en,
    input wire [16:0] fs,
    input wire [6:0] track,
    output wire [14:0] time_mmss,
    output wire [6:0]  hex0,
    output wire [6:0]  hex1,
    output wire [6:0]  hex2,
    output wire [6:0]  hex3,
    output wire [6:0]  hex4,
    output wire [6:0]  hex5
);
    // ------------------------------------------------------------------
    // PENDIENTE: implementar (borrar estas asignaciones provisionales)
    // ------------------------------------------------------------------
    assign time_mmss = 15'd0;   // 00:00
    assign hex0 = 7'h7F;        // apagados (activos en bajo)
    assign hex1 = 7'h7F;
    assign hex2 = 7'h7F;
    assign hex3 = 7'h7F;
    assign hex4 = 7'h7F;
    assign hex5 = 7'h7F;

endmodule

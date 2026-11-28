// ===============================================================================================================
//       ~~~~~ Tiempo de reproduccion MM:SS y displays de 7 segmentos (submodulo de audio_dsp) ~~~~~
//
// Manejo directo de los display 7 segmentos (HW) con la visualizacion del tiempo de reproduccion (MM:SS) y el numero de
// cancion. El tiempo se cuenta con las MUESTRAS reproducidas (no con un timer), asi queda sincronizado con el
// audio: en pausa el Nios no escribe muestras, no llegan pulsos y el tiempo se congela solo.
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
//             (registro FS). fs = 0 no es valido y el tiempo no avanza
//   time_clr  pulso de 1 ciclo: tiempo a 00:00 y preescalador a 0
//             (CTRL.TIME_CLR, al cambiar de cancion). Gana sobre tick_par.
//   hex_en    1 = displays encendidos, 0 = todos apagados (CTRL.HEX_EN). el tiempo sigue contando aunque esten apagados.
//   track     numero de cancion 0-99 para HEX5..HEX4 (registro TRACK). 100-127 no son validos y se muestra "--".
//
// SALIDAS:
//
//   time_mmss [5:0] segundos 0..59, [14:8] minutos 0..99, en BINARIO,
//             [7:6] = 0. Se lee en el registro TIME (0x1C).
//   hex0..hex5 segmentos ACTIVOS EN BAJO, bit 0 = a ... bit 6 = g (DE1-SoC):
//             HEX1..HEX0 = segundos, HEX3..HEX2 = minutos, HEX5..HEX4 = numero de cancion
//
// Funcionamiento del tiempo y displays:
//                                         
//  tick_par -> preescalador (0 .. fs-1) -> seg_u(0-9) -> seg_d(0-5) -> min_u(0-9) -> min_d(0-9)
//  Al contar fs pulsos suma 1 segundo, se compara el preescalador con fs - 1
//  Los contadores son BCD lo cual ayuda a no tener que convertir binario a decimal sino que cada uno ya es un digito
//  Para el registro TIME se pasa de BCD a binario con sumas y desplazamientos como: x * 10 = (x << 3) + (x << 1)
//  En 99:59 se queda fijo (no vuelve a 00:00). En este caso el preescalador sigue pero ya no suma segundos. Pero una canción es muy extraño que dure 99 minutos digamos.
//  El numero de cancion (binario 0-99) se separa en decenas y unidades con comparaciones.
//  Latencia: time_mmss cambia en el mismo flanco que recibe el pulso, los displays cambian un ciclo despues.
// ===============================================================================================================

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
    // Segmentos (activos en bajo, bit 0 = a - bit 6 = g)
    // ------------------------------------------------------------------
    localparam [6:0] SEG_OFF   = 7'h7F; // todos apagados
    localparam [6:0] SEG_GUION = 7'h3F; // solo g: "-"
    localparam [3:0] DIG_GUION = 4'hF;  // digito que no es 0..9 -> guion

    function [6:0] dig7;
        input [3:0] d;
        case (d)
            4'd0: dig7 = 7'h40;
            4'd1: dig7 = 7'h79;
            4'd2: dig7 = 7'h24;
            4'd3: dig7 = 7'h30;
            4'd4: dig7 = 7'h19;
            4'd5: dig7 = 7'h12;
            4'd6: dig7 = 7'h02;
            4'd7: dig7 = 7'h78;
            4'd8: dig7 = 7'h00;
            4'd9: dig7 = 7'h10;
            default: dig7 = SEG_GUION;
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Preescalador y contadores BCD del tiempo
    // ------------------------------------------------------------------
    reg [16:0] presc; // pares contados dentro del segundo en el que estamos (0..fs-1)
    reg [3:0]  seg_u; // unidades de segundos (0-9)
    reg [2:0]  seg_d; // decenas de segundos (0-5)
    reg [3:0]  min_u; //unidades de minutos (0-9)
    reg [3:0]  min_d; //decenas de minutos (0-9)

    wire fs_ok   = (fs != 17'd0);
    wire fin_seg = (presc >= fs - 17'd1); //para completar un seg
    wire tope    = (min_d == 4'd9) && (min_u == 4'd9) && (seg_d == 3'd5) && (seg_u == 4'd9); // 99:59

    always @(posedge clk) begin
        if (rst || time_clr) begin
            presc <= 17'd0;
            seg_u <= 4'd0;
            seg_d <= 3'd0;
            min_u <= 4'd0;
            min_d <= 4'd0;
        end else if (tick_par && fs_ok) begin
            if (!fin_seg) begin
                presc <= presc + 17'd1;
            end else begin
                presc <= 17'd0;
                if (!tope) begin
                    // suma 1 segundo con acarreo BCD. 59s es 1 min y 9 marca decena siguiente
                    if (seg_u != 4'd9) begin
                        seg_u <= seg_u + 4'd1;
                    end else begin
                        seg_u <= 4'd0;
                        if (seg_d != 3'd5) begin
                            seg_d <= seg_d + 3'd1;
                        end else begin
                            seg_d <= 3'd0;
                            if (min_u != 4'd9) begin
                                min_u <= min_u + 4'd1;
                            end else begin
                                min_u <= 4'd0;
                                min_d <= min_d + 4'd1; //no pasa de 9 por el tope
                            end
                        end
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Registro TIME en binario =  decenas * 10 + unidades
    // ------------------------------------------------------------------
    wire [5:0] seg_bin = {seg_d, 3'b000} + {2'b00, seg_d, 1'b0} + {2'b00, seg_u};
    wire [6:0] min_bin = {min_d, 3'b000} + {2'b00, min_d, 1'b0} + {3'b000, min_u};
    assign time_mmss = {min_bin, 2'b00, seg_bin};

    // ------------------------------------------------------------------
    // Numero de cancion  0-99
    // ------------------------------------------------------------------
    reg [3:0] trk_d, trk_u;
    reg [6:0] trk_resto; // track - decenas * 10
    always @(*) begin
        if(track >= 7'd100) trk_d = DIG_GUION;
        else if (track >= 7'd90)  trk_d = 4'd9;
        else if (track >= 7'd80)  trk_d = 4'd8;
        else if (track >= 7'd70)  trk_d = 4'd7;
        else if (track >= 7'd60)  trk_d = 4'd6;
        else if (track >= 7'd50)  trk_d = 4'd5;
        else if (track >= 7'd40)  trk_d = 4'd4;
        else if (track >= 7'd30)  trk_d = 4'd3;
        else if (track >= 7'd20)  trk_d = 4'd2;
        else if (track >= 7'd10)  trk_d = 4'd1;
        else                      trk_d = 4'd0;

        trk_resto = track - ({trk_d, 3'b000} + {2'b00, trk_d, 1'b0});
        trk_u = (track >= 7'd100) ? DIG_GUION : trk_resto[3:0];
    end

    // -----------
    // Displays
    // -----------
    reg [6:0] hex0_q, hex1_q, hex2_q, hex3_q, hex4_q, hex5_q;

    always @(posedge clk) begin
        if (rst || !hex_en) begin
            hex0_q <= SEG_OFF;
            hex1_q <= SEG_OFF;
            hex2_q <= SEG_OFF;
            hex3_q <= SEG_OFF;
            hex4_q <= SEG_OFF;
            hex5_q <= SEG_OFF;
        end else begin
            hex0_q <= dig7(seg_u);
            hex1_q <= dig7({1'b0, seg_d});
            hex2_q <= dig7(min_u);
            hex3_q <= dig7(min_d);
            hex4_q <= dig7(trk_u);
            hex5_q <= dig7(trk_d);
        end
    end

    assign hex0 = hex0_q;
    assign hex1 = hex1_q;
    assign hex2 = hex2_q;
    assign hex3 = hex3_q;
    assign hex4 = hex4_q;
    assign hex5 = hex5_q;

endmodule

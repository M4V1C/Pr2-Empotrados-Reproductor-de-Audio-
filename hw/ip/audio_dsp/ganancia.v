// ===================================================================================================
//                   ~~~~~ Escalamiento digital del volumen / Potenciómetro ~~~~~
//
// Control de volumen "mediante escalamiento digital en HW (multiplicador antes de la IP de audio)
//
// Para cada canal (combinacional, 2 multiplicadores = 2 bloques DSP):
//     y = sat16( (x * gain) >>> 12 )
//
//   x    : muestra int16 con signo (Q1.15)
//   gain : ganancia sin signo Q1.12 de 13 bits (0..8191) Se vería así:
//          4096 = x1.0   2048 = x0.5   0 = silencio   8191 = ~x2.0
//   >>>  : desplazamiento ARITMETICO (redondea hacia abajo)
//   sat  : 1 si L o R se salieron de int16 y se saturaron
//
// Con gain = 4096 la salida es exactamente igual a la entrada.
// En el sistema, Nios escribe GAIN desde tabla logarítmica del potenciómetro (ADC), valores [0,4096]
// =====================================================================================================
`timescale 1ns/1ps

module ganancia (
    input wire [31:0] x_lr,  // par de entrada:  [15:0] = L, [31:16] = R
    input wire [12:0] gain,  // ganancia Q1.12
    output wire [31:0] y_lr, // par de salida:   [15:0] = L, [31:16] = R
    output wire sat          // 1 si L o R saturaron
);
    wire signed [15:0] x_l = x_lr[15:0];
    wire signed [15:0] x_r = x_lr[31:16];
    wire signed [13:0] g   = {1'b0, gain}; // con signo, siempre positiva
    //16 x 14 bits con signo -> 30 bits
    wire signed [29:0] prod_l = x_l * g;
    wire signed [29:0] prod_r = x_r * g;
    // >>> 12 (aritmetico). |prod| <= 32768 * 8191 < 2^28 -> cabe en 18 bits
    wire signed [29:0] prod_l_shf = prod_l >>> 12;
    wire signed [29:0] prod_r_shf = prod_r >>> 12;
    wire signed [17:0] shift_l    = prod_l_shf[17:0];
    wire signed [17:0] shift_r    = prod_r_shf[17:0];
    //saturacion a int16
    wire sat_l_pos = (shift_l >  18'sd32767);
    wire sat_l_neg = (shift_l < -18'sd32768);
    wire sat_r_pos = (shift_r >  18'sd32767);
    wire sat_r_neg = (shift_r < -18'sd32768);
    wire signed [15:0] y_l = sat_l_pos ? 16'sh7FFF : sat_l_neg ? 16'sh8000 : shift_l[15:0];
    wire signed [15:0] y_r = sat_r_pos ? 16'sh7FFF : sat_r_neg ? 16'sh8000 : shift_r[15:0];
    assign y_lr = {y_r, y_l};
    assign sat  = sat_l_pos | sat_l_neg | sat_r_pos | sat_r_neg;

endmodule

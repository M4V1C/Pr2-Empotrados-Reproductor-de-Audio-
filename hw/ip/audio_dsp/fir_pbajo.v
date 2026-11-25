// ==========================================================================================================
//                       ~~~~~ Filtro pasa-baja FIR (issue F-02 en repo) ~~~~~~
//
// Bloque DSP descrito en HDL por el grupo (registros, multiplicador-acumulador y control de coeficientes)
//
// Arquitectura: 1 multiplicador-acumulador (MAC) que recorre los N_TAPS coeficientes, primero para el 
// canal L y luego para el R. Usando:
//
//   y[n] = sat16((sum_{k=0}^{N-1} h[k] * x[n-k] + 2^14) >>> 15)
//
// - Muestras y coeficientes: int16 con signo (Q1.15)
// - Acumulador de 37 bits: 32 productos de 32 bits sin desbordar
// - Redondeo al mas cercano (+2^14) y desplazamiento ARITMETICO (>>>)
// - Saturacion a int16; 'sat' indica si L o R saturo en el par procesado
// - Tiene el comportamiento de model_fir() de tools/gen_coefs.py (bit-exact), para su testeo
//
// Temporizacion (N_TAPS = 32): 
// 67 flancos desde que se acepta 'start' hasta que 'done' valga 1 = 1 carga + (32 MAC + 1 redondeo) x 2canales
// =============================================================================================================
`timescale 1ns/1ps

module fir_pbajo #(
    parameter N_TAPS = 32,
    parameter AW = 5    // log2(N_TAPS)
)(
    input wire clk,
    input wire rst,    // reset sincrono, activo en alto

    // --- Las muestras ---
    input wire start,    // pulso: procesar un par L/R (solo en reposo)
    input wire signed [15:0] x_l,
    input wire signed [15:0] x_r,
    output reg signed [15:0] y_l,
    output reg signed [15:0] y_r,
    output wire busy,    // mantiene 1 mientras procesa
    output reg done,     // pulso de 1 ciclo: y_l/y_r/sat validos
    output reg sat,      // tiene 1 si L o R saturaron en este par
    input wire hist_clr, // borra el historial (solo en reposo)

    // --- Los coeficientes ---
    input wire coef_we,
    input wire [AW-1:0] coef_addr,
    input wire signed [15:0] coef_wdata,
    output wire signed [15:0] coef_rdata
);

    // ==================================================================
    // ~~~ Estados ~~~
    // ==================================================================
    localparam [1:0] S_IDLE = 2'd0,
                     S_MAC = 2'd1,
                     S_RND = 2'd2;
    reg [1:0] state;

    // =============================================================
    // ~~~ Almacenamiento ~~~
    // =============================================================
    reg signed [15:0] coef [0:N_TAPS-1];   // h[k]
    reg signed [15:0] hist_l [0:N_TAPS-1]; // hist_l[k] = x_l[n-k]
    reg signed [15:0] hist_r [0:N_TAPS-1]; // hist_r[k] = x_r[n-k]
    reg [AW-1:0] k;           // indice del tap
    reg channel;              // 0 = L, 1 = R
    reg signed [36:0] acc;    // acumulador de 37 bits
    integer i;   // indice de lazos de la maquina de estados
    integer j;   // indice del bloque inicial
    // Valores de arranque (simulacion y power-up del FPGA)
    initial begin
        for (j = 0; j < N_TAPS; j = j + 1)
            coef[j] = 16'sd0;
    end

    // ========================================================================================
    // ~~~ Datapath combinacional: multiplicador, redondeo y saturacion ~~~ 
    // ========================================================================================
    wire signed [15:0] c_sel = coef[k];
    wire signed [15:0] h_sel = channel ? hist_r[k] : hist_l[k];
    wire signed [31:0] producto = c_sel * h_sel;
    wire signed [36:0] acc_rnd = acc + 37'sd16384;       // + 2^14
    wire signed [36:0] acc_shift_full = acc_rnd >>> 15;  // aritmetico
    wire signed [21:0] acc_shift = acc_shift_full[21:0]; // |acc| <= 2^35 -> cabe en 22 bits
    wire ovf_pos = (acc_shift >  22'sd32767);
    wire ovf_neg = (acc_shift < -22'sd32768);
    wire signed [15:0] y_sat = ovf_pos ? 16'sh7FFF :
                               ovf_neg ? 16'sh8000 :
                                         acc_shift[15:0];
    assign busy       = (state != S_IDLE);
    assign coef_rdata = coef[coef_addr];

    // ============================================================
    // ~~~ Escritura de coeficientes (escribe solo en reposo) ~~~ 
    // ============================================================
    always @(posedge clk) begin
        if (coef_we)
            coef[coef_addr] <= coef_wdata;
    end

    // ==============================================================================
    // ~~~ Maquina de estados ~~~ 
    // ==============================================================================
    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            state <= S_IDLE;
            k     <= {AW{1'b0}};
            channel <= 1'b0;
            acc   <= 37'sd0;
            y_l   <= 16'sd0;
            y_r   <= 16'sd0;
            sat   <= 1'b0;
            for (i = 0; i < N_TAPS; i = i + 1) begin
                hist_l[i] <= 16'sd0;
                hist_r[i] <= 16'sd0;
            end
        end else begin
            case (state)
                // ------------------------Estado: IDLE----------------------------
                S_IDLE: begin
                    if (hist_clr) begin
                        for (i = 0; i < N_TAPS; i = i + 1) begin
                            hist_l[i] <= 16'sd0;
                            hist_r[i] <= 16'sd0;
                        end
                    end else if (start) begin
                        // desplaza el historial e inserta la muestra nueva
                        hist_l[0] <= x_l;
                        hist_r[0] <= x_r;
                        for (i = 1; i < N_TAPS; i = i + 1) begin
                            hist_l[i] <= hist_l[i-1];
                            hist_r[i] <= hist_r[i-1];
                        end
                        k     <= {AW{1'b0}};
                        channel <= 1'b0;
                        acc   <= 37'sd0;
                        sat   <= 1'b0;
                        state <= S_MAC;
                    end
                end
                // ------------------Estado: MAC-------------------
                S_MAC: begin
                    acc <= acc + producto;
                    if (k == N_TAPS - 1)
                        state <= S_RND;
                    else
                        k <= k + 1'b1;
                end
                // --------------------Estado: RND-----------------------
                S_RND: begin
                    if (ovf_pos || ovf_neg)
                        sat <= 1'b1;
                    if (channel == 1'b0) begin // termina L -> sigue R
                        y_l   <= y_sat;
                        channel <= 1'b1;
                        k     <= {AW{1'b0}};
                        acc   <= 37'sd0;
                        state <= S_MAC;
                    end else begin  // termina R -> listo
                        y_r   <= y_sat;
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                // -----------------------------------------------------
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

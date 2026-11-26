// ====================================================================================================================
//                  ~~~~~ Modulo HW personalizado del reproductor (issue F-03 del repo) ~~~~~
//
// Es el modulo de hardware personalizado con registros de control, estado y datos, accesible mediante mapeo a memoria
//
// Periferico Avalon-MM (esclavo) que ve el Nios V. Este tiene:
//   * bypass: con CTRL.FIR_EN = 0 muestra pasa sin filtrar
//   * fir_pbajo: filtro pasa-bajos FIR (fir_pbajo.v)
//   * ganancia: volumen / potenciómetro (ganancia.v)
//   * time_7seg: tiempo MM:SS y 7segmentos (time_7seg.v) PENDIENTE: el cuerpo; ahora en 00:00 y apagado
//
// -----------------------------------------------------------------------------
// Interfaces para el Plataform Designer
// ----------------------------------------------------------------------------
//  Puerto            Dir   Ancho  Interfaz       Tipo de señal
//  clk               in    1      clock          clk
//  rst               in    1      reset          reset (activo en ALTO)
//  avs_address       in    6      avalon_slave   address (por PALABRA)
//  avs_read          in    1      avalon_slave   read
//  avs_readdata      out   32     avalon_slave   readdata
//  avs_write         in    1      avalon_slave   write
//  avs_writedata     in    32     avalon_slave   writedata
//  avs_waitrequest   out   1      avalon_slave   waitrequest
//  hex0 .. hex5      out   7 c/u  conduit "hex"  (exportar al top-level)
//
//  avalon_slave: 32 bits de datos, direccionamiento por palabra (64 palabras = 256 bytes de espacio), 
//  latencia de lectura 0, con waitrequest. 
//  No usa byteenable: el Nios siempre accede a palabras completas de 32 bits
//
// -------------------------------------------------------------------------------------------------------------
// Mapa de registros (offset en BYTES desde la base) (avs_address = offset/4)
// -------------------------------------------------------------------------------------------------------------
//  0x00      ID           RO   [31:0] 0x41554431 ("AUD1")
//  0x04      CTRL         RW   [0] FIR_EN 1 = pasa-bajos FIR, 0 = bypass
//                              [1] HIST_CLR escribir 1 borra el historial del FIR (se lee 0)
//                              [2] TIME_EN 1 = el tiempo avanza con cada par
//                              [3] TIME_CLR escribir 1 pone el tiempo y FRAME_CNT en 0 (se lee 0)
//                              [4] HEX_EN 1 = displays encendidos
//  0x08      STATUS       RO   [0] BUSY 1 mientras el FIR procesa (y el ciclo en que termina)
//                         W1C  [1] SAT 1 si alguna salida saturo desde la ultima vez que se borro; escribir 1 lo borra
//  0x0C      SAMPLE_IN    WO   [15:0] L, [31:16] R (int16). Escribir procesa un par (Ambos L/R)
//  0x10      SAMPLE_OUT   RO   [15:0] L, [31:16] R. waitrequest mientras BUSY
//  0x14      GAIN         RW   [12:0] Q1.12 (4096 = x1.0). Valor de reset 4096
//  0x18      FS           RW   [16:0] pares por segundo (8000, 16000, 44100)
//  0x1C      TIME         RO   [5:0] segundos, [14:8] minutos (de time_7seg)
//  0x20      TRACK        RW   [6:0] numero de cancion para HEX5..HEX4
//  0x24      FRAME_CNT    RO   [31:0] pares escritos desde el ultimo TIME_CLR
//  0x80-0xFC COEF[k]      RW   [15:0] coeficiente k del FIR (Q1.15); se lee con extension de signo a 32 bits
//
// ----------------------------------------------------------------------------------------------------------
// Temporización Y waitrequest
// -----------------------------------------------------------------------------------------------------------
//  * Con FIR_EN = 1, escribir SAMPLE_IN arranca fir_pbajo (dura 67 ciclos).
//    Leer SAMPLE_OUT en ese tiempo detiene al Nios (waitrequest) hasta que el resultado esta listo: 
//    el software solo escribe y lee, sin polling.
//  * Con FIR_EN = 0 (bypass), SAMPLE_OUT esta listo al ciclo siguiente, sin espera (FIR no arranca)
//  * waitrequest = BUSY y (cualquier escritura, o lectura de SAMPLE_OUT), con BUSY = fir_pbajo procesando o 
//    terminando (hasta que SAMPLE_OUT se carga). Así nunca se agarra un cálculo a medias
//    Leer ID, STATUS, etc. no espera.
// ===========================================================================================================

`timescale 1ns/1ps

module audio_dsp (
    // ~~~ señales ~~~
    // clock: conectar al mismo reloj del Nios (50 MHz).
    input wire clk,
    // reset: activo en ALTO. Conectar al reset del sistema.
    input wire rst,
    // ~~~ avalon_slave: conectar al data_manager del Nios V ~~~
    input wire [5:0] avs_address,
    input wire avs_read,
    input wire avs_write,
    input wire [31:0] avs_writedata,
    output reg [31:0] avs_readdata,
    output wire avs_waitrequest,
    // Conduit "hex" -> exportar en Platform Designer y conectar en el top-level
    // a HEX0..HEX5. Activos en bajo (DE1-SoC). Pines: asignar en .qsf del proyecto
    output wire [6:0]  hex0,
    output wire [6:0]  hex1,
    output wire [6:0]  hex2,
    output wire [6:0]  hex3,
    output wire [6:0]  hex4,
    output wire [6:0]  hex5
);
    // ------------------------------------------------------------------
    // Direcciones de registro (por palabra = offset en bytes/4)
    // ------------------------------------------------------------------
    localparam [5:0] A_ID = 6'd0,         // 0x00
                     A_CTRL = 6'd1,       // 0x04
                     A_STATUS = 6'd2,     // 0x08
                     A_SAMPLE_IN = 6'd3,  // 0x0C
                     A_SAMPLE_OUT = 6'd4, // 0x10
                     A_GAIN = 6'd5,       // 0x14
                     A_FS = 6'd6,         // 0x18
                     A_TIME = 6'd7,       // 0x1C
                     A_TRACK = 6'd8,      // 0x20
                     A_FRAME_CNT = 6'd9,  // 0x24
                     A_COEF0 = 6'd32;     // 0x80 (COEF[k] = A_COEF0 + k)

    localparam [31:0] ID_VALUE = 32'h41554431; // "AUD1"

    // ------------------------------------------------------------------
    // Registros
    // ------------------------------------------------------------------
    reg ctrl_fir_en;         // CTRL[0]
    reg time_en;             // CTRL[2]
    reg hex_en;              // CTRL[4]
    reg sat_general;         // STATUS[1]: saturacion acumulada (W1C)
    reg [12:0] gain_q;       // GAIN
    reg [16:0] fs_q;         // FS
    reg [6:0]  track_q;      // TRACK
    reg [31:0] frame_cnt;    // FRAME_CNT
    reg [31:0] sample_in_q;  // ultimo valor escrito en SAMPLE_IN
    reg [31:0] sample_out_q; // SAMPLE_OUT

    // ------------------------------------------------------------------
    // Conexion con fir_pbajo
    // ------------------------------------------------------------------
    wire fir_busy;
    wire fir_done;
    wire fir_sat;
    wire signed [15:0] fir_y_l, fir_y_r;
    wire signed [15:0] fir_coef_rdata;

    // ------------------------------------------------------------------
    // Deco de accesos (sin waitrequest)
    // ------------------------------------------------------------------
    // ocupado = el FIR calcula, o termino en este ciclo y SAMPLE_OUT todaviano se actualiza 
    // (se carga en el flanco siguiente a fir_done)
    wire ocupado = fir_busy || fir_done;
    assign avs_waitrequest = ocupado && (avs_write || (avs_read && avs_address == A_SAMPLE_OUT));
    wire wr_ok        = avs_write && !avs_waitrequest;
    wire wr_ctrl      = wr_ok && (avs_address == A_CTRL);
    wire wr_sample_in = wr_ok && (avs_address == A_SAMPLE_IN);
    wire wr_coef      = wr_ok && avs_address[5];          // 0x80..0xFC
    wire hist_clr     = wr_ctrl && avs_writedata[1];      // pulso de 1 ciclo
    wire time_clr     = wr_ctrl && avs_writedata[3];      // pulso de 1 ciclo
    wire fir_start    = wr_sample_in && ctrl_fir_en;
    // Pulso por cada par(L/R) escrito (hacia time_7seg)
    wire tick_par     = wr_sample_in && time_en;

    fir_pbajo #(.N_TAPS(32), .AW(5)) u_fir (
        .clk        (clk),
        .rst        (rst),
        .start      (fir_start),
        .x_l        (avs_writedata[15:0]),
        .x_r        (avs_writedata[31:16]),
        .y_l        (fir_y_l),
        .y_r        (fir_y_r),
        .busy       (fir_busy),
        .done       (fir_done),
        .sat        (fir_sat),
        .hist_clr   (hist_clr),
        .coef_we    (wr_coef),
        .coef_addr  (avs_address[4:0]),
        .coef_wdata (avs_writedata[15:0]),
        .coef_rdata (fir_coef_rdata)
    );
    // ------------------------------------------------------------------
    // Camino de muestra: FIR o bypass -> ganancia -> SAMPLE_OUT
    // ------------------------------------------------------------------
    // Valor que se carga en SAMPLE_OUT:
    //   - FIR_EN = 1: el resultado del FIR cuando termina (fir_done)
    //   - FIR_EN = 0: la muestra escrita, en el mismo ciclo (bypass)
    wire load_out = fir_done || (wr_sample_in && !ctrl_fir_en);
    wire [31:0] sel_sample_out = fir_done ? {fir_y_r, fir_y_l} : avs_writedata;

    // Ganancia (volumen): y = sat16((x * GAIN) >>> 12) por canal, GAIN en Q1.12
    // Con GAIN = 4096 (valor de reset) la muestra pasa directa sin cambios
    wire [31:0] sample_gain;
    wire gain_sat;

    ganancia u_gain (
        .x_lr (sel_sample_out),
        .gain (gain_q),
        .y_lr (sample_gain),
        .sat  (gain_sat)
    );

    // ------------------------------------------------------------------
    // Escritura de registros
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            ctrl_fir_en  <= 1'b0;
            time_en      <= 1'b0;
            hex_en       <= 1'b0;
            sat_general  <= 1'b0;
            gain_q       <= 13'd4096;   // x1.0
            fs_q         <= 17'd44100;
            track_q      <= 7'd0;
            frame_cnt    <= 32'd0;
            sample_in_q  <= 32'd0;
            sample_out_q <= 32'd0;
        end else begin
            // ~~~ registros de config ~~~
            if (wr_ctrl) begin
                ctrl_fir_en <= avs_writedata[0];
                time_en     <= avs_writedata[2];
                hex_en      <= avs_writedata[4];
            end
            if (wr_ok && avs_address == A_GAIN)  gain_q  <= avs_writedata[12:0];
            if (wr_ok && avs_address == A_FS)    fs_q    <= avs_writedata[16:0];
            if (wr_ok && avs_address == A_TRACK) track_q <= avs_writedata[6:0];
            // ~~~ muestras ~~~
            if (wr_sample_in) sample_in_q  <= avs_writedata;
            if (load_out)     sample_out_q <= sample_gain;
            // ~~~ contador de pares ~~~
            if (time_clr)          frame_cnt <= 32'd0;
            else if (wr_sample_in) frame_cnt <= frame_cnt + 32'd1;
            // ~~~ saturacion acumulada (write 1 to clear[W1C]) ~~~
            if ((fir_done && fir_sat) || (load_out && gain_sat))
                sat_general <= 1'b1;
            else if (wr_ok && avs_address == A_STATUS && avs_writedata[1])
                sat_general <= 1'b0;
        end
    end

    // ----------------------------------------------------------------------------------------------
    // Tiempo MM:SS y displays de 7 segmentos (time_7seg.v)
    // ~~~ OJO ~~~ PENDIENTE: implementar el resto de time_7seg.v
    //     Esta instancia ya está para los demás archivos entonces la idea es no cambiarlos acá
    //     Revisar el README.md, seccion 7
    // ----------------------------------------------------------------------------------------------
    wire [14:0] time_mmss;  // [5:0] segundos, [14:8] minutos -> TIME

    time_7seg u_time (
        .clk       (clk),
        .rst       (rst),
        .tick_par  (tick_par), // 1 pulso por par escrito (si TIME_EN = 1)
        .fs        (fs_q),     // registro FS
        .time_clr  (time_clr), // CTRL.TIME_CLR
        .hex_en    (hex_en),   // CTRL.HEX_EN
        .track     (track_q),  // registro TRACK
        .time_mmss (time_mmss),
        .hex0      (hex0),
        .hex1      (hex1),
        .hex2      (hex2),
        .hex3      (hex3),
        .hex4      (hex4),
        .hex5      (hex5)
    );

    // ------------------------------------------------------------------
    // Lectura de registros (latencia 0)
    // ------------------------------------------------------------------
    always @(*) begin
        if (avs_address[5]) begin
            // COEF[k]: coeficiente con extension de signo
            avs_readdata = {{16{fir_coef_rdata[15]}}, fir_coef_rdata};
        end else begin
            case (avs_address)
                A_ID:         avs_readdata = ID_VALUE;
                A_CTRL:       avs_readdata = {27'd0, hex_en, 1'b0, time_en, 1'b0, ctrl_fir_en};
                A_STATUS:     avs_readdata = {30'd0, sat_general, ocupado};
                A_SAMPLE_IN:  avs_readdata = sample_in_q; // solo para depuracion
                A_SAMPLE_OUT: avs_readdata = sample_out_q;
                A_GAIN:       avs_readdata = {19'd0, gain_q};
                A_FS:         avs_readdata = {15'd0, fs_q};
                A_TIME:       avs_readdata = {17'd0, time_mmss};
                A_TRACK:      avs_readdata = {25'd0, track_q};
                A_FRAME_CNT:  avs_readdata = frame_cnt;
                default:      avs_readdata = 32'd0; // reservado
            endcase
        end
    end

endmodule

// =====================================================================================================
//                    ~~~~~ Verificacion de audio_dsp por el bus Avalon ~~~~~
//
// Verificacion aislada del modulo propio ANTES de integrar. Todo se hace por el bus Avalon, 
// como lo veria el Nios, y se compara contra los vectores del modelo de referencia (tools/gen_coefs.py)
//
//   TC1:  ID
//   TC2:  bypass (FIR_EN = 0): SAMPLE_OUT = SAMPLE_IN, sin waitrequest
//   TC3:  respuesta al impulso = COEF, y relectura de COEF (8, 16 y 44.1 kHz)
//   TC4:  escalon, seno en banda de paso y de rechazo contra el modelo (3 fs)
//   TC5:  ruido aleatorio, 2000 pares bit a bit (3 fs)
//   TC6:  saturacion: STATUS.SAT se enciende, se queda (general) y W1C la borra
//   TC7:  HIST_CLR y recarga de coeficientes (y sin HIST_CLR el resultado cambia)
//   TC8:  waitrequest: 
//             (a) SAMPLE_OUT nunca devuelve un dato viejo, leyendo 0..70 ciclos despues de escribir
//             (b) STATUS.BUSY se lee sin espera
//             (c) escribir SAMPLE_IN o COEF durante el calculo espera y no sobreescribe nada
//   TC9:  GAIN sobre el FIR (x0.5, silencio, x1) y saturacion por ganancia
//   TC10: FRAME_CNT y TIME_CLR; TIME (MM:SS) con un FS pequeño.
//         Mientras time_7seg todavia falta (TIME siempre 00:00), TIME se marca [PEND] en lugar de [FAIL]
//
// Correr con:  sim/run_audio_dsp.sh
// ========================================================================================================
`timescale 1ns/1ps

module tb_audio_dsp;
    localparam string VEC_DIR = "vectors";
    localparam int MAX_REPORT = 10; // errores impresos por vector
    localparam int FS_PRUEBA = 4; // FS pequeno para TC10 (4 pares = 1s)
    // direcciones por palabra (offset en bytes/4)
    localparam logic [5:0] A_ID = 0, 
                           A_CTRL = 1, 
                           A_STATUS = 2, 
                           A_SAMPLE_IN = 3,
                           A_SAMPLE_OUT = 4, 
                           A_GAIN = 5, 
                           A_FS = 6, 
                           A_TIME = 7,
                           A_TRACK = 8, 
                           A_FRAME_CNT = 9, 
                           A_COEF0 = 32;
    // bits de CTRL
    localparam logic [31:0] FIR_EN = 32'h01, 
                            HIST_CLR = 32'h02, 
                            TIME_EN = 32'h04,
                            TIME_CLR = 32'h08, 
                            HEX_EN = 32'h10;
    //--- reloj de 50 MHz y reset ---
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #10 clk = ~clk;
    // -------------- bus Avalon ---------------
    logic [5:0] avs_address = '0;
    logic avs_read = 1'b0;
    logic avs_write = 1'b0;
    logic [31:0] avs_writedata = '0;
    wire [31:0] avs_readdata;
    wire avs_waitrequest;
    wire [6:0] hex0, hex1, hex2, hex3, hex4, hex5;
    audio_dsp dut (.*);
    int errores = 0;
    int max_wait = 0; // ciclos max de waitrequest observados
    int casos_pendientes = 0; // casos [PEND] (aun faltan)
    string resumen[$]; // 1 linea por caso, para resumen final
    int fs_list[3] = '{8000, 16000, 44100};
    logic [15:0] coef_mem [0:31];

    // ------------------------------------------------------------------------
    // Movimiento en Avalon (como lo haría el Nios): respetando el waitrequest
    // ------------------------------------------------------------------------
    task automatic avs_wr_w(input logic [5:0] a, input logic [31:0] d, output int w);
        w = 0;
        @(negedge clk);
        avs_address = a; avs_writedata = d; avs_write = 1'b1;
        #1;
        while (avs_waitrequest) begin @(negedge clk); #1; w++; end
        @(posedge clk); #1;
        avs_write = 1'b0;
        if (w > max_wait) max_wait = w;
    endtask

    task automatic avs_wr(input logic [5:0] a, input logic [31:0] d);
        int w;
        avs_wr_w(a, d, w);
    endtask

    task automatic avs_rd(input logic [5:0] a, output logic [31:0] d, output int w);
        w = 0;
        @(negedge clk);
        avs_address = a; avs_read = 1'b1;
        #1;
        while (avs_waitrequest) begin @(negedge clk); #1; w++; end
        d = avs_readdata;
        @(posedge clk); #1;
        avs_read = 1'b0;
        if (w > max_wait) max_wait = w;
    endtask

    // Deja pasar n ciclos sin acceder al bus
    task automatic esperar_ciclos(input int n);
        repeat (n) @(negedge clk);
    endtask

    task automatic check(input string nombre, input logic [31:0] leido, input logic [31:0] esperado);
        if (leido !== esperado) begin
            $display("  [ERROR] %s: leido=%h esperado=%h", nombre, leido, esperado);
            errores++;
        end
    endtask

    // Imprime el [PASS] / [FAIL] / [PEND] y lo guarda para el resumen final
    task automatic reporte_caso(input string nombre, input int err_antes, input bit pendiente = 1'b0);
        string estado, linea;
        if (pendiente) begin
            estado = "PEND";
            casos_pendientes++;
        end else begin
            estado = (errores == err_antes) ? "PASS" : "FAIL";
        end
        linea = $sformatf("[%s] %s", estado, nombre);
        $display("%s", linea);
        resumen.push_back(linea);
    endtask

    // ------------------------------------------------------------------------
    // Auxiliares, op punto fijo
    // ------------------------------------------------------------------------
    function automatic int sat16(input int v);
        if (v >  32767) return  32767;
        if (v < -32768) return -32768;
        return v;
    endfunction

    // Esperado con ganancia: sat16((x * g) >>> 12) por canal (g = 4096 -> igual)
    function automatic logic [31:0] aplicar_ganancia(input logic [31:0] par, input int g);
        int l, r;
        l = sat16((int'($signed(par[15:0]))  * g) >>> 12);
        r = sat16((int'($signed(par[31:16])) * g) >>> 12);
        return {r[15:0], l[15:0]};
    endfunction

    // ------------------------------------------------------------------------
    // Carga los 32 coeficientes de una fs por el bus y los relee
    // ------------------------------------------------------------------------
    task automatic cargar_coefs(input int fs);
        logic [31:0] d;
        int w;
        $readmemh($sformatf("%s/coefs_%0d.hex", VEC_DIR, fs), coef_mem);
        for (int k = 0; k < 32; k++) avs_wr(A_COEF0 + k, {16'h0, coef_mem[k]});
        for (int k = 0; k < 32; k++) begin
            avs_rd(A_COEF0 + k, d, w);
            check($sformatf("fs=%0d COEF[%0d]", fs, k), d, {{16{coef_mem[k][15]}}, coef_mem[k]});
        end
    endtask

    // ------------------------------------------------------------------------
    // Procesa fir_<fs>_<caso>_in.hex por el bus y compara con _out.hex
    //     g: ganancia aplicada al esperado (4096 = sin cambio)
    //     esperar_coincidencia = 1: cada diferencia es un error
    //     esperar_coincidencia = 0: solo cuenta diferencias (prueba negativa)
    // ------------------------------------------------------------------------
    task automatic correr_vector(input int fs, input string caso, input int g,
                                 input bit esperar_coincidencia,
                                 output int pares, output int difs);
        int fd_in, fd_out, w;
        logic [31:0] w_in, w_exp, leido;
        fd_in  = $fopen($sformatf("%s/fir_%0d_%s_in.hex",  VEC_DIR, fs, caso), "r");
        fd_out = $fopen($sformatf("%s/fir_%0d_%s_out.hex", VEC_DIR, fs, caso), "r");
        if (fd_in == 0 || fd_out == 0)
            $fatal(1, "No se pudo abrir fir_%0d_%s (correr desde sim/)", fs, caso);
        pares = 0;
        difs  = 0;
        while ($fscanf(fd_in, "%h\n", w_in) == 1) begin
            void'($fscanf(fd_out, "%h\n", w_exp));
            w_exp = aplicar_ganancia(w_exp, g);
            avs_wr(A_SAMPLE_IN, w_in);
            avs_rd(A_SAMPLE_OUT, leido, w);
            if (leido !== w_exp) begin
                difs++;
                if (esperar_coincidencia) begin
                    if (difs <= MAX_REPORT)
                        $display("  [ERROR] fs=%0d %s par %0d: leido=%h esperado=%h",
                                 fs, caso, pares, leido, w_exp);
                    errores++;
                end
            end
            pares++;
        end
        $fclose(fd_in);
        $fclose(fd_out);
    endtask

    // Mete n pares de ruido al FIR para dejar el historial "sucio" y probar comportamiento
    task automatic ensuciar_historial(input int n);
        int fd, w;
        logic [31:0] w_in, d;
        fd = $fopen($sformatf("%s/fir_44100_ruido_in.hex", VEC_DIR), "r");
        for (int i = 0; i < n && $fscanf(fd, "%h\n", w_in) == 1; i++) begin
            avs_wr(A_SAMPLE_IN, w_in);
            avs_rd(A_SAMPLE_OUT, d, w);
        end
        $fclose(fd);
    endtask

    // -----------------------------------------------------------------
    // Secuencia
    // -----------------------------------------------------------------
    logic [31:0] d, t, w_in, imp_in [0:1], imp_out [0:1];
    int w, e0, pares, difs, fd_i, fd_o, total_pares;
    bit time_pend;

    initial begin
        $display("=== tb_audio_dsp ===");
        repeat (4) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        // Primeros dos pares del impulso a 44.1 kHz (para TC8)
        fd_i = $fopen($sformatf("%s/fir_44100_impulso_in.hex",  VEC_DIR), "r");
        fd_o = $fopen($sformatf("%s/fir_44100_impulso_out.hex", VEC_DIR), "r");
        for (int i = 0; i < 2; i++) begin
            void'($fscanf(fd_i, "%h\n", imp_in[i]));
            void'($fscanf(fd_o, "%h\n", imp_out[i]));
        end
        $fclose(fd_i);
        $fclose(fd_o);
        // ---------------- TC1 ----------------
        e0 = errores;
        avs_rd(A_ID, d, w); check("ID", d, 32'h41554431);
        reporte_caso("TC1: ID", e0);
        // ---------------- TC2 ----------------
        e0 = errores;
        avs_wr(A_CTRL, 32'h0); // bypass, GAIN = 4096 (reset)
        fd_i = $fopen($sformatf("%s/fir_44100_ruido_in.hex", VEC_DIR), "r");
        pares = 0;
        while ($fscanf(fd_i, "%h\n", w_in) == 1) begin
            avs_wr(A_SAMPLE_IN, w_in);
            avs_rd(A_SAMPLE_OUT, d, w);
            check($sformatf("bypass par %0d", pares), d, w_in);
            if (w != 0) begin
                $display("  [ERROR] bypass par %0d con waitrequest (%0d ciclos)", pares, w);
                errores++;
            end
            pares++;
        end
        $fclose(fd_i);
        reporte_caso($sformatf("TC2: bypass sin espera (%0d pares)", pares), e0);
        // ---------------- TC3, TC4, TC5 (las 3 fs) ----------------
        total_pares = 0;
        foreach (fs_list[f]) begin
            e0 = errores;
            cargar_coefs(fs_list[f]);
            avs_wr(A_CTRL, FIR_EN | HIST_CLR);
            correr_vector(fs_list[f], "impulso", 4096, 1'b1, pares, difs);
            total_pares += pares;
            reporte_caso($sformatf("TC3: respuesta al impulso y relectura de COEF (fs=%0d)", fs_list[f]), e0);
            e0 = errores;
            avs_wr(A_CTRL, FIR_EN | HIST_CLR);
            correr_vector(fs_list[f], "escalon", 4096, 1'b1, pares, difs); total_pares += pares;
            avs_wr(A_CTRL, FIR_EN | HIST_CLR);
            correr_vector(fs_list[f], "seno_paso", 4096, 1'b1, pares, difs); total_pares += pares;
            avs_wr(A_CTRL, FIR_EN | HIST_CLR);
            correr_vector(fs_list[f], "seno_rechazo", 4096, 1'b1, pares, difs); total_pares += pares;
            reporte_caso($sformatf("TC4: escalon y senos contra el modelo (fs=%0d)", fs_list[f]), e0);
            e0 = errores;
            avs_wr(A_CTRL, FIR_EN | HIST_CLR);
            correr_vector(fs_list[f], "ruido", 4096, 1'b1, pares, difs);
            total_pares += pares;
            reporte_caso($sformatf("TC5: ruido, %0d pares bit a bit (fs=%0d)", pares, fs_list[f]), e0);
        end
        $display("    pares por el FIR en TC3-TC5: %0d", total_pares);
        // ---------------- TC6 ----------------
        e0 = errores;
        cargar_coefs(8000);
        avs_wr(A_STATUS, 32'h2); // SAT = 0
        avs_rd(A_STATUS, d, w); check("SAT en 0 antes", d & 32'h2, 32'h0);
        avs_wr(A_CTRL, FIR_EN | HIST_CLR);
        correr_vector(8000, "saturacion", 4096, 1'b1, pares, difs);
        avs_rd(A_STATUS, d, w); check("SAT encendido", d & 32'h2, 32'h2);
        avs_wr(A_CTRL, 32'h0); // un par sin saturacion
        avs_wr(A_SAMPLE_IN, 32'h0);
        avs_rd(A_SAMPLE_OUT, d, w);
        avs_rd(A_STATUS, d, w); check("SAT sigue encendido (general)", d & 32'h2, 32'h2);
        avs_wr(A_STATUS, 32'h0); // escribir 0 no borra
        avs_rd(A_STATUS, d, w); check("escribir 0 no borra SAT", d & 32'h2, 32'h2);
        avs_wr(A_STATUS, 32'h2); // W1C
        avs_rd(A_STATUS, d, w); check("W1C borra SAT", d & 32'h2, 32'h0);
        reporte_caso("TC6: saturacion acumulada (general y W1C)", e0);
        // ---------------- TC7 ----------------
        e0 = errores;
        avs_wr(A_CTRL, FIR_EN);
        ensuciar_historial(50); // historial con coefs de 8 kHz
        cargar_coefs(44100); // recarga
        avs_wr(A_CTRL, FIR_EN | HIST_CLR);
        correr_vector(44100, "impulso", 4096, 1'b1, pares, difs); // tiene que coincidir
        avs_wr(A_CTRL, FIR_EN);
        ensuciar_historial(50);
        avs_wr(A_CTRL, FIR_EN); // SIN HIST_CLR
        correr_vector(44100, "impulso", 4096, 1'b0, pares, difs); // tiene que ser diferente
        if (difs == 0) begin
            $display("  [ERROR] sin HIST_CLR el resultado no cambio: HIST_CLR no tendría efecto");
            errores++;
        end else begin
            $display("    sin HIST_CLR: %0d de %0d pares distintos (esperado)", difs, pares);
        end
        reporte_caso("TC7: HIST_CLR y recarga de coeficientes", e0);
        // ---------------- TC8 ----------------
        // (a) leer SAMPLE_OUT n = 0..70 ciclos despues de escribir
        e0 = errores;
        max_wait = 0;
        for (int n = 0; n <= 70; n++) begin
            avs_wr(A_CTRL, 32'h0); // bypass: SAMPLE_OUT = marca
            avs_wr(A_SAMPLE_IN, 32'h1234_5678);
            avs_wr(A_CTRL, FIR_EN | HIST_CLR);
            avs_wr(A_SAMPLE_IN, imp_in[0]);
            esperar_ciclos(n);
            avs_rd(A_SAMPLE_OUT, d, w);
            check($sformatf("lectura %0d ciclos después de escribir", n), d, imp_out[0]);
        end
        $display("    waitrequest máximo por acceso: %0d ciclos", max_wait);
        reporte_caso("TC8: (a) SAMPLE_OUT nunca devuelve un dato viejo (0..70 ciclos)", e0);
        // (b) STATUS.BUSY durante el calculo, sin espera
        e0 = errores;
        avs_wr(A_CTRL, FIR_EN | HIST_CLR);
        avs_wr(A_SAMPLE_IN, imp_in[0]);
        avs_rd(A_STATUS, d, w);
        check("BUSY = 1 durante el calculo", d & 32'h1, 32'h1);
        if (w != 0) begin $display("  [ERROR] leer STATUS espero %0d ciclos", w); errores++; end
        avs_rd(A_SAMPLE_OUT, d, w);
        avs_rd(A_STATUS, d, w);
        check("BUSY = 0 al terminar", d & 32'h1, 32'h0);
        reporte_caso("TC8: (b) STATUS.BUSY se lee sin espera", e0);
        // (c) escrituras durante el calculo
        e0 = errores;
        avs_wr(A_CTRL, FIR_EN | HIST_CLR);
        avs_wr(A_SAMPLE_IN, imp_in[0]);
        avs_wr_w(A_SAMPLE_IN, imp_in[1], w); // llega mientras calcula
        if (w == 0) begin $display("  [ERROR] la 2a escritura a SAMPLE_IN no espero"); errores++; end
        avs_rd(A_SAMPLE_OUT, d, w);
        check("resultado del 2o par", d, imp_out[1]);
        avs_wr(A_SAMPLE_IN, 32'h0);
        avs_wr_w(A_COEF0, {16'h0, coef_mem[0]}, w); // COEF durante el calculo
        if (w == 0) begin $display("  [ERROR] la escritura a COEF no espero"); errores++; end
        avs_rd(A_COEF0, d, w);
        check("COEF[0] intacto", d, {{16{coef_mem[0][15]}}, coef_mem[0]});
        avs_rd(A_SAMPLE_OUT, d, w);
        reporte_caso("TC8: (c) escribir SAMPLE_IN o COEF durante el calculo espera", e0);
        // ---------------- TC9 ----------------
        e0 = errores;
        avs_wr(A_GAIN, 32'd2048);
        avs_wr(A_CTRL, FIR_EN | HIST_CLR);
        correr_vector(44100, "seno_paso", 2048, 1'b1, pares, difs);
        avs_wr(A_GAIN, 32'd0);
        avs_wr(A_CTRL, FIR_EN | HIST_CLR);
        correr_vector(44100, "seno_paso", 0, 1'b1, pares, difs);
        avs_wr(A_GAIN, 32'd4096);
        avs_wr(A_CTRL, FIR_EN | HIST_CLR);
        correr_vector(44100, "seno_paso", 4096, 1'b1, pares, difs);
        avs_wr(A_STATUS, 32'h2); // SAT = 0
        avs_wr(A_CTRL, 32'h0);
        avs_wr(A_GAIN, 32'd8191); // ~x2: satura
        avs_wr(A_SAMPLE_IN, 32'h8000_7FFF);
        avs_rd(A_SAMPLE_OUT, d, w); check("GAIN x2 saturado", d, 32'h8000_7FFF);
        avs_rd(A_STATUS, d, w); check("SAT por ganancia", d & 32'h2, 32'h2);
        avs_wr(A_STATUS, 32'h2);
        avs_wr(A_GAIN, 32'd4096);
        reporte_caso("TC9: GAIN sobre el FIR (x0.5, silencio, x1) y saturacion", e0);
        // ---------------- TC10 ----------------
        // (a) FRAME_CNT y TIME_CLR
        e0 = errores;
        avs_wr(A_FS, FS_PRUEBA);
        avs_wr(A_CTRL, TIME_CLR);
        avs_rd(A_FRAME_CNT, d, w); check("FRAME_CNT tras TIME_CLR", d, 0);
        avs_wr(A_CTRL, TIME_EN); // bypass, el tiempo avanza
        repeat (FS_PRUEBA * 61) avs_wr(A_SAMPLE_IN, 32'h0); // 61 "segundos"
        avs_rd(A_FRAME_CNT, d, w); check("FRAME_CNT", d, FS_PRUEBA * 61);
        avs_rd(A_TIME, t, w); // se revisa en (b)
        avs_wr(A_CTRL, TIME_EN | TIME_CLR);
        avs_rd(A_FRAME_CNT, d, w); check("FRAME_CNT tras 2o TIME_CLR", d, 0);
        avs_wr(A_CTRL, 32'h0); // TIME_EN = 0
        repeat (8) avs_wr(A_SAMPLE_IN, 32'h0);
        avs_rd(A_FRAME_CNT, d, w);  check("FRAME_CNT cuenta con TIME_EN = 0", d, 8);
        reporte_caso("TC10: (a) FRAME_CNT y TIME_CLR", e0);
        // (b) TIME (depende de time_7seg)
        e0 = errores;
        time_pend = (t == 32'h0);
        if (time_pend) begin
            $display("    TIME = 00:00 tras 61 s: time_7seg todavía falta");
        end else begin
            check("TIME = 01:01", t, 32'h0000_0101);
            avs_rd(A_TIME, d, w); check("TIME tras TIME_CLR y sin TIME_EN", d, 32'h0);
        end
        reporte_caso("TC10: (b) TIME MM:SS (time_7seg)", e0, time_pend);
        avs_wr(A_FS, 32'd44100);

        // ---------------- Resumen ----------------
        $display("-----------------------------------------");
        foreach (resumen[i]) $display("%s", resumen[i]);
        $display("-----------------------------------------");
        $display("Errores: %0d | Casos pendientes: %0d", errores, casos_pendientes);
        $display("RESULTADO: %s", (errores == 0) ? "PASS" : "FAIL");
        $display("-----------------------------------------");
        $finish;
    end
endmodule

// =============================================================================
//          ~~~~~ Smoke Test de audio_dsp por el bus Avalon ~~~~~
//
// Comprueba que paquete compila y responde por el bus, como lo vería el Nios
//
//   H1:  ID se lee correctamente
//   H2:  valores de reset de CTRL, STATUS, GAIN y FS
//   H3:  escritura/lectura de GAIN, FS y TRACK
//   H4:  carga de COEF[0..31] por el bus y relectura (con extension de signo)
//   H5:  bypass (FIR_EN = 0): SAMPLE_OUT = SAMPLE_IN, sin waitrequest
//   H6:  FIR por el bus: impulso a 44.1 kHz contra el modelo (waitrequest)
//   H7:  FRAME_CNT cuenta los pares y TIME_CLR lo borra
//   H8:  saturacion: STATUS.SAT se enciende y se borra escribiendo 1 (W1C)
//   H9:  ganancia: x0.5, silencio y saturacion por ganancia (sat_general)
//
// Correr con:  sim/run_audio_dsp.sh        
// =============================================================================
`timescale 1ns/1ps

module tb_audio_dsp;
    localparam string VEC_DIR = "vectors";
    // direcciones por palabra (offset en bytes/4)
    localparam logic [5:0] A_ID = 0, A_CTRL = 1, A_STATUS = 2, A_SAMPLE_IN = 3,
                           A_SAMPLE_OUT = 4, A_GAIN = 5, A_FS = 6, A_TIME = 7,
                           A_TRACK = 8, A_FRAME_CNT = 9, A_COEF0 = 32;
    // bits de CTRL
    localparam logic [31:0] FIR_EN = 32'h01, HIST_CLR = 32'h02, TIME_EN = 32'h04,
                            TIME_CLR = 32'h08, HEX_EN = 32'h10;
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

    // ------------------------------------------------------------------------
    // Movimiento en Avalon (como lo haría el Nios): respetando el waitrequest
    // ------------------------------------------------------------------------
    task automatic avs_wr(input logic [5:0] a, input logic [31:0] d);
        int w = 0;
        @(negedge clk);
        avs_address = a; avs_writedata = d; avs_write = 1'b1;
        #1;
        while (avs_waitrequest) begin @(negedge clk); #1; w++; end
        @(posedge clk); #1;
        avs_write = 1'b0;
        if (w > max_wait) max_wait = w;
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

    task automatic check(input string nombre, input logic [31:0] leido, input logic [31:0] esperado);
        if (leido !== esperado) begin
            $display("  [ERROR] %s: leido=%h esperado=%h", nombre, leido, esperado);
            errores++;
        end
    endtask

    task automatic resultado(input string nombre, input int err_antes);
        $display("[%s] %s", (errores == err_antes) ? "PASS" : "FAIL", nombre);
    endtask

    // -----------------------------------------------------------------
    // Procesa un archivo de vectores por el bus y compara
    // -----------------------------------------------------------------
    task automatic proc_vectores(input string caso, output int pares);
        int fd_in, fd_out, w;
        logic [31:0] w_in, w_exp, leido;
        fd_in  = $fopen($sformatf("%s/fir_44100_%s_in.hex",  VEC_DIR, caso), "r");
        fd_out = $fopen($sformatf("%s/fir_44100_%s_out.hex", VEC_DIR, caso), "r");
        if (fd_in == 0 || fd_out == 0) $fatal(1, "No se pudo abrir el caso %s (correr desde sim/)", caso);
        pares = 0;
        while ($fscanf(fd_in, "%h\n", w_in) == 1) begin
            void'($fscanf(fd_out, "%h\n", w_exp));
            avs_wr(A_SAMPLE_IN, w_in);
            avs_rd(A_SAMPLE_OUT, leido, w);
            check($sformatf("%s par %0d", caso, pares), leido, w_exp);
            pares++;
        end
        $fclose(fd_in);
        $fclose(fd_out);
    endtask

    // -----------------------------------------------------------------
    // Secuencia
    // -----------------------------------------------------------------
    logic [31:0] d;
    logic [15:0] coef_mem [0:31];
    int w, e0, pares;

    initial begin
        $display("=== tb_audio_dsp (Smoke test) ===");
        repeat (4) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        // H1
        e0 = errores;
        avs_rd(A_ID, d, w); check("ID", d, 32'h41554431);
        resultado("H1: ID", e0);
        // H2
        e0 = errores;
        avs_rd(A_CTRL, d, w); check("CTRL reset", d, 32'h0);
        avs_rd(A_STATUS, d, w); check("STATUS reset", d, 32'h0);
        avs_rd(A_GAIN, d, w); check("GAIN reset", d, 32'd4096);
        avs_rd(A_FS, d, w); check("FS reset", d, 32'd44100);
        resultado("H2: valores de reset", e0);
        // H3
        e0 = errores;
        avs_wr(A_GAIN, 32'd2048); avs_rd(A_GAIN, d, w); check("GAIN", d, 32'd2048);
        avs_wr(A_FS, 32'd8000); avs_rd(A_FS, d, w); check("FS", d, 32'd8000);
        avs_wr(A_TRACK, 32'd7); avs_rd(A_TRACK, d, w); check("TRACK", d, 32'd7);
        avs_wr(A_GAIN, 32'd4096); avs_wr(A_FS, 32'd44100);
        resultado("H3: GAIN, FS y TRACK", e0);
        // H4
        e0 = errores;
        $readmemh($sformatf("%s/coefs_44100.hex", VEC_DIR), coef_mem);
        for (int k = 0; k < 32; k++) avs_wr(A_COEF0 + k, {16'h0, coef_mem[k]});
        for (int k = 0; k < 32; k++) begin
            avs_rd(A_COEF0 + k, d, w);
            check($sformatf("COEF[%0d]", k), d, {{16{coef_mem[k][15]}}, coef_mem[k]});
        end
        resultado("H4: COEF[0..31] por el bus", e0);
        // H5
        e0 = errores;
        avs_wr(A_CTRL, 32'h0); // bypass
        avs_wr(A_SAMPLE_IN, 32'h8001_7FFF);
        avs_rd(A_SAMPLE_OUT, d, w);
        check("bypass", d, 32'h8001_7FFF);
        if (w != 0) begin $display("  [ERROR] bypass con waitrequest (%0d ciclos)", w); errores++; end
        resultado("H5: bypass sin espera", e0);
        // H6 + H7
        e0 = errores;
        avs_wr(A_CTRL, TIME_CLR);                    // FRAME_CNT = 0
        avs_wr(A_CTRL, FIR_EN | HIST_CLR | TIME_EN); // FIR, historial limpio
        max_wait = 0;
        proc_vectores("impulso", pares);
        $display("    waitrequest maximo por acceso: %0d ciclos", max_wait);
        if (max_wait == 0) begin $display("  [ERROR] el FIR nunca hizo esperar al bus"); errores++; end
        resultado($sformatf("H6: FIR por el bus (impulso, %0d pares)", pares), e0);
        e0 = errores;
        avs_rd(A_FRAME_CNT, d, w); check("FRAME_CNT", d, pares);
        avs_wr(A_CTRL, FIR_EN | TIME_CLR);
        avs_rd(A_FRAME_CNT, d, w); check("FRAME_CNT tras TIME_CLR", d, 0);
        resultado("H7: FRAME_CNT y TIME_CLR", e0);
        // H8
        e0 = errores;
        avs_wr(A_CTRL, FIR_EN | HIST_CLR);
        proc_vectores("saturacion", pares);
        avs_rd(A_STATUS, d, w); check("STATUS.SAT encendido", d & 32'h2, 32'h2);
        avs_wr(A_STATUS, 32'h2); // W1C
        avs_rd(A_STATUS, d, w); check("STATUS.SAT borrado", d & 32'h2, 32'h0);
        resultado("H8: saturacion acumulada (W1C)", e0);
        // H9
        e0 = errores;
        avs_wr(A_CTRL, 32'h0); // bypass: solo ganancia
        avs_wr(A_GAIN, 32'd2048); // x0.5
        avs_wr(A_SAMPLE_IN, 32'h8001_7FFF); // L = 32767, R = -32767
        avs_rd(A_SAMPLE_OUT, d, w); check("GAIN x0.5", d, 32'hC000_3FFF);  // 16383, -16384
        avs_wr(A_GAIN, 32'd0); // silencio
        avs_wr(A_SAMPLE_IN, 32'h8001_7FFF);
        avs_rd(A_SAMPLE_OUT, d, w); check("GAIN 0", d, 32'h0000_0000);
        avs_wr(A_STATUS, 32'h2); // SAT = 0
        avs_wr(A_GAIN, 32'd8191); // ~x2: satura
        avs_wr(A_SAMPLE_IN, 32'h8000_7FFF); // L = 32767, R = -32768
        avs_rd(A_SAMPLE_OUT, d, w); check("GAIN x2 saturado", d, 32'h8000_7FFF);
        avs_rd(A_STATUS, d, w); check("STATUS.SAT por ganancia", d & 32'h2, 32'h2);
        avs_wr(A_STATUS, 32'h2);
        avs_wr(A_GAIN, 32'd4096); // de vuelta a x1
        resultado("H9: ganancia", e0);
        $display("---------------------------------------------");
        $display("Errores: %0d", errores);
        $display("RESULTADO: %s", (errores == 0) ? "PASS" : "FAIL");
        $display("---------------------------------------------");
        $finish;
    end

endmodule

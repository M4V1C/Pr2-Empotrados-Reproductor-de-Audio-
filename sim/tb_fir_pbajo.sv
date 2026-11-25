// =============================================================================
// ~~~~~ Testbench unitario de fir_pbajo (para el issue F-02 del repo) ~~~~~~
//
// Para cada fs (8000, 16000, 44100):
//   1. Carga coefs_<fs>.hex por el puerto de coeficientes y los relee.
//   2. Para cada caso (impulso, escalon, seno_paso, seno_rechazo, ruido,
//      saturacion): borra el historial, procesa fir_<fs>_<caso>_in.hex par a
//      par y compara bit a bit contra fir_<fs>_<caso>_out.hex
//      (generados por tools/gen_coefs.py).
//   3. Mide los ciclos por par (<= 80).
//
// Correr desde sim/ con:  ./run_fir_pbajo.sh     (consola)
//                         ./run_fir_pbajo.sh gui (con formas de onda)
// =============================================================================
`timescale 1ns/1ps

module tb_fir_pbajo;

    localparam int    N_TAPS     = 32;
    localparam int    AW         = 5;
    localparam int    MAX_CYCLES = 80;          // criterio de aceptacion de F-02
    localparam int    MAX_REPORT = 10;          // errores impresos por caso
    localparam string VEC_DIR    = "vectors";

    // ---------------- reloj de 50 MHz y reset ----------------
    logic clk = 1'b0;
    logic rst = 1'b1;
    always #10 clk = ~clk;

    // ---------------- senales del DUT ----------------
    logic                start      = 1'b0;
    logic                hist_clr   = 1'b0;
    logic signed [15:0]  x_l        = '0;
    logic signed [15:0]  x_r        = '0;
    wire  signed [15:0]  y_l, y_r;
    wire                 busy, done, sat;
    logic                coef_we    = 1'b0;
    logic [AW-1:0]       coef_addr  = '0;
    logic signed [15:0]  coef_wdata = '0;
    wire  signed [15:0]  coef_rdata;

    fir_pbajo #(.N_TAPS(N_TAPS), .AW(AW)) dut (.*);

    // ---------------- casos ----------------
    int    fs_list[3]    = '{8000, 16000, 44100};
    string case_list[6]  = '{"impulso", "escalon", "seno_paso",
                             "seno_rechazo", "ruido", "saturacion"};

    int total_err    = 0;
    int total_frames = 0;
    int total_fail   = 0;
    int max_seen     = 0;

    logic [15:0] coef_mem [0:N_TAPS-1];       // coeficientes leidos del .hex

    // -----------------------------------------------------------------
    // Carga los coeficientes y verifica la relectura
    // -----------------------------------------------------------------
    task automatic load_coefs(input int fs);
        int errs = 0;
        $readmemh($sformatf("%s/coefs_%0d.hex", VEC_DIR, fs), coef_mem);

        for (int i = 0; i < N_TAPS; i++) begin
            @(negedge clk);
            coef_we    = 1'b1;
            coef_addr  = i[AW-1:0];
            coef_wdata = coef_mem[i];
        end
        @(negedge clk);
        coef_we = 1'b0;

        for (int i = 0; i < N_TAPS; i++) begin
            @(negedge clk);
            coef_addr = i[AW-1:0];
            #1;
            if (coef_rdata !== coef_mem[i]) begin
                $display("  [ERROR] fs=%0d COEF[%0d] leido=%h esperado=%h",
                         fs, i, coef_rdata, coef_mem[i]);
                errs++;
            end
        end
        total_err += errs;
        $display("[%s] fs=%0d carga y relectura de %0d coeficientes",
                 (errs == 0) ? "PASS" : "FAIL", fs, N_TAPS);
        if (errs != 0) total_fail++;
    endtask

    // -----------------------------------------------------------------
    // Corre un caso completo contra el modelo
    // -----------------------------------------------------------------
    task automatic run_case(input int fs, input string name);
        string       f_in, f_out;
        int          fd_in, fd_out;
        logic [31:0] w_in, w_exp;
        int          frames = 0, errs = 0, cycles, case_max = 0;
        bit          sat_seen = 1'b0;

        f_in  = $sformatf("%s/fir_%0d_%s_in.hex",  VEC_DIR, fs, name);
        f_out = $sformatf("%s/fir_%0d_%s_out.hex", VEC_DIR, fs, name);
        fd_in  = $fopen(f_in,  "r");
        fd_out = $fopen(f_out, "r");
        if (fd_in == 0 || fd_out == 0)
            $fatal(1, "No se pudo abrir %s o %s (correr desde sim/)", f_in, f_out);

        // borra el historial: cada caso empieza con estado en cero
        @(negedge clk); hist_clr = 1'b1;
        @(negedge clk); hist_clr = 1'b0;

        while ($fscanf(fd_in, "%h\n", w_in) == 1) begin
            if ($fscanf(fd_out, "%h\n", w_exp) != 1)
                $fatal(1, "%s tiene menos lineas que %s", f_out, f_in);

            // empaquetado: [31:16] = R, [15:0] = L
            @(negedge clk);
            x_l   = w_in[15:0];
            x_r   = w_in[31:16];
            start = 1'b1;

            cycles = 0;
            do begin
                @(posedge clk); #1;
                start = 1'b0;
                cycles++;
            end while (!done && cycles < 1000);

            if (!done)
                $fatal(1, "Timeout: fs=%0d caso=%s par=%0d", fs, name, frames);

            if (sat) sat_seen = 1'b1;
            if (cycles > case_max) case_max = cycles;

            if ({y_r, y_l} !== w_exp) begin
                if (errs < MAX_REPORT)
                    $display("  [ERROR] fs=%0d %s par %0d: L=%h R=%h  esperado L=%h R=%h",
                             fs, name, frames, y_l, y_r, w_exp[15:0], w_exp[31:16]);
                errs++;
            end
            frames++;
        end
        $fclose(fd_in);
        $fclose(fd_out);

        if (name == "saturacion" && !sat_seen) begin
            $display("  [ERROR] fs=%0d saturacion: la bandera sat nunca se activo", fs);
            errs++;
        end

        if (case_max > max_seen) max_seen = case_max;
        total_err    += errs;
        total_frames += frames;
        if (errs != 0) total_fail++;

        $display("[%s] fs=%0d %s: %0d pares, %0d errores, %0d ciclos/par%s",
                 (errs == 0) ? "PASS" : "FAIL", fs, name, frames, errs, case_max,
                 (name == "saturacion") ? (sat_seen ? ", sat=1 OK" : ", sat nunca en 1") : "");
    endtask

    // -----------------------------------------------------------------
    // Secuencia principal
    // -----------------------------------------------------------------
    initial begin
        $display("=== tb_fir_pbajo: N_TAPS=%0d ===", N_TAPS);
        repeat (4) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        foreach (fs_list[f]) begin
            load_coefs(fs_list[f]);
            foreach (case_list[c])
                run_case(fs_list[f], case_list[c]);
        end

        $display("--------------------------------------------------------------");
        $display("Pares procesados: %0d | errores: %0d | ciclos/par max: %0d (limite %0d)",
                 total_frames, total_err, max_seen, MAX_CYCLES);
        if (total_err == 0 && total_fail == 0 && max_seen <= MAX_CYCLES)
            $display("RESULTADO: PASS");
        else
            $display("RESULTADO: FAIL");
        $display("--------------------------------------------------------------");
        $finish;
    end

endmodule

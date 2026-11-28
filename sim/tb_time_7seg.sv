// =======================================================================================================
//                  ~~~~~ Testbench unitario de time_7seg (tiempo MM:SS y 7 segmentos) ~~~~~
//
// Dos formas de verificar al mismo tiempo:
//   1. Modelo de referencia: en CADA ciclo, un modelo escrito en el testbench (segundos totales + preescalador,
//      sin BCD) predice time_mmss y los 6 displays; cualquier diferencia cuenta como error.
//   2. Casos dirigidos: comprueban valores absolutos (por si el modelo tuviera el mismo error que el RTL).
//
//   T1:  reset: 00:00 y displays apagados (hex_en = 0 al arrancar)
//   T2:  hex_en = 1 muestra "00 00 00"
//   T3:  avance 00:00 -> 00:01 justo en el pulso numero fs (no antes)
//   T4:  acarreos 00:59 -> 01:00 y 09:59 -> 10:00
//   T5:  tope en 99:59 (no vuelve a 00:00)
//   T6:  time_clr; y time_clr en el mismo ciclo que el tick_par que completaria el segundo (gana time_clr)
//   T7:  tick_par en ciclos consecutivos (se cuentan todos)
//   T8:  hex_en = 0 apaga todo y el tiempo sigue contando
//   T9:  decodificador: los 10 digitos, track = 0, 7, 42, 99 y el barrido 0..127 (100..127 -> "--")
//   T10: fs reales (8000, 16000, 44100), fs = 0 no avanza y fs baja a mitad de un segundo
//   T11: 300000 ciclos aleatorios (pulsos, time_clr, hex_en, track y fs) contra el modelo
//
// Correr con:  sim/run_time_7seg.sh       (consola)
//              sim/run_time_7seg.sh gui   (formas de onda: wave_time_7seg.do)
// =======================================================================================================
`timescale 1ns/1ps

module tb_time_7seg;
    localparam int FS_PRUEBA = 4; // FS pequeño: 4 pulsos = 1 s
    localparam int MAX_REPORT = 10; // errores impresos

    // --- reloj de 50 MHz ---
    logic clk = 1'b0;
    always #10 clk = ~clk;

    // --- DUT ---
    logic rst = 1'b1;
    logic tick_par = 1'b0;
    logic time_clr = 1'b0;
    logic hex_en = 1'b0;
    logic [16:0] fs = 17'(FS_PRUEBA);
    logic [6:0] track = '0;
    wire  [14:0] time_mmss;
    wire  [6:0] hex0, hex1, hex2, hex3, hex4, hex5;
    time_7seg dut (.*);

    int errores = 0;
    string resumen[$];

    // Tabla del README (seccion 7.4): activos en bajo, bit 0 = a ... bit 6 = g
    localparam logic [6:0] DIGITO [10] = '{7'h40, 7'h79, 7'h24, 7'h30, 7'h19,
                                           7'h12, 7'h02, 7'h78, 7'h00, 7'h10};
    localparam logic [6:0] APAGADO = 7'h7F, GUION = 7'h3F;
    localparam int TRACKS [4] = '{0, 7, 42, 99};
    localparam int FS_REALES [3] = '{8000, 16000, 44100};

    function automatic logic [6:0] seg(input int d);
        return (d >= 0 && d <= 9) ? DIGITO[d] : GUION;
    endfunction

    // =========================================================================================
    // Modelo de referencia (otra forma de contar: segundos totales en binario, sin BCD)
    // Se actualiza en el flanco de subida con las mismas entradas que ve el DUT.
    // =========================================================================================
    int m_presc = 0, m_seg = 0; // m_seg = segundos totales 0..5999
    logic [6:0] m_hex [6] = '{default: APAGADO};
    function automatic logic [6:0] m_hex_de(input int i, input int s, input int trk);
        case (i)
            0: return seg((s % 60) % 10);
            1: return seg((s % 60) / 10);
            2: return seg((s / 60) % 10);
            3: return seg((s / 60) / 10);
            4: return (trk > 99) ? GUION : seg(trk % 10);
            default: return (trk > 99) ? GUION : seg(trk / 10);
        endcase
    endfunction

    always @(posedge clk) begin
        // displays: registrados con el estado ANTES de este flanco
        for (int i = 0; i < 6; i++)
            m_hex[i] = (rst || !hex_en) ? APAGADO : m_hex_de(i, m_seg, track);
        // tiempo
        if (rst || time_clr) begin
            m_presc = 0;
            m_seg = 0;
        end else if (tick_par && fs != 0) begin
            if (m_presc >= int'(fs) - 1) begin
                m_presc = 0;
                if (m_seg < 99*60 + 59) m_seg++;
            end else begin
                m_presc++;
            end
        end
    end

    // Comparacion en cada flanco de bajada (salidas estables, entradas todavia sin cambiar)
    int comparaciones = 0;
    always @(negedge clk) begin
        logic [14:0] esperado_t;
        logic [6:0] hx [6];
        esperado_t = {7'(m_seg / 60), 2'b00, 6'(m_seg % 60)};
        hx = '{hex0, hex1, hex2, hex3, hex4, hex5};
        comparaciones++;
        if (time_mmss !== esperado_t) begin
            if (errores < MAX_REPORT)
                $display("  [ERROR] %0t: time_mmss = %02d:%02d, modelo %02d:%02d", $time,
                         time_mmss[14:8], time_mmss[5:0], m_seg / 60, m_seg % 60);
            errores++;
        end
        for (int i = 0; i < 6; i++)
            if (hx[i] !== m_hex[i]) begin
                if (errores < MAX_REPORT)
                    $display("  [ERROR] %0t: hex%0d = %h, modelo %h", $time, i, hx[i], m_hex[i]);
                errores++;
            end
    end

    // =========================================================================================
    // Tareas (las entradas cambian en el flanco de bajada, el DUT las toma en el de subida)
    // =========================================================================================
    task automatic ciclos(input int n);
        repeat (n) @(negedge clk);
    endtask

    // n pulsos separados (1 ciclo en alto, 1 en bajo)
    task automatic pulsos(input int n);
        repeat (n) begin
            tick_par = 1'b1; ciclos(1);
            tick_par = 1'b0; ciclos(1);
        end
    endtask

    // n pulsos en ciclos consecutivos
    task automatic pulsos_seguidos(input int n);
        if (n > 0) begin
            tick_par = 1'b1; ciclos(n);
            tick_par = 1'b0;
        end
    endtask

    task automatic limpiar();
        time_clr = 1'b1; ciclos(1);
        time_clr = 1'b0; ciclos(1);
    endtask

    // Avanza 's' segundos completos con el fs actual
    task automatic segundos(input int s);
        pulsos_seguidos(s * int'(fs));
    endtask

    task automatic check_tiempo(input int mm, input int ss, input string que);
        if (time_mmss !== {7'(mm), 2'b00, 6'(ss)}) begin
            if (errores < MAX_REPORT)
                $display("  [ERROR] %s: TIME = %02d:%02d (%h), esperado %02d:%02d",
                         que, time_mmss[14:8], time_mmss[5:0], time_mmss, mm, ss);
            errores++;
        end
    endtask

    // Revisa los 6 displays (espera 1 ciclo: las salidas son registradas)
    task automatic check_hex(input logic [6:0] e5, e4, e3, e2, e1, e0, input string que);
        ciclos(1);
        if ({hex5, hex4, hex3, hex2, hex1, hex0} !== {e5, e4, e3, e2, e1, e0}) begin
            if (errores < MAX_REPORT)
                $display("  [ERROR] %s: hex5..0 = %h %h %h %h %h %h, esperado %h %h %h %h %h %h", que,
                         hex5, hex4, hex3, hex2, hex1, hex0, e5, e4, e3, e2, e1, e0);
            errores++;
        end
    endtask

    // Displays para MM:SS y track en decimal
    task automatic check_display(input int trk, input int mm, input int ss, input string que);
        check_hex(seg(trk / 10), seg(trk % 10), seg(mm / 10), seg(mm % 10), seg(ss / 10), seg(ss % 10), que);
    endtask

    task automatic reporte(input string nombre, input int e0);
        string linea;
        linea = $sformatf("[%s] %s", (errores == e0) ? "PASS" : "FAIL", nombre);
        $display("%s", linea);
        resumen.push_back(linea);
    endtask

    // =========================================================================================
    // Casos
    // =========================================================================================
    int e0;

    initial begin
        $display("=== tb_time_7seg ===");

        // ---------------- T1: reset ----------------
        e0 = errores;
        ciclos(4);
        rst = 1'b0;
        ciclos(1);
        check_tiempo(0, 0, "T1 tras reset");
        check_hex(APAGADO, APAGADO, APAGADO, APAGADO, APAGADO, APAGADO, "T1 hex_en = 0");
        reporte("T1: reset -> 00:00 y displays apagados", e0);

        // ---------------- T2: hex_en ----------------
        e0 = errores;
        hex_en = 1'b1;
        check_display(0, 0, 0, "T2 00 00 00");
        reporte("T2: hex_en = 1 muestra 00 00:00", e0);

        // ---------------- T3: avance de 1 s ----------------
        e0 = errores;
        pulsos(FS_PRUEBA - 1);
        check_tiempo(0, 0, "T3 con fs-1 pulsos");
        pulsos(1);
        check_tiempo(0, 1, "T3 con fs pulsos");
        check_display(0, 0, 1, "T3 display 00:01");
        reporte("T3: 00:00 -> 00:01 justo en el pulso fs", e0);

        // ---------------- T4: acarreos ----------------
        e0 = errores;
        segundos(58);                       // 00:59
        check_tiempo(0, 59, "T4 00:59");
        segundos(1);
        check_tiempo(1, 0, "T4 01:00");
        check_display(0, 1, 0, "T4 display 01:00");
        segundos(8 * 60 + 59);              // 09:59
        check_tiempo(9, 59, "T4 09:59");
        segundos(1);
        check_tiempo(10, 0, "T4 10:00");
        check_display(0, 10, 0, "T4 display 10:00");
        reporte("T4: acarreos 00:59 -> 01:00 y 09:59 -> 10:00", e0);

        // ---------------- T5: tope ----------------
        e0 = errores;
        segundos(89 * 60 + 59);             // 99:59
        check_tiempo(99, 59, "T5 99:59");
        check_display(0, 99, 59, "T5 display 99:59");
        segundos(5);
        pulsos(3);
        check_tiempo(99, 59, "T5 se queda en 99:59");
        check_display(0, 99, 59, "T5 display sigue en 99:59");
        reporte("T5: tope en 99:59", e0);

        // ---------------- T6: time_clr ----------------
        e0 = errores;
        limpiar();
        check_tiempo(0, 0, "T6 time_clr");
        check_display(0, 0, 0, "T6 display 00:00");
        // time_clr en el MISMO ciclo que el pulso que completaria el segundo
        pulsos(FS_PRUEBA - 1);              // preescalador en fs-1
        tick_par = 1'b1; time_clr = 1'b1; ciclos(1);
        tick_par = 1'b0; time_clr = 1'b0; ciclos(1);
        check_tiempo(0, 0, "T6 time_clr gana a tick_par");
        pulsos(FS_PRUEBA - 1);              // si el preescalador no se borro, aqui pasaria a 00:01
        check_tiempo(0, 0, "T6 preescalador en 0 tras time_clr");
        pulsos(1);
        check_tiempo(0, 1, "T6 00:01 tras fs pulsos nuevos");
        reporte("T6: time_clr (tambien junto con tick_par)", e0);

        // ---------------- T7: pulsos consecutivos ----------------
        e0 = errores;
        limpiar();
        pulsos_seguidos(10 * FS_PRUEBA);
        check_tiempo(0, 10, "T7 10 s con pulsos seguidos");
        pulsos_seguidos(FS_PRUEBA - 1);
        check_tiempo(0, 10, "T7 sin completar el segundo");
        pulsos_seguidos(1);
        check_tiempo(0, 11, "T7 00:11");
        reporte("T7: tick_par en ciclos consecutivos", e0);

        // ---------------- T8: hex_en = 0 ----------------
        e0 = errores;
        hex_en = 1'b0;
        check_hex(APAGADO, APAGADO, APAGADO, APAGADO, APAGADO, APAGADO, "T8 apagados");
        segundos(3);
        check_tiempo(0, 14, "T8 sigue contando apagado");
        check_hex(APAGADO, APAGADO, APAGADO, APAGADO, APAGADO, APAGADO, "T8 siguen apagados");
        hex_en = 1'b1;
        check_display(0, 0, 14, "T8 al encender muestra 00:14");
        reporte("T8: hex_en = 0 apaga y el tiempo sigue", e0);

        // ---------------- T9: decodificador ----------------
        e0 = errores;
        foreach (DIGITO[d]) begin           // los 10 digitos en HEX0 (unidades de segundo)
            limpiar();
            segundos(d);
            check_hex(seg(0), seg(0), seg(0), seg(0), seg(0), DIGITO[d], $sformatf("T9 digito %0d", d));
        end
        limpiar();
        foreach (TRACKS[i]) begin
            track = 7'(TRACKS[i]);
            check_display(TRACKS[i], 0, 0, $sformatf("T9 track = %0d", TRACKS[i]));
        end
        for (int trk = 0; trk < 128; trk++) begin
            track = 7'(trk);
            if (trk > 99) check_hex(GUION, GUION, seg(0), seg(0), seg(0), seg(0), $sformatf("T9 track = %0d", trk));
            else          check_display(trk, 0, 0, $sformatf("T9 track = %0d", trk));
        end
        track = 7'd3;
        reporte("T9: decodificador (10 digitos, track 0/7/42/99, 100..127 -> --)", e0);

        // ---------------- T10: fs reales ----------------
        e0 = errores;
        foreach (FS_REALES[i]) begin
            int f;
            f = FS_REALES[i];
            fs = 17'(f);
            limpiar();
            pulsos_seguidos(f - 1);
            check_tiempo(0, 0, $sformatf("T10 fs = %0d, fs-1 pulsos", f));
            pulsos_seguidos(1);
            check_tiempo(0, 1, $sformatf("T10 fs = %0d, fs pulsos", f));
            pulsos_seguidos(2 * f);
            check_tiempo(0, 3, $sformatf("T10 fs = %0d, 3 s", f));
        end
        // fs = 0: no avanza
        fs = 17'd0;
        limpiar();
        pulsos_seguidos(100);
        check_tiempo(0, 0, "T10 fs = 0 no avanza");
        // fs baja a mitad de un segundo: el siguiente pulso completa el segundo
        fs = 17'd44100;
        pulsos_seguidos(1000);
        fs = 17'(FS_PRUEBA);
        pulsos(1);
        check_tiempo(0, 1, "T10 fs baja de 44100 a 4 con el preescalador en 1000");
        pulsos(FS_PRUEBA);
        check_tiempo(0, 2, "T10 despues sigue con fs = 4");
        reporte("T10: fs = 8000/16000/44100, fs = 0 y cambio de fs", e0);

        // ---------------- T11: aleatorio contra el modelo ----------------
        // El modelo se compara en cada ciclo desde el inicio; aqui se ejercitan combinaciones al azar.
        e0 = errores;
        begin
            automatic int fs_azar[4] = '{3, 4, 7, 10};
            automatic int maximo = 0;
            for (int n = 0; n < 300000; n++) begin
                tick_par = ($urandom_range(0, 99) < 60);
                time_clr = ($urandom_range(0, 99999) == 0);
                if ($urandom_range(0, 9999) == 0) hex_en = ~hex_en;
                if ($urandom_range(0, 4999) == 0) track = 7'($urandom_range(0, 127));
                if ($urandom_range(0, 49999) == 0) fs = 17'(fs_azar[$urandom_range(0, 3)]);
                ciclos(1);
                if (m_seg > maximo) maximo = m_seg;
            end
            tick_par = 1'b0; time_clr = 1'b0;
            ciclos(2);
            $display("    T11: tiempo maximo alcanzado %02d:%02d", maximo / 60, maximo % 60);
        end
        reporte("T11: 300000 ciclos aleatorios contra el modelo", e0);

        // ---------------- Resumen ----------------
        $display("-------------------------------------------------");
        foreach (resumen[i]) $display("%s", resumen[i]);
        $display("-------------------------------------------------");
        $display("Ciclos comparados con el modelo: %0d | errores: %0d", comparaciones, errores);
        $display("RESULTADO: %s", (errores == 0) ? "PASS" : "FAIL");
        $display("-------------------------------------------------");
        $finish;
    end
endmodule

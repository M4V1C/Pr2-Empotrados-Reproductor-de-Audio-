// =======================================================================
//              ~~~~~ Testbench unitario de ganancia ~~~~~
//
// Compara la salida contra una referencia calculada en el testbench:
//     ref = sat16( (x * gain) >>> 12 )
//
//   C1:  casos límite: gain = 0, 2048, 4096, 8191 con x en los extremos
//   C2:  gain = 4096 deja la muestra igual (x1.0 exacto)
//   C3:  20000 pares aleatorios con ganancias aleatorias (0..8191)
//   C4:  la bandera sat coincide con la referencia
//
// Correr con:  sim/run_ganancia.sh
// =======================================================================
`timescale 1ns/1ps

module tb_ganancia;
    logic [31:0] x_lr = '0;
    logic [12:0] gain = '0;
    wire [31:0] y_lr;
    wire sat;
    ganancia dut (.*);
    int errores = 0, pruebas = 0;
    function automatic int sat16(input int v);
        if (v >  32767) return  32767;
        if (v < -32768) return -32768;
        return v;
    endfunction
    // Aplica un par y compara contra la referencia
    task automatic probar(input logic signed [15:0] l, input logic signed [15:0] r,
                          input logic [12:0] g, input string grupo);
        int pl, pr, rl, rr;
        bit rsat;
        pl = (int'(l) * int'(g)) >>> 12;
        pr = (int'(r) * int'(g)) >>> 12;
        rl = sat16(pl);
        rr = sat16(pr);
        rsat = (rl != pl) || (rr != pr);
        x_lr = {r, l}; //junta el par
        gain = g;
        #1;
        pruebas++;
        if (y_lr !== {rr[15:0], rl[15:0]} || sat !== rsat) begin
            if (errores < 10)
                $display("  [ERROR] %s: L=%0d R=%0d gain=%0d -> y_L=%0d y_R=%0d sat=%0b | esperado %0d %0d sat=%0b",
                         grupo, l, r, g, $signed(y_lr[15:0]), $signed(y_lr[31:16]), sat, rl, rr, rsat);
            errores++;
        end
    endtask

    logic signed [15:0] extremos [5]  = '{16'sd32767, -16'sd32768, 16'sd1, -16'sd1, 16'sd0};
    logic [12:0] ganancias [4] = '{13'd0, 13'd2048, 13'd4096, 13'd8191};
    int e0;

    initial begin
        $display("=== tb_ganancia ===");
        // C1:
        e0 = errores;
        foreach (extremos[i]) foreach (extremos[j]) foreach (ganancias[k])
            probar(extremos[i], extremos[j], ganancias[k], "C1");
        $display("[%s] C1: casos de borde", (errores == e0) ? "PASS" : "FAIL");
        // C2:
        e0 = errores;
        for (int v = -32767; v <= 32767; v += 97) begin
            probar(v[15:0], v[15:0], 13'd4096, "C2");
            if (y_lr !== {v[15:0], v[15:0]}) begin
                $display("  [ERROR] C2: x1.0 cambio la muestra %0d", v);
                errores++;
            end
        end
        $display("[%s] C2: gain = 4096 es x1.0 exacto", (errores == e0) ? "PASS" : "FAIL");
        // C3 + C4
        e0 = errores;
        for (int n = 0; n < 20000; n++)
            probar($urandom(), $urandom(), $urandom_range(0, 8191), "C3");
        $display("[%s] C3/C4: 20000 pares aleatorios (valor y bandera sat)", (errores == e0) ? "PASS" : "FAIL");
        $display("-------------------------------------------------");
        $display("Pruebas: %0d | errores: %0d", pruebas, errores);
        $display("RESULTADO: %s", (errores == 0) ? "PASS" : "FAIL");
        $display("------------------------------------------------");
        $finish;
    end
endmodule

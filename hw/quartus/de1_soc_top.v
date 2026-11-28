// =====================================================================
// de1_soc_top.v -- Tope del diseno en la DE1-SoC
// El tope es el "cableado" entre los pines fisicos de la tarjeta y el
// sistema generado por Platform Designer (soc_system). Los nombres de
// los puertos coinciden con los del .qsf (CLOCK_50, KEY, LEDR, ...).
//
// Fase 1: solo reloj, reset y dos LED de diagnostico generados en HW.
// =====================================================================
module de1_soc_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,        // activos en bajo; en fase 2 van a un PIO
    output wire [9:0]  LEDR
);

    // -----------------------------------------------------------------
    // Reset de encendido (power-on reset, POR)
    // Los 4 KEY se necesitan para el reproductor (play/pausa, stop,
    // anterior, siguiente), asi que el reset no sale de un boton:
    // un contador arranca en 0 al configurarse la FPGA (los registros de
    // Cyclone V aceptan valor inicial) y mantiene reset_n = 0 durante
    // 2^20 ciclos (~21 ms a 50 MHz).
    // -----------------------------------------------------------------
    reg [20:0] por_cnt = 21'd0;
    wire       por_done = por_cnt[20];

    always @(posedge CLOCK_50)
        if (!por_done)
            por_cnt <= por_cnt + 21'd1;

    // -----------------------------------------------------------------
    // Latido en hardware: LEDR[9] parpadea (~1,5 Hz) si la FPGA esta
    // configurada y CLOCK_50 corre, sin importar lo que haga el Nios.
    // -----------------------------------------------------------------
    reg [24:0] hb_cnt = 25'd0;
    always @(posedge CLOCK_50)
        hb_cnt <= hb_cnt + 25'd1;

    assign LEDR[9]   = hb_cnt[24];
    assign LEDR[8]   = por_done;   // encendido = reset liberado
    assign LEDR[7:0] = 8'd0;

    // -----------------------------------------------------------------
    // Sistema de Platform Designer
    // -----------------------------------------------------------------
    soc_system u_soc (
        .clk_clk       (CLOCK_50),
        .reset_reset_n (por_done)
    );

endmodule

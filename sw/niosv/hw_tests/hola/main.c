/*
 * Fase 1 -- prueba en tarjeta: "hola" por la JTAG UART.
 * Proyecto II CE-1113, Sistemas Empotrados (TEC)
 *
 * Verifica que el Nios V/m arranca desde la RAM on-chip inicializada en
 * la compilacion y que stdout (JTAG UART) llega a juart-terminal.
 * Imprime cada segundo para que el mensaje se vea aunque la terminal se
 * abra despues de configurar la FPGA.
 *
 * El tiempo se mide con el CSR mcycle de RISC-V (cuenta ciclos de reloj
 * a 50 MHz): no usa alt_*, IOWR/IORD ni usleep.
 */
#include <stdio.h>
#include <stdint.h>
#include "system.h"

static inline uint32_t ciclos(void)
{
    uint32_t c;
    __asm__ volatile ("csrr %0, mcycle" : "=r"(c));
    return c;
}

int main(void)
{
    printf("\nHola desde el Nios V/m en la DE1-SoC\n");
    printf("Compilado: %s %s\n", __DATE__, __TIME__);
    printf("NIOS_RAM_BASE  = 0x%08lx\n", (unsigned long)NIOS_RAM_BASE);
    printf("JTAG_UART_BASE = 0x%08lx\n", (unsigned long)JTAG_UART_BASE);

    const uint32_t un_segundo = 50000000u;   /* ciclos a 50 MHz */
    uint32_t t0 = ciclos();
    unsigned n = 0;

    for (;;) {
        /* La resta sin signo funciona aunque mcycle (32 bits bajos)
         * de la vuelta cada ~86 s. */
        if ((uint32_t)(ciclos() - t0) >= un_segundo) {
            t0 += un_segundo;
            printf("hola %u\n", n++);
        }
    }
    return 0;
}

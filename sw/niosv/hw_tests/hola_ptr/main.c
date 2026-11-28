/*
 * Fase 1 -- "hola" por la JTAG UART con punteros directos (sin printf/HAL).
 * Proyecto II CE-1113, Sistemas Empotrados (TEC)
 *
 * Separa hardware de software: si esto imprime bien, la JTAG UART, el
 * interconnect y la RAM funcionan, y cualquier falla de la version con
 * printf esta en el driver del HAL.
 *
 * Registros de la JTAG UART (Embedded Peripherals IP User Guide):
 *   +0 DATA    : [7:0] dato, [15] RVALID, [31:16] RAVAIL (bytes por leer)
 *   +4 CONTROL : [0] RE, [1] WE (habilitan IRQ), [8] RI, [9] WI,
 *                [10] AC (hubo actividad del host), [31:16] WSPACE
 *                (espacio libre en la FIFO de escritura)
 */
#include <stdint.h>
#include "system.h"

#define JUART_DATA    (*(volatile uint32_t *)(JTAG_UART_BASE + 0))
#define JUART_CONTROL (*(volatile uint32_t *)(JTAG_UART_BASE + 4))

/* Espera a que haya espacio en la FIFO (WSPACE > 0) y escribe un byte.
 * Si la terminal no esta abierta, la FIFO se llena y esto espera: el
 * texto no se pierde, sale cuando el host se conecta. */
static void juart_putc(char c)
{
    while ((JUART_CONTROL >> 16) == 0)
        ;
    JUART_DATA = (uint8_t)c;
}

static void juart_puts(const char *s)
{
    while (*s) {
        if (*s == '\n')
            juart_putc('\r');   /* retorno de carro para la consola de Windows */
        juart_putc(*s++);
    }
}

static void juart_putu(uint32_t v)          /* entero sin signo en decimal */
{
    char buf[11];
    int i = 10;
    buf[i] = '\0';
    do { buf[--i] = (char)('0' + v % 10u); v /= 10u; } while (v);
    juart_puts(&buf[i]);
}

static void juart_puthex(uint32_t v)        /* 0x%08x */
{
    static const char dig[] = "0123456789abcdef";
    juart_puts("0x");
    for (int s = 28; s >= 0; s -= 4)
        juart_putc(dig[(v >> s) & 0xFu]);
}

/* Tiempo en ciclos de 50 MHz: parte baja del registro mtime del
 * timer_sw_agent del Nios V (memoria, no CSR). El Nios V/m no implementa
 * el CSR mcycle: leerlo causa una excepcion de instruccion ilegal. */
#define MTIME_LO (*(volatile uint32_t *)(CPU_TIMER_SW_AGENT_BASE + 0))

static inline uint32_t ciclos(void)
{
    return MTIME_LO;
}

int main(void)
{
    juart_puts("\nHola desde el Nios V/m (punteros directos)\n");
    juart_puts("JTAG_UART_BASE = "); juart_puthex(JTAG_UART_BASE); juart_puts("\n");
    juart_puts("CONTROL        = "); juart_puthex(JUART_CONTROL);  juart_puts("\n");

    const uint32_t un_segundo = 50000000u;
    uint32_t t0 = ciclos();
    uint32_t n = 0;
    for (;;) {
        if ((uint32_t)(ciclos() - t0) >= un_segundo) {
            t0 += un_segundo;
            juart_puts("hola "); juart_putu(n++); juart_puts("\n");
        }
    }
    return 0;
}

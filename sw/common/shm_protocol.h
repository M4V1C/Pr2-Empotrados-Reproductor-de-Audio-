/*
 * shm_protocol.h - Contrato entre el HPS (Linux) y el Nios V (bare-metal) sobre la RAM compartida.
 *
 * Este archivo lo incluyen AMBOS lados y no depende de libc (solo stdint.h), asi que sirve
 * tal cual para el BSP del Nios V. Descripcion completa en docs/interfaz-hps-nios.md.
 *
 * Regla de oro: cada campo tiene UN SOLO escritor. No hay cerrojos entre procesadores.
 *
 * Todos los desplazamientos son en BYTES respecto a la base de la RAM compartida.
 * Las palabras son de 32 bits.
 */
#ifndef SHM_PROTOCOL_H
#define SHM_PROTOCOL_H

#include <stdint.h>

#define SHM_MAGIC      0x41505232u /* "APR2" */
#define SHM_VERSION    1u
#define SHM_SIZE_BYTES 0x10000u    /* 64 KiB */

/* ---- bloque de control (0x0000-0x00FF) ---- */
#define SHM_CTRL_BYTES   0x100u
#define SHM_OFF_MAGIC    0x00u /* HPS: se escribe AL FINAL de la inicializacion */
#define SHM_OFF_VERSION  0x04u /* HPS */
#define SHM_OFF_CMD_SEQ  0x08u /* HPS: numero de secuencia del comando (se escribe al final) */
#define SHM_OFF_CMD_CODE 0x0Cu /* HPS */
#define SHM_OFF_ARG0     0x10u /* HPS: LOAD = frecuencia de muestreo */
#define SHM_OFF_ARG1     0x14u /* HPS: LOAD = total de tramas */
#define SHM_OFF_ARG2     0x18u /* HPS: LOAD = numero de cancion (1..N) */
#define SHM_OFF_ACK      0x1Cu /* Nios: igual a CMD_SEQ cuando termino el comando */
#define SHM_OFF_RESULT   0x20u /* Nios: SHM_RES_* */
#define SHM_OFF_STATE    0x24u /* Nios: SHM_ST_* */
#define SHM_OFF_PLAYED   0x28u /* Nios: tramas reales reproducidas de la cancion */
#define SHM_OFF_FILTER   0x2Cu /* Nios: 0 bypass, 1 pasa-bajos, 2 pasa-banda, 3 eco */
#define SHM_OFF_VOLUME   0x30u /* Nios: 0-100 */
#define SHM_OFF_UNDERRUN 0x34u /* Nios: veces que el buffer estaba vacio reproduciendo */
#define SHM_OFF_RING_WR  0x38u /* HPS: contador de palabras escritas (sin mascara) */
#define SHM_OFF_RING_RD  0x3Cu /* Nios: contador de palabras leidas (sin mascara) */
#define SHM_OFF_EVT_WR   0x40u /* Nios: contador de eventos publicados */
#define SHM_OFF_EVT_RD   0x44u /* HPS: contador de eventos consumidos */
#define SHM_OFF_NIOS_MAGIC 0x48u /* Nios: SHM_MAGIC cuando ya atiende; el HPS lo espera tras init */
#define SHM_OFF_EVT_BASE 0x80u /* Nios: SHM_EVT_SLOTS palabras de evento */

/* ---- cola de eventos Nios -> HPS ---- */
#define SHM_EVT_SLOTS 16u /* potencia de 2 */
#define SHM_EVT_MASK  (SHM_EVT_SLOTS - 1u)
#define SHM_EVT(code, arg) ((uint32_t)(code) | ((uint32_t)(arg) << 8))
#define SHM_EVT_CODE(e)    ((e) & 0xFFu)
#define SHM_EVT_ARG(e)     ((e) >> 8)

enum {
    SHM_EVT_NONE = 0,
    SHM_EVT_BTN_PLAYPAUSE = 1,
    SHM_EVT_BTN_STOP = 2,
    SHM_EVT_BTN_NEXT = 3,
    SHM_EVT_BTN_PREV = 4
};

/* ---- buffer circular de tramas (0x8000-0xFFFF) ---- */
#define SHM_RING_OFFSET 0x8000u
#define SHM_RING_WORDS  8192u /* potencia de 2 */
#define SHM_RING_MASK   (SHM_RING_WORDS - 1u)
/* Cada palabra es una trama estereo: bits [15:0] = L, [31:16] = R (PCM 16 bit con signo). */

/* ---- comandos (HPS -> Nios) ---- */
enum {
    SHM_CMD_LOAD = 1, /* ARG0 = fs (8000/16000/44100), ARG1 = total de tramas, ARG2 = n.o de cancion */
    SHM_CMD_PLAY = 2,
    SHM_CMD_PAUSE = 3,
    SHM_CMD_STOP = 4
};

/* ---- resultados ---- */
enum {
    SHM_RES_OK = 0,
    SHM_RES_BAD_FS = 1,
    SHM_RES_BAD_STATE = 2,
    SHM_RES_BAD_CMD = 3
};

/* ---- estados del Nios ---- */
enum {
    SHM_ST_IDLE = 0,
    SHM_ST_READY = 1,
    SHM_ST_PLAYING = 2,
    SHM_ST_PAUSED = 3,
    SHM_ST_ENDED = 4
};

/* ---- acceso a la memoria ---- */

/* Barrera de memoria entre procesadores. __sync_synchronize genera 'dmb' en ARM y 'fence'
 * en RISC-V. Se puede redefinir antes de incluir este archivo. */
#ifndef SHM_BARRIER
#define SHM_BARRIER() __sync_synchronize()
#endif

static inline uint32_t shm_rd(volatile uint32_t *base, uint32_t off)
{
    return base[off >> 2];
}

static inline void shm_wr(volatile uint32_t *base, uint32_t off, uint32_t v)
{
    base[off >> 2] = v;
}

#endif /* SHM_PROTOCOL_H */

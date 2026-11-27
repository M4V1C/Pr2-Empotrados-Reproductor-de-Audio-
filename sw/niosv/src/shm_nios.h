/*
 * shm_nios.h - Lado Nios V del protocolo HPS <-> Nios V (ver docs/interfaz-hps-nios.md).
 *
 * Para quien escriba el main del Nios: esta libreria atiende los comandos del HPS y entrega
 * las tramas del buffer compartido. No toca el codec, ni los filtros, ni el audio_dsp: eso
 * es del main, que se entera de lo que debe hacer por los ganchos (hooks).
 *
 * Sin libc, sin HAL (alt_*) y sin IOWR/IORD: solo punteros volatile, como exige el enunciado.
 * Sin multiplicaciones ni divisiones (el Nios V/m no tiene multiplicador).
 *
 * Esquema del main (lo mismo que hace el simulador de sw/hps/tests/test_comm.c):
 *
 *     shm_nios_init(&n, (volatile uint32_t *)SHM_BASE, &hooks);   // SHM_BASE de system.h
 *     for (;;) {
 *         shm_nios_service(&n);                       // atiende comandos del HPS
 *         leer_switches_y_adc();                      // shm_nios_set_filter / set_volume
 *         if (codec_tiene_espacio()) {
 *             uint32_t trama;
 *             int r = shm_nios_pop_frame(&n, &trama); // 1 = trama, 0 = vacio, -1 = no suena
 *             if (r == 1)      escribir_al_codec(filtrar(trama));
 *             else if (r == 0) escribir_al_codec(0);  // silencio para no perder el ritmo
 *         }
 *     }
 *     // en la ISR de botones: shm_nios_push_event(&n, SHM_EVT_BTN_NEXT, 0);
 */
#ifndef SHM_NIOS_H
#define SHM_NIOS_H

#include <stddef.h>
#include <stdint.h>

#include "../../common/shm_protocol.h"

/* Ganchos opcionales (pueden ser NULL). Se llaman desde shm_nios_service(). */
typedef struct {
    /* Cancion nueva: configurar FS y TRACK de audio_dsp, reiniciar filtros (filters_sw_init,
     * HIST_CLR) y el contador de tiempo. El buffer ya fue vaciado. */
    void (*on_load)(void *ctx, uint32_t fs, uint32_t total_frames, uint32_t track_no);
    void (*on_play)(void *ctx);  /* arrancar el contador de tiempo (TIME_EN) */
    void (*on_pause)(void *ctx); /* detener el contador de tiempo */
    void (*on_stop)(void *ctx);  /* detener y poner a cero el contador de tiempo */
    void *ctx;
} shm_nios_hooks_t;

typedef struct {
    volatile uint32_t *base;
    shm_nios_hooks_t hooks;
    uint32_t total_frames;
    int ready;
} shm_nios_t;

/* 'base' es la direccion de la RAM compartida (SHM_BASE en system.h). 'hooks' puede ser NULL. */
void shm_nios_init(shm_nios_t *n, volatile uint32_t *base, const shm_nios_hooks_t *hooks);

/* Llamar en cada vuelta del lazo principal (debe ser mas frecuente que ~1 ms).
 * Espera el MAGIC del HPS, se reinicia si el HPS se reinicia y ejecuta el comando pendiente. */
void shm_nios_service(shm_nios_t *n);

/* Saca la siguiente trama del buffer, solo si el estado es PLAYING.
 *   1  -> *frame tiene una trama valida ([15:0]=L, [31:16]=R)
 *   0  -> buffer vacio estando en PLAYING (underrun): enviar silencio
 *  -1  -> no esta reproduciendo (IDLE, READY, PAUSED, ENDED o protocolo sin iniciar)
 * Al consumir la ultima trama de la cancion pasa solo a ENDED. */
int shm_nios_pop_frame(shm_nios_t *n, uint32_t *frame);

uint32_t shm_nios_state(const shm_nios_t *n);

/* Estado visible para el HPS. */
void shm_nios_set_filter(shm_nios_t *n, uint32_t filter);
void shm_nios_set_volume(shm_nios_t *n, uint32_t volume);

/* Publica un evento para el HPS (por ejemplo desde la ISR de botones).
 * Devuelve 1 si quedo en la cola, 0 si estaba llena (el evento se descarta). */
int shm_nios_push_event(shm_nios_t *n, uint32_t code, uint32_t arg);

#endif /* SHM_NIOS_H */

/*
 * shm_hps.h - Lado HPS (Linux) del protocolo HPS <-> Nios V (ver docs/interfaz-hps-nios.md).
 *
 * Escribe comandos y muestras en la RAM compartida y lee el estado y los eventos del Nios.
 * Todas las funciones se llaman desde UN solo hilo (el del reproductor); no hay cerrojos.
 */
#ifndef SHM_HPS_H
#define SHM_HPS_H

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>

#include "../common/shm_protocol.h"

typedef struct {
    volatile uint32_t *base;
    uint32_t seq;        /* ultimo numero de secuencia usado */
    uint32_t timeout_ms; /* espera maxima del ACK de un comando (por defecto 100) */
} shm_hps_t;

/* Mapea 'len' bytes de la memoria fisica 'phys' a traves de 'dev' ("/dev/mem" o un /dev/uioN).
 * Devuelve NULL si falla. En la placa 'phys' sale del mapa del HPS: base del puente ligero
 * (0xFF200000) mas la direccion de la RAM compartida en Platform Designer. */
volatile uint32_t *shm_hps_map(const char *dev, off_t phys, size_t len);
void shm_hps_unmap(volatile uint32_t *base, size_t len);

/* Reinicia el protocolo: borra el bloque de control y escribe MAGIC al final.
 * Bloquea ~2 ms para que el Nios note el reinicio. */
void shm_hps_init(shm_hps_t *s, volatile uint32_t *base);

/* Espera hasta 'timeout_ms' a que el Nios confirme que ya atiende el protocolo.
 * Llamar despues de shm_hps_init y antes del primer comando (el Nios puede arrancar mas
 * lento que Linux). 0 si esta listo, -1 si vencio el tiempo. */
int shm_hps_wait_nios(const shm_hps_t *s, uint32_t timeout_ms);

/* Envia un comando y espera el ACK. Devuelve SHM_RES_* (>= 0) o -1 si el Nios no respondio.
 * Tras un -1 lo mas seguro es repetir shm_hps_init y volver a cargar la cancion. */
int shm_hps_command(shm_hps_t *s, uint32_t code, uint32_t a0, uint32_t a1, uint32_t a2);

/* Buffer circular de tramas (el HPS es el unico que escribe RING_WR). */
uint32_t shm_hps_ring_free(const shm_hps_t *s);
/* Escribe hasta 'n' tramas; devuelve cuantas entraron (nunca mas que las libres). */
size_t shm_hps_ring_write(shm_hps_t *s, const uint32_t *frames, size_t n);

/* Estado publicado por el Nios. */
uint32_t shm_hps_state(const shm_hps_t *s);
uint32_t shm_hps_frames_played(const shm_hps_t *s);
uint32_t shm_hps_filter(const shm_hps_t *s);
uint32_t shm_hps_volume(const shm_hps_t *s);
uint32_t shm_hps_underruns(const shm_hps_t *s);

/* Saca un evento de la cola (botones). Devuelve 1 si habia uno, 0 si no. */
int shm_hps_event_pop(shm_hps_t *s, uint32_t *evt);

#endif /* SHM_HPS_H */

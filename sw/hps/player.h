/*
 * player.h - Reproductor del HPS: lista de reproduccion, estado y control.
 *
 * Es el "cerebro": decide que cancion suena, atiende play/pausa/stop/siguiente/anterior,
 * mantiene lleno el buffer con track_read() y pasa a la siguiente cancion al terminar.
 * No sabe nada del transporte: habla con el Nios V por una interfaz de salida abstracta
 * (player_sink_t). shm_sink.c la implementa sobre el protocolo de memoria compartida.
 *
 * Hilos: TODAS las funciones player_* se llaman desde el mismo hilo (el que invoca
 * player_tick cada ~10 ms). Los botones llegan como eventos del sink, no por otro hilo.
 */
#ifndef PLAYER_H
#define PLAYER_H

#include <stddef.h>
#include <stdint.h>

#include "../storage/playlist.h"
#include "../storage/track_reader.h"

#define PLAYER_BLOCK_FRAMES 1024u

/* Interfaz de salida: todo lo que el reproductor necesita del Nios V. */
typedef struct {
    /* Carga una cancion (vacia el buffer, configura fs). 0 si ok. */
    int (*load)(void *ctx, uint32_t fs, uint32_t total_frames, uint32_t track_no);
    int (*play)(void *ctx);
    int (*pause)(void *ctx);
    int (*stop)(void *ctx);
    uint32_t (*free_frames)(void *ctx);                           /* huecos en el buffer */
    void (*write)(void *ctx, const uint32_t *frames, size_t n);   /* n <= free_frames */
    uint32_t (*state)(void *ctx);                                 /* SHM_ST_* del Nios */
    int (*poll_event)(void *ctx, uint32_t *evt);                  /* 1 si hay evento */
    void *ctx;
} player_sink_t;

typedef enum { PLAYER_STOPPED = 0, PLAYER_PLAYING, PLAYER_PAUSED } player_state_t;

typedef struct {
    const playlist_t *pl;
    player_sink_t sink;
    player_state_t state;
    size_t index;          /* cancion actual (0..count-1) */
    track_reader_t reader;
    int reader_open;
    int reader_done;       /* ya se entregaron todas las tramas (o hubo error) */
    uint32_t block[PLAYER_BLOCK_FRAMES];
} player_t;

/* Devuelve 0 si ok, -1 si la lista esta vacia. El player queda en STOPPED en la cancion 0. */
int player_init(player_t *p, const playlist_t *pl, const player_sink_t *sink);

/* Acciones del usuario (botones, UI). */
void player_play_pause(player_t *p); /* STOPPED->PLAYING, PLAYING->PAUSED, PAUSED->PLAYING */
void player_stop(player_t *p);
/* Con musica (sonando o en pausa) cargan la otra cancion y empiezan a sonar; en STOPPED solo
 * mueven la seleccion. Al pasar de la ultima a la primera (y viceversa) dan la vuelta. */
void player_next(player_t *p);
void player_prev(player_t *p);

/* Llamar cada ~10 ms: atiende eventos del Nios, rellena el buffer y avanza al terminar. */
void player_tick(player_t *p);

player_state_t player_state(const player_t *p);
size_t player_index(const player_t *p);
const track_t *player_track(const player_t *p); /* cancion actual (metadatos para la UI) */

void player_close(player_t *p); /* cierra el archivo abierto */

#endif /* PLAYER_H */

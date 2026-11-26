/*
 * shm_sink.h - Implementa la interfaz de salida del reproductor sobre la RAM compartida:
 * conecta player.c con shm_hps.c.
 */
#ifndef SHM_SINK_H
#define SHM_SINK_H

#include "player.h"
#include "shm_hps.h"

/* 'h' debe haberse iniciado con shm_hps_init y vivir mas que el player. */
void shm_sink_init(player_sink_t *sink, shm_hps_t *h);

#endif /* SHM_SINK_H */

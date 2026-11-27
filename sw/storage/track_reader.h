/*
 * track_reader.h - Lectura de las muestras de audio de una cancion WAV.
 *
 * Entrega tramas estereo empaquetadas en palabras de 32 bits:
 *     bits [15:0]  = canal izquierdo (PCM 16 bit con signo)
 *     bits [31:16] = canal derecho
 * Es el mismo formato que SAMPLE_IN de audio_dsp y que una trama estereo de un WAV.
 * Los WAV mono se duplican (L = R), asi que el consumidor siempre recibe estereo.
 *
 * No sabe nada del transporte (buffer circular, mailbox): quien conecte con el Nios V
 * solo llama a track_read() y copia el resultado donde corresponda.
 * Sin malloc; el unico estado es el track_reader_t del llamador.
 */
#ifndef TRACK_READER_H
#define TRACK_READER_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include "wav_meta.h"

#define TRACK_ERR_NONE      0
#define TRACK_ERR_TRUNCATED 1 /* el archivo termino antes de lo que decia la cabecera */
#define TRACK_ERR_IO        2 /* fallo de lectura */

typedef struct {
    FILE *f;
    uint32_t total_frames; /* tramas de la cancion (solo lectura) */
    uint32_t remaining;    /* tramas que faltan por entregar (solo lectura) */
    uint32_t data_offset;
    uint16_t channels;
    uint16_t frame_bytes;  /* bytes por trama en el archivo: 2 (mono) o 4 (estereo) */
    int error;             /* TRACK_ERR_*; si no es 0 la cancion se da por terminada */
} track_reader_t;

/* Abre 'path' y se posiciona al inicio de las muestras. 'info' viene de wav_parse().
 * Devuelve 0 si todo bien, -1 si no se pudo abrir o el formato no es PCM 16 bit. */
int track_open(track_reader_t *r, const char *path, const wav_info_t *info);

/* Lee hasta 'max_frames' tramas en 'dst'. Devuelve las tramas escritas;
 * 0 significa fin de la cancion (o error: revisar r->error). */
size_t track_read(track_reader_t *r, uint32_t *dst, size_t max_frames);

/* Salta a la trama 'frame' (0 = inicio) y limpia el error. 0 si ok, -1 si esta fuera de rango. */
int track_seek(track_reader_t *r, uint32_t frame);

void track_close(track_reader_t *r);

#endif /* TRACK_READER_H */

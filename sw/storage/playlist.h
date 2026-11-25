/*
 * playlist.h - Escaneo de un directorio (punto de montaje de la SD) y lista
 * de canciones. Memoria estatica: sin malloc, tamano fijo conocido en compilacion.
 */
#ifndef PLAYLIST_H
#define PLAYLIST_H

#include <stddef.h>

#include "wav_meta.h"

#define PLAYLIST_MAX      32
#define PLAYLIST_PATH_MAX 256

typedef struct {
    char path[PLAYLIST_PATH_MAX];
    wav_info_t info; /* title/artist nunca quedan vacios (ver respaldo) */
} track_t;

typedef struct {
    track_t tracks[PLAYLIST_MAX];
    size_t count;
} playlist_t;

/*
 * Busca *.wav (sin distinguir mayusculas) en 'dir', ordena por nombre y parsea
 * cada archivo. Descarta los que no sean WAV PCM 16 bit soportados.
 * Si falta LIST/INFO usa el nombre: "Artista - Titulo.wav" o solo "Titulo.wav".
 * Devuelve la cantidad de canciones, o -1 si no se pudo abrir el directorio.
 */
int playlist_scan(playlist_t *pl, const char *dir);

#endif /* PLAYLIST_H */

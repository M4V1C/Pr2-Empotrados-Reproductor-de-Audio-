/*
 * main_read - Prueba de aceptacion de la lectura de muestras.
 * Recorre una o todas las canciones de un directorio con track_read(), verifica que se
 * entreguen todas las tramas y mide el rendimiento de lectura.
 *
 * Uso: main_read <directorio> [numero_de_cancion]
 * Sale con 0 si todas las canciones leidas estan completas, 1 si alguna falla.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "playlist.h"
#include "track_reader.h"

#define BLOCK_FRAMES 1024u

static playlist_t pl;                /* estatico: no consume pila */
static uint32_t block[BLOCK_FRAMES]; /* 4 KB */

static double now_ms(void)
{
    struct timespec t;

    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}

/* Devuelve 0 si la cancion se leyo completa. */
static int leer_cancion(size_t idx)
{
    const track_t *t = &pl.tracks[idx];
    track_reader_t r;
    uint32_t total = 0;
    size_t got;
    double t0, ms;

    if (track_open(&r, t->path, &t->info) != 0) {
        printf("%02zu | %-18s | NO SE PUDO ABRIR\n", idx + 1, t->info.title);
        return 1;
    }
    t0 = now_ms();
    while ((got = track_read(&r, block, BLOCK_FRAMES)) > 0)
        total += (uint32_t)got;
    ms = now_ms() - t0;
    if (ms < 0.001)
        ms = 0.001;

    printf("%02zu | %-18s | %8u/%-8u tramas | %6.1f MB/s | %s\n",
           idx + 1, t->info.title, total, r.total_frames,
           (double)total * r.frame_bytes / 1048576.0 / (ms / 1000.0),
           (total == r.total_frames && r.error == TRACK_ERR_NONE) ? "OK" : "FALLO");
    {
        int fallo = !(total == r.total_frames && r.error == TRACK_ERR_NONE);

        track_close(&r);
        return fallo;
    }
}

int main(int argc, char **argv)
{
    const char *dir = argc > 1 ? argv[1] : ".";
    int n = playlist_scan(&pl, dir);
    int fallos = 0;
    size_t i;

    if (n < 0) {
        fprintf(stderr, "No se pudo abrir '%s'\n", dir);
        return 1;
    }
    if (argc > 2) {
        long k = strtol(argv[2], NULL, 10);

        if (k < 1 || k > n) {
            fprintf(stderr, "Cancion %ld fuera de rango (1..%d)\n", k, n);
            return 1;
        }
        return leer_cancion((size_t)k - 1) ? 1 : 0;
    }
    for (i = 0; i < pl.count; i++)
        fallos += leer_cancion(i);
    printf("%d cancion(es), %d con fallo\n", n, fallos);
    return fallos ? 1 : 0;
}

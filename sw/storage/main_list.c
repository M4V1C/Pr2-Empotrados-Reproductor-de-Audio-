/*
 * main_list - Imprime la playlist de un directorio (punto de montaje de la SD).
 * Uso: main_list <directorio>
 */
#include <stdio.h>

#include "playlist.h"

static playlist_t pl; /* estatico: no consume pila */

int main(int argc, char **argv)
{
    const char *dir = argc > 1 ? argv[1] : ".";
    int n = playlist_scan(&pl, dir);
    size_t i;

    if (n < 0) {
        fprintf(stderr, "No se pudo abrir '%s'\n", dir);
        return 1;
    }
    printf("%d cancion(es) en %s\n", n, dir);
    for (i = 0; i < pl.count; i++) {
        const wav_info_t *w = &pl.tracks[i].info;
        uint32_t s = (w->duration_ms + 500) / 1000;

        printf("%02zu | %-18s | %-15s | %-16s | %02u:%02u | %5u Hz %uch\n",
               i + 1, w->title, w->artist, w->album[0] ? w->album : "-",
               s / 60, s % 60, w->sample_rate, w->channels);
    }
    return 0;
}

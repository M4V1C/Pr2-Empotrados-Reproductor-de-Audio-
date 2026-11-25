#define _GNU_SOURCE /* memmem */
#include "playlist.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

static int is_wav_name(const char *name)
{
    size_t n = strlen(name);

    return n > 4 && strcasecmp(name + n - 4, ".wav") == 0;
}

static int cmp_track(const void *a, const void *b)
{
    return strcasecmp(((const track_t *)a)->path, ((const track_t *)b)->path);
}

static void copy_tag(char *dst, const char *src, size_t len)
{
    if (len >= WAV_TAG_MAX)
        len = WAV_TAG_MAX - 1;
    memcpy(dst, src, len);
    dst[len] = '\0';
}

/* Respaldo cuando el WAV no trae LIST/INFO: usa el nombre de archivo. */
static void fill_from_filename(track_t *t)
{
    const char *base = strrchr(t->path, '/');
    const char *sep;
    size_t len;

    base = base ? base + 1 : t->path;
    len = strlen(base) - 4; /* sin ".wav" */
    sep = memmem(base, len, " - ", 3);

    if (t->info.title[0] == '\0') {
        if (sep && t->info.artist[0] == '\0') {
            copy_tag(t->info.artist, base, (size_t)(sep - base));
            copy_tag(t->info.title, sep + 3, len - (size_t)(sep + 3 - base));
        } else {
            copy_tag(t->info.title, base, len);
        }
    }
    if (t->info.artist[0] == '\0')
        copy_tag(t->info.artist, "Desconocido", sizeof("Desconocido") - 1);
}

int playlist_scan(playlist_t *pl, const char *dir)
{
    DIR *d = opendir(dir);
    struct dirent *e;
    size_t n = 0, kept = 0, i;

    pl->count = 0;
    if (!d)
        return -1;

    while ((e = readdir(d)) != NULL && n < PLAYLIST_MAX) {
        int w;

        if (!is_wav_name(e->d_name))
            continue;
        w = snprintf(pl->tracks[n].path, PLAYLIST_PATH_MAX, "%s/%s", dir, e->d_name);
        if (w < 0 || w >= PLAYLIST_PATH_MAX)
            continue; /* ruta demasiado larga */
        n++;
    }
    closedir(d);

    qsort(pl->tracks, n, sizeof pl->tracks[0], cmp_track);

    for (i = 0; i < n; i++) {
        track_t *t = &pl->tracks[i];

        if (wav_parse_file(t->path, &t->info) != WAV_OK)
            continue; /* no es WAV valido/soportado: se descarta */
        fill_from_filename(t);
        if (kept != i)
            pl->tracks[kept] = *t;
        kept++;
    }
    pl->count = kept;
    return (int)kept;
}

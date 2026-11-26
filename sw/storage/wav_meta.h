/*
 * wav_meta.h - Parser de cabecera WAV (RIFF/PCM) y metadatos LIST/INFO.
 *
 * Solo depende de stdio, de modo que corre igual en el PC, en QEMU y en el
 * HPS (Linux). No lee las muestras de audio: solo recorre los chunks.
 *
 * Metadatos (chunk LIST de tipo INFO):
 *   INAM = titulo, IART = artista, IPRD = album.
 * La duracion se calcula con data_size / (rate * canales * bytes_por_muestra).
 */
#ifndef WAV_META_H
#define WAV_META_H

#include <stdint.h>
#include <stdio.h>

#define WAV_TAG_MAX 64 /* bytes por etiqueta, incluye el NUL final */

typedef enum {
    WAV_OK = 0,
    WAV_ERR_IO,          /* fallo de lectura/posicionamiento */
    WAV_ERR_FORMAT,      /* no es RIFF/WAVE o faltan chunks fmt/data */
    WAV_ERR_UNSUPPORTED  /* no es PCM 16 bit, 1-2 canales, 8/16/44.1 kHz */
} wav_status_t;

typedef struct {
    uint32_t sample_rate;     /* Hz */
    uint16_t channels;        /* 1 o 2 */
    uint16_t bits_per_sample; /* siempre 16 si el parseo fue exitoso */
    uint32_t data_offset;     /* byte donde empiezan las muestras */
    uint32_t data_size;       /* bytes de audio (acotado al tamano del archivo) */
    uint32_t duration_ms;
    char title[WAV_TAG_MAX];  /* vacios si el archivo no trae LIST/INFO */
    char artist[WAV_TAG_MAX];
    char album[WAV_TAG_MAX];
} wav_info_t;

/* Parsea el archivo abierto en modo lectura binaria. 'out' se pone a cero. */
wav_status_t wav_parse(FILE *f, wav_info_t *out);

/* Abre 'path', parsea y cierra. */
wav_status_t wav_parse_file(const char *path, wav_info_t *out);

#endif /* WAV_META_H */

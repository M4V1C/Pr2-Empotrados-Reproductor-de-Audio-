#define _FILE_OFFSET_BITS 64
#define _DEFAULT_SOURCE
#include "wav_meta.h"

#include <stdbool.h>
#include <string.h>
#include <sys/types.h>

static uint16_t le16(const uint8_t *p)
{
    return (uint16_t)(p[0] | (p[1] << 8));
}

static uint32_t le32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static bool rate_supported(uint32_t r)
{
    return r == 8000u || r == 16000u || r == 44100u;
}

/* Lee un subchunk de texto a 'dst' (max bytes), recortando NUL y espacios finales. */
static void read_tag(FILE *f, char *dst, uint32_t size)
{
    size_t n = size < (WAV_TAG_MAX - 1) ? size : (WAV_TAG_MAX - 1);
    size_t got = fread(dst, 1, n, f);

    dst[got] = '\0';
    got = strlen(dst); /* corta en el primer NUL (cadenas rellenadas) */
    while (got > 0 && (dst[got - 1] == ' ' || dst[got - 1] == '\r' || dst[got - 1] == '\n'))
        dst[--got] = '\0';
}

/* Recorre un chunk LIST; solo procesa el tipo INFO. 'size' ya esta validado. */
static wav_status_t parse_list(FILE *f, off_t body, uint32_t size, wav_info_t *out)
{
    uint8_t type[4];
    off_t pos = body + 4;
    off_t end = body + (off_t)size;

    if (size < 4)
        return WAV_OK;
    if (fseeko(f, body, SEEK_SET) != 0 || fread(type, 1, 4, f) != 4)
        return WAV_ERR_IO;
    if (memcmp(type, "INFO", 4) != 0)
        return WAV_OK;

    while (pos + 8 <= end) {
        uint8_t h[8];
        uint32_t sz;
        char *dst = NULL;

        if (fseeko(f, pos, SEEK_SET) != 0 || fread(h, 1, 8, f) != 8)
            return WAV_ERR_IO;
        sz = le32(h + 4);
        if ((off_t)sz > end - (pos + 8))
            break; /* subchunk corrupto: ignora el resto */

        if (memcmp(h, "INAM", 4) == 0)
            dst = out->title;
        else if (memcmp(h, "IART", 4) == 0)
            dst = out->artist;
        else if (memcmp(h, "IPRD", 4) == 0)
            dst = out->album;

        if (dst)
            read_tag(f, dst, sz);
        pos += 8 + (off_t)sz + (sz & 1u); /* subchunks alineados a byte par */
    }
    return WAV_OK;
}

wav_status_t wav_parse(FILE *f, wav_info_t *out)
{
    uint8_t hdr[12];
    off_t fsize, pos = 12;
    bool have_fmt = false, have_data = false;

    memset(out, 0, sizeof *out);

    if (fseeko(f, 0, SEEK_END) != 0)
        return WAV_ERR_IO;
    fsize = ftello(f);
    if (fsize < 0 || fseeko(f, 0, SEEK_SET) != 0)
        return WAV_ERR_IO;

    if (fread(hdr, 1, 12, f) != 12 ||
        memcmp(hdr, "RIFF", 4) != 0 || memcmp(hdr + 8, "WAVE", 4) != 0)
        return WAV_ERR_FORMAT;

    while (pos + 8 <= fsize) {
        uint8_t ch[8];
        uint32_t size;
        off_t body, avail;

        if (fseeko(f, pos, SEEK_SET) != 0 || fread(ch, 1, 8, f) != 8)
            return WAV_ERR_IO;
        size = le32(ch + 4);
        body = pos + 8;
        avail = fsize - body;

        if (memcmp(ch, "data", 4) == 0) {
            if ((off_t)size > avail)
                size = (uint32_t)avail; /* cabecera con tamano mayor al real */
            out->data_offset = (uint32_t)body;
            out->data_size = size;
            have_data = true;
        } else if ((off_t)size > avail) {
            break; /* chunk no-data truncado */
        } else if (memcmp(ch, "fmt ", 4) == 0) {
            uint8_t b[16];

            if (size < 16)
                return WAV_ERR_FORMAT;
            if (fread(b, 1, 16, f) != 16)
                return WAV_ERR_IO;
            out->channels = le16(b + 2);
            out->sample_rate = le32(b + 4);
            out->bits_per_sample = le16(b + 14);
            if (le16(b) != 1 || out->bits_per_sample != 16 ||
                out->channels < 1 || out->channels > 2 ||
                !rate_supported(out->sample_rate))
                return WAV_ERR_UNSUPPORTED;
            have_fmt = true;
        } else if (memcmp(ch, "LIST", 4) == 0) {
            wav_status_t st = parse_list(f, body, size, out);

            if (st != WAV_OK)
                return st;
        }
        pos = body + (off_t)size + (size & 1u); /* chunks alineados a byte par */
    }

    if (!have_fmt || !have_data)
        return WAV_ERR_FORMAT;

    out->duration_ms = (uint32_t)(((uint64_t)out->data_size * 1000u) /
                                  ((uint64_t)out->sample_rate * out->channels * 2u));
    return WAV_OK;
}

wav_status_t wav_parse_file(const char *path, wav_info_t *out)
{
    FILE *f = fopen(path, "rb");
    wav_status_t st;

    if (!f) {
        memset(out, 0, sizeof *out);
        return WAV_ERR_IO;
    }
    st = wav_parse(f, out);
    fclose(f);
    return st;
}

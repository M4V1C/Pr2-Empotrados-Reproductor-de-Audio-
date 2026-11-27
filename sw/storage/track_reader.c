#define _FILE_OFFSET_BITS 64
#define _DEFAULT_SOURCE
#include "track_reader.h"

#include <string.h>
#include <sys/types.h>

#define CHUNK_FRAMES 256u /* tramas por lectura de stdio: buffer de 1 KB en la pila */

static uint32_t le16(const uint8_t *p)
{
    return (uint32_t)(p[0] | (p[1] << 8));
}

static uint32_t le32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

int track_open(track_reader_t *r, const char *path, const wav_info_t *info)
{
    memset(r, 0, sizeof *r);
    if (!path || !info || info->bits_per_sample != 16 ||
        info->channels < 1 || info->channels > 2)
        return -1;

    r->f = fopen(path, "rb");
    if (!r->f)
        return -1;

    r->channels = info->channels;
    r->frame_bytes = (uint16_t)(info->channels * 2u);
    r->data_offset = info->data_offset;
    r->total_frames = info->data_size / r->frame_bytes;

    if (track_seek(r, 0) != 0) {
        fclose(r->f);
        memset(r, 0, sizeof *r);
        return -1;
    }
    return 0;
}

size_t track_read(track_reader_t *r, uint32_t *dst, size_t max_frames)
{
    size_t done = 0;

    if (!r || !r->f || !dst)
        return 0;

    while (done < max_frames && r->remaining > 0) {
        uint8_t buf[CHUNK_FRAMES * 4u];
        size_t want = max_frames - done;
        size_t got, i;

        if (want > CHUNK_FRAMES)
            want = CHUNK_FRAMES;
        if (want > r->remaining)
            want = r->remaining;

        got = fread(buf, r->frame_bytes, want, r->f);
        for (i = 0; i < got; i++) {
            if (r->channels == 2) {
                dst[done + i] = le32(buf + 4 * i);
            } else {
                uint32_t s = le16(buf + 2 * i);

                dst[done + i] = s | (s << 16); /* mono: L = R */
            }
        }
        done += got;
        r->remaining -= (uint32_t)got;

        if (got < want) {
            r->error = ferror(r->f) ? TRACK_ERR_IO : TRACK_ERR_TRUNCATED;
            r->remaining = 0;
            break;
        }
    }
    return done;
}

int track_seek(track_reader_t *r, uint32_t frame)
{
    if (!r || !r->f || frame > r->total_frames)
        return -1;
    if (fseeko(r->f, (off_t)r->data_offset + (off_t)frame * r->frame_bytes, SEEK_SET) != 0)
        return -1;
    r->remaining = r->total_frames - frame;
    r->error = TRACK_ERR_NONE;
    return 0;
}

void track_close(track_reader_t *r)
{
    if (r && r->f)
        fclose(r->f);
    if (r)
        memset(r, 0, sizeof *r);
}

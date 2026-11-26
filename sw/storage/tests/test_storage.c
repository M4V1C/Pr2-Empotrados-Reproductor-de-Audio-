/*
 * Pruebas unitarias del parser WAV y del escaneo de playlist.
 * Genera WAV sinteticos en un directorio temporal; no necesita la SD.
 */
#define _DEFAULT_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../playlist.h"
#include "../wav_meta.h"

static int failures, checks;

#define CHECK(cond)                                                          \
    do {                                                                     \
        checks++;                                                            \
        if (!(cond)) {                                                       \
            failures++;                                                      \
            fprintf(stderr, "FALLO %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                    \
    } while (0)

enum { LIST_NONE, LIST_BEFORE_DATA, LIST_AFTER_DATA };

typedef struct {
    uint32_t rate;
    uint16_t channels, bits, format;
    uint32_t frames;
    int list_pos;
    const char *title, *artist, *album;
    uint32_t claim_extra; /* bytes extra declarados en 'data' y no escritos */
} spec_t;

static void w16(FILE *f, uint16_t v) { fputc(v & 255, f); fputc(v >> 8, f); }
static void w32(FILE *f, uint32_t v) { w16(f, v & 0xFFFF); w16(f, (uint16_t)(v >> 16)); }
static void wid(FILE *f, const char *id) { fwrite(id, 1, 4, f); }

static uint32_t sub_size(const char *s)
{
    uint32_t n;

    if (!s)
        return 0;
    n = (uint32_t)strlen(s) + 1;
    return 8 + n + (n & 1);
}

static void write_sub(FILE *f, const char *id, const char *s)
{
    uint32_t n;

    if (!s)
        return;
    n = (uint32_t)strlen(s) + 1;
    wid(f, id);
    w32(f, n);
    fwrite(s, 1, n, f);
    if (n & 1)
        fputc(0, f);
}

static void write_list(FILE *f, const spec_t *s)
{
    uint32_t sz = 4 + sub_size(s->title) + sub_size(s->artist) + sub_size(s->album);

    wid(f, "LIST");
    w32(f, sz);
    wid(f, "INFO");
    write_sub(f, "INAM", s->title);
    write_sub(f, "IART", s->artist);
    write_sub(f, "IPRD", s->album);
}

static void write_wav(const char *path, const spec_t *s)
{
    FILE *f = fopen(path, "wb");
    uint32_t bytes = s->frames * s->channels * (s->bits / 8u);
    uint32_t i;
    long end;

    if (!f) {
        perror(path);
        exit(2);
    }
    wid(f, "RIFF"); w32(f, 0); wid(f, "WAVE");
    wid(f, "fmt "); w32(f, 16);
    w16(f, s->format); w16(f, s->channels); w32(f, s->rate);
    w32(f, s->rate * s->channels * (s->bits / 8u));
    w16(f, (uint16_t)(s->channels * (s->bits / 8u))); w16(f, s->bits);

    if (s->list_pos == LIST_BEFORE_DATA)
        write_list(f, s);
    wid(f, "data"); w32(f, bytes + s->claim_extra);
    for (i = 0; i < bytes; i++)
        fputc(0, f);
    if (bytes & 1)
        fputc(0, f);
    if (s->list_pos == LIST_AFTER_DATA)
        write_list(f, s);

    end = ftell(f);
    fseek(f, 4, SEEK_SET);
    w32(f, (uint32_t)(end - 8));
    fclose(f);
}

static spec_t base_spec(void)
{
    spec_t s;

    memset(&s, 0, sizeof s);
    s.rate = 8000; s.channels = 1; s.bits = 16; s.format = 1; s.frames = 16000;
    return s;
}

static void test_info_before_data(const char *dir)
{
    char p[1024];
    wav_info_t i;
    spec_t s = base_spec();

    s.list_pos = LIST_BEFORE_DATA;
    s.title = "Hola"; s.artist = "Yo"; s.album = "Alb"; /* longitudes impares/pares: relleno */
    snprintf(p, sizeof p, "%s/a.wav", dir);
    write_wav(p, &s);

    CHECK(wav_parse_file(p, &i) == WAV_OK);
    CHECK(strcmp(i.title, "Hola") == 0);
    CHECK(strcmp(i.artist, "Yo") == 0);
    CHECK(strcmp(i.album, "Alb") == 0);
    CHECK(i.sample_rate == 8000 && i.channels == 1 && i.bits_per_sample == 16);
    CHECK(i.data_size == 32000);
    CHECK(i.duration_ms == 2000);
}

static void test_info_after_data_stereo(const char *dir)
{
    char p[1024];
    wav_info_t i;
    spec_t s = base_spec();

    s.rate = 44100; s.channels = 2; s.frames = 44100;
    s.list_pos = LIST_AFTER_DATA;
    s.title = "Final"; s.artist = "Banda"; s.album = "Disco";
    snprintf(p, sizeof p, "%s/b.wav", dir);
    write_wav(p, &s);

    CHECK(wav_parse_file(p, &i) == WAV_OK);
    CHECK(strcmp(i.title, "Final") == 0);
    CHECK(strcmp(i.album, "Disco") == 0);
    CHECK(i.duration_ms == 1000);
}

static void test_no_info(const char *dir)
{
    char p[1024];
    wav_info_t i;
    spec_t s = base_spec();

    snprintf(p, sizeof p, "%s/c.wav", dir);
    write_wav(p, &s);
    CHECK(wav_parse_file(p, &i) == WAV_OK);
    CHECK(i.title[0] == '\0' && i.artist[0] == '\0' && i.album[0] == '\0');
}

static void test_unsupported(const char *dir)
{
    char p[1024];
    wav_info_t i;
    spec_t s = base_spec();

    snprintf(p, sizeof p, "%s/d.wav", dir);

    s.bits = 8;
    write_wav(p, &s);
    CHECK(wav_parse_file(p, &i) == WAV_ERR_UNSUPPORTED);

    s = base_spec(); s.rate = 22050;
    write_wav(p, &s);
    CHECK(wav_parse_file(p, &i) == WAV_ERR_UNSUPPORTED);

    s = base_spec(); s.format = 3; /* float */
    write_wav(p, &s);
    CHECK(wav_parse_file(p, &i) == WAV_ERR_UNSUPPORTED);
}

static void test_bad_files(const char *dir)
{
    char p[1024];
    wav_info_t i;
    FILE *f;

    snprintf(p, sizeof p, "%s/e.wav", dir);
    f = fopen(p, "wb");
    fputs("esto no es un wav, es texto cualquiera", f);
    fclose(f);
    CHECK(wav_parse_file(p, &i) == WAV_ERR_FORMAT);

    f = fopen(p, "wb"); /* vacio */
    fclose(f);
    CHECK(wav_parse_file(p, &i) == WAV_ERR_FORMAT);

    CHECK(wav_parse_file("/no/existe.wav", &i) == WAV_ERR_IO);
}

static void test_truncated_data(const char *dir)
{
    char p[1024];
    wav_info_t i;
    spec_t s = base_spec();

    s.claim_extra = 1000000; /* declara mas datos de los que hay */
    snprintf(p, sizeof p, "%s/f.wav", dir);
    write_wav(p, &s);

    CHECK(wav_parse_file(p, &i) == WAV_OK);
    CHECK(i.data_size == 32000); /* acotado al tamano real */
    CHECK(i.duration_ms == 2000);
}

static void test_playlist(const char *dir)
{
    char p[1024];
    playlist_t *pl = malloc(sizeof *pl);
    spec_t s = base_spec();

    /* directorio aparte: solo contenido controlado */
    char sub[512];
    snprintf(sub, sizeof sub, "%s/pl", dir);
    mkdir(sub, 0700);

    s.list_pos = LIST_BEFORE_DATA; s.title = "Con Info"; s.artist = "Grupo"; s.album = "A";
    snprintf(p, sizeof p, "%s/z_con_info.wav", sub);
    write_wav(p, &s);

    s = base_spec();
    snprintf(p, sizeof p, "%s/Artista X - Cancion Y.WAV", sub); /* respaldo por nombre */
    write_wav(p, &s);

    snprintf(p, sizeof p, "%s/solo_titulo.wav", sub);
    write_wav(p, &s);

    s.bits = 8; /* se descarta */
    snprintf(p, sizeof p, "%s/mala.wav", sub);
    write_wav(p, &s);

    snprintf(p, sizeof p, "%s/notas.txt", sub); /* no es .wav */
    FILE *f = fopen(p, "wb");
    fputs("x", f);
    fclose(f);

    CHECK(playlist_scan(pl, sub) == 3);
    CHECK(pl->count == 3);
    /* orden por nombre sin distinguir mayusculas: Artista..., solo_titulo, z_con_info */
    CHECK(strcmp(pl->tracks[0].info.artist, "Artista X") == 0);
    CHECK(strcmp(pl->tracks[0].info.title, "Cancion Y") == 0);
    CHECK(strcmp(pl->tracks[1].info.title, "solo_titulo") == 0);
    CHECK(strcmp(pl->tracks[1].info.artist, "Desconocido") == 0);
    CHECK(strcmp(pl->tracks[2].info.title, "Con Info") == 0);
    CHECK(strcmp(pl->tracks[2].info.artist, "Grupo") == 0);
    CHECK(playlist_scan(pl, "/no/existe") == -1);
    free(pl);
}

int main(void)
{
    char dir[] = "/tmp/storage_test_XXXXXX";
    char cmd[400];

    if (!mkdtemp(dir)) {
        perror("mkdtemp");
        return 2;
    }

    test_info_before_data(dir);
    test_info_after_data_stereo(dir);
    test_no_info(dir);
    test_unsupported(dir);
    test_bad_files(dir);
    test_truncated_data(dir);
    test_playlist(dir);

    snprintf(cmd, sizeof cmd, "rm -rf '%s'", dir);
    if (system(cmd) != 0)
        fprintf(stderr, "aviso: no se pudo borrar %s\n", dir);

    printf("%d verificaciones, %d fallos\n", checks, failures);
    return failures ? 1 : 0;
}

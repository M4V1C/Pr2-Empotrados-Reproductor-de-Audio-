/*
 * Simulacion en el PC de la comunicacion HPS <-> Nios V.
 *
 * Dos hilos comparten un arreglo que hace de RAM compartida:
 *   - el hilo principal es el HPS: player + shm_sink + shm_hps (codigo real del HPS);
 *   - el hilo "nios_main" es el Nios V: usa shm_nios.c (la libreria real del Nios) y simula el
 *     codec consumiendo tramas. Es el mismo lazo que tendra el main del Nios.
 *
 * Todas las tramas que el "codec" recibe se guardan; las pruebas comprueban que son
 * exactamente las del archivo, en orden, sin perdidas ni duplicados.
 */
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "../../niosv/src/shm_nios.h"
#include "../../storage/playlist.h"
#include "../player.h"
#include "../shm_hps.h"
#include "../shm_sink.h"

static int failures, checks;

#define CHECK(cond)                                                          \
    do {                                                                     \
        checks++;                                                            \
        if (!(cond)) {                                                       \
            failures++;                                                      \
            fprintf(stderr, "FALLO %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                    \
    } while (0)

/* ------------------------------------------------------------------ WAV sinteticos */

static void w16(FILE *f, uint16_t v) { fputc(v & 255, f); fputc(v >> 8, f); }
static void w32(FILE *f, uint32_t v) { w16(f, (uint16_t)(v & 0xFFFFu)); w16(f, (uint16_t)(v >> 16)); }

static uint16_t sample(uint32_t seed, uint32_t i)
{
    return (uint16_t)(i * 31u + seed * 1009u + 7u);
}

/* trama k de una cancion con 'seed': lo que debe recibir el Nios */
static uint32_t expected(uint32_t seed, int ch, uint32_t k)
{
    if (ch == 2)
        return (uint32_t)sample(seed, 2 * k) | ((uint32_t)sample(seed, 2 * k + 1) << 16);
    return (uint32_t)sample(seed, k) | ((uint32_t)sample(seed, k) << 16);
}

static void write_wav(const char *path, uint32_t rate, int ch, uint32_t frames, uint32_t seed)
{
    FILE *f = fopen(path, "wb");
    uint32_t bytes = frames * (uint32_t)ch * 2u, i;

    if (!f) {
        perror(path);
        exit(2);
    }
    fwrite("RIFF", 1, 4, f); w32(f, 36u + bytes); fwrite("WAVEfmt ", 1, 8, f);
    w32(f, 16); w16(f, 1); w16(f, (uint16_t)ch); w32(f, rate);
    w32(f, rate * (uint32_t)ch * 2u); w16(f, (uint16_t)(ch * 2)); w16(f, 16);
    fwrite("data", 1, 4, f); w32(f, bytes);
    for (i = 0; i < frames * (uint32_t)ch; i++)
        w16(f, sample(seed, i));
    fclose(f);
}

typedef struct {
    const char *name;
    uint32_t rate;
    int ch;
    uint32_t frames;
    uint32_t seed;
} song_t;

/* La 3 supera el buffer (8192 tramas): ejercita la vuelta del buffer y la contrapresion. */
static const song_t SONGS[3] = {
    {"1_a.wav", 8000, 1, 3000, 1},
    {"2_b.wav", 16000, 2, 2500, 2},
    {"3_c.wav", 44100, 2, 20000, 3},
};

/* ------------------------------------------------------------------ Nios simulado */

#define CAP_MAX 200000
#define MAX_SEG 32

typedef struct {
    shm_nios_t nios;
    pthread_t th;
    volatile int run;
    volatile uint32_t inject;   /* evento a publicar como si fuera la ISR de un boton */
    uint32_t cap[CAP_MAX];      /* tramas recibidas por el "codec" */
    volatile size_t cap_len;
    size_t seg_start[MAX_SEG];  /* un segmento por LOAD */
    uint32_t seg_track[MAX_SEG];
    uint32_t seg_fs[MAX_SEG];
    uint32_t seg_total[MAX_SEG];
    volatile int nseg;
} sim_t;

static sim_t sim;
static volatile uint32_t shm_mem[SHM_SIZE_BYTES / 4]; /* la "RAM compartida" */

static void on_load(void *ctx, uint32_t fs, uint32_t total, uint32_t track)
{
    sim_t *s = ctx;
    int i = s->nseg;

    if (i < MAX_SEG) {
        s->seg_start[i] = s->cap_len;
        s->seg_track[i] = track;
        s->seg_fs[i] = fs;
        s->seg_total[i] = total;
    }
    s->nseg = i + 1;
}

static void *nios_main(void *arg)
{
    sim_t *s = arg;

    while (s->run) {
        int i;

        shm_nios_service(&s->nios);
        if (s->inject) {
            shm_nios_push_event(&s->nios, s->inject, 0);
            s->inject = 0;
        }
        for (i = 0; i < 64; i++) { /* el codec acepta 64 tramas por vuelta (~300 mil tramas/s) */
            uint32_t f;

            if (shm_nios_pop_frame(&s->nios, &f) != 1)
                break; /* vacio (underrun) o sin reproducir */
            if (s->cap_len < CAP_MAX) {
                s->cap[s->cap_len] = f;
                s->cap_len = s->cap_len + 1;
            }
        }
        usleep(200);
    }
    return NULL;
}

static void start_sim(void)
{
    shm_nios_hooks_t h = {on_load, NULL, NULL, NULL, &sim};

    shm_wr(shm_mem, SHM_OFF_MAGIC, 0);
    sim.cap_len = 0;
    sim.nseg = 0;
    sim.inject = 0;
    shm_nios_init(&sim.nios, shm_mem, &h);
    sim.run = 1;
    pthread_create(&sim.th, NULL, nios_main, &sim);
}

static void stop_sim(void)
{
    sim.run = 0;
    pthread_join(sim.th, NULL);
}

/* ------------------------------------------------------------------ HPS */

static playlist_t pl;
static player_t player;
static shm_hps_t hps;
static player_sink_t sink;

static void begin(void)
{
    start_sim();
    shm_hps_init(&hps, shm_mem);
    CHECK(shm_hps_wait_nios(&hps, 1000) == 0);
    shm_sink_init(&sink, &hps);
    CHECK(player_init(&player, &pl, &sink) == 0);
}

/* Ejecuta player_tick cada 1 ms hasta que done() sea verdadero o pasen 'ms'. */
static int pump(int ms, int (*done)(void))
{
    int t;

    for (t = 0; t < ms; t++) {
        player_tick(&player);
        if (done && done())
            return 1;
        usleep(1000);
    }
    return done == NULL;
}

static size_t want_len;
static int want_seg;

static int cap_ge(void) { return sim.cap_len >= want_len; }
static int seg_ge(void) { return sim.nseg >= want_seg; }
/* ya empezo el segmento 'want_seg' y llegaron 300 tramas de el */
static int seg_data(void)
{
    return sim.nseg >= want_seg && sim.cap_len >= sim.seg_start[want_seg - 1] + 300;
}
static int is_paused(void) { return player_state(&player) == PLAYER_PAUSED; }
static int is_stopped(void) { return player_state(&player) == PLAYER_STOPPED; }

/* Cuenta las tramas del segmento 's' que no coinciden con la cancion (seed, ch). */
static size_t segment_bad(int s, uint32_t seed, int ch, size_t *len)
{
    size_t start = sim.seg_start[s];
    size_t end = (s + 1 < sim.nseg) ? sim.seg_start[s + 1] : sim.cap_len;
    size_t k, bad = 0;

    for (k = 0; start + k < end; k++)
        if (sim.cap[start + k] != expected(seed, ch, (uint32_t)k))
            bad++;
    *len = end - start;
    return bad;
}

/* ------------------------------------------------------------------ pruebas */

static void test_lista_completa_y_vuelta(void)
{
    size_t len;

    begin();
    CHECK(player_state(&player) == PLAYER_STOPPED);
    player_play_pause(&player);
    CHECK(player_state(&player) == PLAYER_PLAYING);

    want_seg = 4; /* las 3 canciones y la vuelta a la primera */
    CHECK(pump(5000, seg_data));
    player_stop(&player);
    stop_sim();

    CHECK(sim.nseg >= 4);
    CHECK(sim.seg_track[0] == 1 && sim.seg_fs[0] == 8000 && sim.seg_total[0] == 3000);
    CHECK(sim.seg_track[1] == 2 && sim.seg_fs[1] == 16000 && sim.seg_total[1] == 2500);
    CHECK(sim.seg_track[2] == 3 && sim.seg_fs[2] == 44100 && sim.seg_total[2] == 20000);
    CHECK(sim.seg_track[3] == 1);

    CHECK(segment_bad(0, 1, 1, &len) == 0 && len == 3000);
    CHECK(segment_bad(1, 2, 2, &len) == 0 && len == 2500);
    CHECK(segment_bad(2, 3, 2, &len) == 0 && len == 20000); /* sin perdidas ni duplicados */
    CHECK(segment_bad(3, 1, 1, &len) == 0 && len >= 300);
}

static void test_pausa_y_reanudar(void)
{
    size_t len, antes;

    begin();
    player_next(&player);
    player_next(&player); /* detenido: solo mueve la seleccion */
    CHECK(player_index(&player) == 2);
    CHECK(sim.nseg == 0);

    player_play_pause(&player);
    want_len = 6000;
    CHECK(pump(5000, cap_ge));

    player_play_pause(&player); /* pausa */
    CHECK(player_state(&player) == PLAYER_PAUSED);
    CHECK(shm_hps_state(&hps) == SHM_ST_PAUSED);
    antes = sim.cap_len;
    pump(30, NULL); /* el HPS sigue rellenando, pero el Nios no consume */
    CHECK(sim.cap_len == antes);

    player_play_pause(&player); /* reanuda */
    CHECK(player_state(&player) == PLAYER_PLAYING);
    want_seg = 2; /* al terminar la 3 vuelve a la 1 */
    CHECK(pump(5000, seg_ge));
    player_stop(&player);
    stop_sim();

    CHECK(segment_bad(0, 3, 2, &len) == 0 && len == 20000); /* continuidad exacta */
}

static void test_controles_y_botones(void)
{
    size_t len;

    begin();
    player_play_pause(&player);
    want_len = 500;
    CHECK(pump(5000, cap_ge));

    player_next(&player); /* 1 -> 2 */
    want_seg = 2;
    CHECK(pump(5000, seg_data));
    CHECK(player_index(&player) == 1);

    player_prev(&player); /* 2 -> 1 */
    want_seg = 3;
    CHECK(pump(5000, seg_data));
    CHECK(player_index(&player) == 0);

    sim.inject = SHM_EVT_BTN_NEXT; /* boton del Nios -> evento -> el HPS cambia de cancion */
    want_seg = 4;
    CHECK(pump(5000, seg_data));
    CHECK(player_index(&player) == 1 && player_state(&player) == PLAYER_PLAYING);

    sim.inject = SHM_EVT_BTN_PLAYPAUSE;
    CHECK(pump(2000, is_paused));
    CHECK(shm_hps_state(&hps) == SHM_ST_PAUSED);

    sim.inject = SHM_EVT_BTN_STOP;
    CHECK(pump(2000, is_stopped));
    CHECK(shm_hps_state(&hps) == SHM_ST_IDLE);
    CHECK(shm_hps_ring_free(&hps) == SHM_RING_WORDS); /* buffer vaciado */
    stop_sim();

    CHECK(segment_bad(0, 1, 1, &len) == 0 && len >= 500);
    CHECK(segment_bad(1, 2, 2, &len) == 0 && len >= 300);
    CHECK(segment_bad(2, 1, 1, &len) == 0 && len >= 300);
    CHECK(segment_bad(3, 2, 2, &len) == 0 && len >= 300);
}

static void test_underrun_se_recupera(void)
{
    size_t len;

    begin();
    player_next(&player);
    player_next(&player);
    player_play_pause(&player); /* rellena el buffer (8192) y arranca */

    usleep(150000); /* el HPS "se atrasa": no hay player_tick, el Nios vacia el buffer */
    CHECK(shm_hps_underruns(&hps) > 0);
    CHECK(sim.cap_len == SHM_RING_WORDS); /* solo salio lo que estaba escrito */

    want_seg = 2;
    CHECK(pump(5000, seg_ge));
    player_stop(&player);
    stop_sim();
    CHECK(segment_bad(0, 3, 2, &len) == 0 && len == 20000); /* el atraso no perdio ni repitio nada */
}

static void test_comandos_y_errores(void)
{
    begin();
    CHECK(shm_hps_ring_free(&hps) == SHM_RING_WORDS);
    CHECK(shm_hps_command(&hps, SHM_CMD_PLAY, 0, 0, 0) == SHM_RES_BAD_STATE); /* desde IDLE */
    CHECK(shm_hps_command(&hps, SHM_CMD_LOAD, 22050, 100, 1) == SHM_RES_BAD_FS);
    CHECK(shm_hps_command(&hps, 99, 0, 0, 0) == SHM_RES_BAD_CMD);
    CHECK(shm_hps_state(&hps) == SHM_ST_IDLE);

    CHECK(shm_hps_command(&hps, SHM_CMD_LOAD, 8000, 10, 1) == SHM_RES_OK);
    CHECK(shm_hps_state(&hps) == SHM_ST_READY);
    CHECK(shm_hps_command(&hps, SHM_CMD_PLAY, 0, 0, 0) == SHM_RES_OK);
    CHECK(shm_hps_state(&hps) == SHM_ST_PLAYING);
    usleep(5000); /* sin tramas: underrun, pero sigue en PLAYING */
    CHECK(shm_hps_underruns(&hps) > 0);
    CHECK(shm_hps_state(&hps) == SHM_ST_PLAYING);
    CHECK(shm_hps_command(&hps, SHM_CMD_PAUSE, 0, 0, 0) == SHM_RES_OK);
    CHECK(shm_hps_command(&hps, SHM_CMD_PAUSE, 0, 0, 0) == SHM_RES_BAD_STATE);
    CHECK(shm_hps_command(&hps, SHM_CMD_STOP, 0, 0, 0) == SHM_RES_OK);
    CHECK(shm_hps_state(&hps) == SHM_ST_IDLE);

    /* una cancion sin tramas termina al instante */
    CHECK(shm_hps_command(&hps, SHM_CMD_LOAD, 8000, 0, 1) == SHM_RES_OK);
    CHECK(shm_hps_command(&hps, SHM_CMD_PLAY, 0, 0, 0) == SHM_RES_OK);
    CHECK(shm_hps_state(&hps) == SHM_ST_ENDED);

    /* sin Nios que responda, el comando vence por tiempo */
    stop_sim();
    hps.timeout_ms = 20;
    CHECK(shm_hps_command(&hps, SHM_CMD_STOP, 0, 0, 0) == -1);
}

static void test_ring_helpers(void)
{
    uint32_t buf[SHM_RING_WORDS + 10];
    uint32_t i;

    for (i = 0; i < SHM_RING_WORDS + 10; i++)
        buf[i] = i;
    begin();
    CHECK(shm_hps_ring_write(&hps, buf, SHM_RING_WORDS + 10) == SHM_RING_WORDS); /* nunca mas que las libres */
    CHECK(shm_hps_ring_free(&hps) == 0);
    stop_sim();
}

static void test_lista_vacia(void)
{
    playlist_t *vacia = calloc(1, sizeof *vacia);
    player_t *p = calloc(1, sizeof *p);
    player_sink_t s;

    memset(&s, 0, sizeof s);
    CHECK(vacia && p);
    CHECK(player_init(p, vacia, &s) == -1);
    free(p);
    free(vacia);
}

int main(void)
{
    char dir[] = "/tmp/comm_test_XXXXXX";
    char path[300], cmd[400];
    size_t i;

    if (!mkdtemp(dir)) {
        perror("mkdtemp");
        return 2;
    }
    for (i = 0; i < 3; i++) {
        snprintf(path, sizeof path, "%s/%s", dir, SONGS[i].name);
        write_wav(path, SONGS[i].rate, SONGS[i].ch, SONGS[i].frames, SONGS[i].seed);
    }
    CHECK(playlist_scan(&pl, dir) == 3);

    test_lista_completa_y_vuelta();
    test_pausa_y_reanudar();
    test_controles_y_botones();
    test_underrun_se_recupera();
    test_comandos_y_errores();
    test_ring_helpers();
    test_lista_vacia();

    player_close(&player);
    snprintf(cmd, sizeof cmd, "rm -rf '%s'", dir);
    if (system(cmd) != 0)
        fprintf(stderr, "aviso: no se pudo borrar %s\n", dir);

    printf("%d verificaciones, %d fallos\n", checks, failures);
    return failures ? 1 : 0;
}

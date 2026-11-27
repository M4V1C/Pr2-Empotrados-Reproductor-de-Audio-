#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE /* usleep */
#include "shm_hps.h"

#include <fcntl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static double ahora_ms(void)
{
    struct timespec t;

    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec * 1000.0 + (double)t.tv_nsec / 1e6;
}

volatile uint32_t *shm_hps_map(const char *dev, off_t phys, size_t len)
{
    void *p;
    int fd = open(dev, O_RDWR | O_SYNC);

    if (fd < 0)
        return NULL;
    p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, phys);
    close(fd);
    return p == MAP_FAILED ? NULL : (volatile uint32_t *)p;
}

void shm_hps_unmap(volatile uint32_t *base, size_t len)
{
    if (base)
        munmap((void *)base, len);
}

void shm_hps_init(shm_hps_t *s, volatile uint32_t *base)
{
    uint32_t off;

    s->base = base;
    s->seq = 0;
    s->timeout_ms = 100;

    shm_wr(base, SHM_OFF_MAGIC, 0); /* el Nios deja de atender mientras se reinicia */
    SHM_BARRIER();
    usleep(2000);
    for (off = 4; off < SHM_CTRL_BYTES; off += 4)
        shm_wr(base, off, 0);
    shm_wr(base, SHM_OFF_VERSION, SHM_VERSION);
    SHM_BARRIER();
    shm_wr(base, SHM_OFF_MAGIC, SHM_MAGIC); /* al final: ahora el Nios puede arrancar */
}

int shm_hps_wait_nios(const shm_hps_t *s, uint32_t timeout_ms)
{
    double t0 = ahora_ms();

    while (shm_rd(s->base, SHM_OFF_NIOS_MAGIC) != SHM_MAGIC) {
        if (ahora_ms() - t0 > (double)timeout_ms)
            return -1;
        usleep(500);
    }
    SHM_BARRIER();
    return 0;
}

int shm_hps_command(shm_hps_t *s, uint32_t code, uint32_t a0, uint32_t a1, uint32_t a2)
{
    volatile uint32_t *b = s->base;
    uint32_t seq = s->seq + 1u;
    double t0;

    if (seq == 0u)
        seq = 1u;
    shm_wr(b, SHM_OFF_ARG0, a0);
    shm_wr(b, SHM_OFF_ARG1, a1);
    shm_wr(b, SHM_OFF_ARG2, a2);
    shm_wr(b, SHM_OFF_CMD_CODE, code);
    SHM_BARRIER();
    shm_wr(b, SHM_OFF_CMD_SEQ, seq); /* al final: dispara la ejecucion en el Nios */
    s->seq = seq;

    t0 = ahora_ms();
    while (shm_rd(b, SHM_OFF_ACK) != seq) {
        if (ahora_ms() - t0 > (double)s->timeout_ms)
            return -1;
        usleep(50);
    }
    SHM_BARRIER();
    return (int)shm_rd(b, SHM_OFF_RESULT);
}

uint32_t shm_hps_ring_free(const shm_hps_t *s)
{
    uint32_t used = shm_rd(s->base, SHM_OFF_RING_WR) - shm_rd(s->base, SHM_OFF_RING_RD);

    return used >= SHM_RING_WORDS ? 0u : SHM_RING_WORDS - used;
}

size_t shm_hps_ring_write(shm_hps_t *s, const uint32_t *frames, size_t n)
{
    volatile uint32_t *b = s->base;
    uint32_t wr = shm_rd(b, SHM_OFF_RING_WR);
    uint32_t libres = shm_hps_ring_free(s);
    size_t i;

    if (n > libres)
        n = libres;
    for (i = 0; i < n; i++)
        shm_wr(b, SHM_RING_OFFSET + (((wr + (uint32_t)i) & SHM_RING_MASK) << 2), frames[i]);
    SHM_BARRIER(); /* los datos antes que el puntero */
    shm_wr(b, SHM_OFF_RING_WR, wr + (uint32_t)n);
    return n;
}

uint32_t shm_hps_state(const shm_hps_t *s) { return shm_rd(s->base, SHM_OFF_STATE); }
uint32_t shm_hps_frames_played(const shm_hps_t *s) { return shm_rd(s->base, SHM_OFF_PLAYED); }
uint32_t shm_hps_filter(const shm_hps_t *s) { return shm_rd(s->base, SHM_OFF_FILTER); }
uint32_t shm_hps_volume(const shm_hps_t *s) { return shm_rd(s->base, SHM_OFF_VOLUME); }
uint32_t shm_hps_underruns(const shm_hps_t *s) { return shm_rd(s->base, SHM_OFF_UNDERRUN); }

int shm_hps_event_pop(shm_hps_t *s, uint32_t *evt)
{
    volatile uint32_t *b = s->base;
    uint32_t rd = shm_rd(b, SHM_OFF_EVT_RD);

    if (rd == shm_rd(b, SHM_OFF_EVT_WR))
        return 0;
    SHM_BARRIER();
    *evt = shm_rd(b, SHM_OFF_EVT_BASE + ((rd & SHM_EVT_MASK) << 2));
    SHM_BARRIER();
    shm_wr(b, SHM_OFF_EVT_RD, rd + 1u);
    return 1;
}

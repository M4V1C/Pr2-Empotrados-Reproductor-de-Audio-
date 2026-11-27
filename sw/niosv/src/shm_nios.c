#include "shm_nios.h"

static int fs_valida(uint32_t fs)
{
    return fs == 8000u || fs == 16000u || fs == 44100u;
}

/* Descarta lo que haya en el buffer: el Nios solo mueve SU puntero (RD) hasta el de escritura.
 * El HPS ya dejo de escribir antes de mandar LOAD o STOP. */
static void vaciar_buffer(shm_nios_t *n)
{
    shm_wr(n->base, SHM_OFF_RING_RD, shm_rd(n->base, SHM_OFF_RING_WR));
}

static void arrancar_limpio(shm_nios_t *n)
{
    volatile uint32_t *b = n->base;
    /* NIOS_MAGIC ya puesto = el Nios se reinicio solo (el HPS no reinicio el protocolo): el
     * ultimo comando es viejo y se ignora. Si no, el HPS acaba de iniciar (y puso ACK y SEQ en
     * cero): un comando que ya haya enviado es valido y debe ejecutarse. */
    int reinicio_solo = shm_rd(b, SHM_OFF_NIOS_MAGIC) == SHM_MAGIC;

    n->total_frames = 0;
    shm_wr(b, SHM_OFF_STATE, SHM_ST_IDLE);
    shm_wr(b, SHM_OFF_PLAYED, 0);
    shm_wr(b, SHM_OFF_UNDERRUN, 0);
    vaciar_buffer(n);
    shm_wr(b, SHM_OFF_EVT_WR, shm_rd(b, SHM_OFF_EVT_RD));
    shm_wr(b, SHM_OFF_ACK, reinicio_solo ? shm_rd(b, SHM_OFF_CMD_SEQ) : 0u);
    SHM_BARRIER();
    shm_wr(b, SHM_OFF_NIOS_MAGIC, SHM_MAGIC); /* al final: ya se puede mandar comandos */
    n->ready = 1;
}

void shm_nios_init(shm_nios_t *n, volatile uint32_t *base, const shm_nios_hooks_t *hooks)
{
    n->base = base;
    n->total_frames = 0;
    n->ready = 0;
    n->hooks.on_load = 0;
    n->hooks.on_play = 0;
    n->hooks.on_pause = 0;
    n->hooks.on_stop = 0;
    n->hooks.ctx = 0;
    if (hooks)
        n->hooks = *hooks;
}

/* Ejecuta un comando y devuelve SHM_RES_*. */
static uint32_t ejecutar(shm_nios_t *n, uint32_t code, uint32_t a0, uint32_t a1, uint32_t a2)
{
    volatile uint32_t *b = n->base;
    uint32_t st = shm_rd(b, SHM_OFF_STATE);

    switch (code) {
    case SHM_CMD_LOAD:
        if (!fs_valida(a0))
            return SHM_RES_BAD_FS;
        vaciar_buffer(n);
        n->total_frames = a1;
        shm_wr(b, SHM_OFF_PLAYED, 0);
        shm_wr(b, SHM_OFF_STATE, SHM_ST_READY);
        if (n->hooks.on_load)
            n->hooks.on_load(n->hooks.ctx, a0, a1, a2);
        return SHM_RES_OK;

    case SHM_CMD_PLAY:
        if (st != SHM_ST_READY && st != SHM_ST_PAUSED)
            return SHM_RES_BAD_STATE;
        /* una cancion sin tramas termina de inmediato */
        shm_wr(b, SHM_OFF_STATE,
               (n->total_frames == 0u) ? SHM_ST_ENDED : SHM_ST_PLAYING);
        if (n->hooks.on_play)
            n->hooks.on_play(n->hooks.ctx);
        return SHM_RES_OK;

    case SHM_CMD_PAUSE:
        if (st != SHM_ST_PLAYING)
            return SHM_RES_BAD_STATE;
        shm_wr(b, SHM_OFF_STATE, SHM_ST_PAUSED);
        if (n->hooks.on_pause)
            n->hooks.on_pause(n->hooks.ctx);
        return SHM_RES_OK;

    case SHM_CMD_STOP:
        vaciar_buffer(n);
        n->total_frames = 0;
        shm_wr(b, SHM_OFF_PLAYED, 0);
        shm_wr(b, SHM_OFF_STATE, SHM_ST_IDLE);
        if (n->hooks.on_stop)
            n->hooks.on_stop(n->hooks.ctx);
        return SHM_RES_OK;

    default:
        return SHM_RES_BAD_CMD;
    }
}

void shm_nios_service(shm_nios_t *n)
{
    volatile uint32_t *b = n->base;
    uint32_t seq, res;

    if (shm_rd(b, SHM_OFF_MAGIC) != SHM_MAGIC) {
        n->ready = 0; /* el HPS no inicio (o se esta reiniciando) */
        return;
    }
    if (!n->ready)
        arrancar_limpio(n);

    seq = shm_rd(b, SHM_OFF_CMD_SEQ);
    if (seq == shm_rd(b, SHM_OFF_ACK))
        return;
    SHM_BARRIER(); /* CMD_SEQ se escribe al final: los argumentos ya son validos */

    res = ejecutar(n, shm_rd(b, SHM_OFF_CMD_CODE), shm_rd(b, SHM_OFF_ARG0),
                   shm_rd(b, SHM_OFF_ARG1), shm_rd(b, SHM_OFF_ARG2));
    shm_wr(b, SHM_OFF_RESULT, res);
    SHM_BARRIER();
    shm_wr(b, SHM_OFF_ACK, seq); /* al final: el HPS espera esto */
}

int shm_nios_pop_frame(shm_nios_t *n, uint32_t *frame)
{
    volatile uint32_t *b = n->base;
    uint32_t rd, wr, played;

    if (!n->ready || shm_rd(b, SHM_OFF_STATE) != SHM_ST_PLAYING)
        return -1;

    rd = shm_rd(b, SHM_OFF_RING_RD);
    wr = shm_rd(b, SHM_OFF_RING_WR);
    if (wr == rd) {
        shm_wr(b, SHM_OFF_UNDERRUN, shm_rd(b, SHM_OFF_UNDERRUN) + 1u);
        return 0;
    }
    SHM_BARRIER(); /* leer WR antes que los datos */
    *frame = shm_rd(b, SHM_RING_OFFSET + ((rd & SHM_RING_MASK) << 2));
    SHM_BARRIER(); /* leer el dato antes de liberar el hueco */
    shm_wr(b, SHM_OFF_RING_RD, rd + 1u);

    played = shm_rd(b, SHM_OFF_PLAYED) + 1u;
    shm_wr(b, SHM_OFF_PLAYED, played);
    if (played >= n->total_frames)
        shm_wr(b, SHM_OFF_STATE, SHM_ST_ENDED);
    return 1;
}

uint32_t shm_nios_state(const shm_nios_t *n)
{
    return shm_rd(n->base, SHM_OFF_STATE);
}

void shm_nios_set_filter(shm_nios_t *n, uint32_t filter)
{
    shm_wr(n->base, SHM_OFF_FILTER, filter);
}

void shm_nios_set_volume(shm_nios_t *n, uint32_t volume)
{
    shm_wr(n->base, SHM_OFF_VOLUME, volume);
}

int shm_nios_push_event(shm_nios_t *n, uint32_t code, uint32_t arg)
{
    volatile uint32_t *b = n->base;
    uint32_t wr = shm_rd(b, SHM_OFF_EVT_WR);

    if (wr - shm_rd(b, SHM_OFF_EVT_RD) >= SHM_EVT_SLOTS)
        return 0;
    shm_wr(b, SHM_OFF_EVT_BASE + ((wr & SHM_EVT_MASK) << 2), SHM_EVT(code, arg));
    SHM_BARRIER();
    shm_wr(b, SHM_OFF_EVT_WR, wr + 1u);
    return 1;
}

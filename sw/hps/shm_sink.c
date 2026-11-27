#include "shm_sink.h"

static int cmd(void *ctx, uint32_t code, uint32_t a0, uint32_t a1, uint32_t a2)
{
    return shm_hps_command((shm_hps_t *)ctx, code, a0, a1, a2) == SHM_RES_OK ? 0 : -1;
}

static int sk_load(void *ctx, uint32_t fs, uint32_t frames, uint32_t track)
{
    return cmd(ctx, SHM_CMD_LOAD, fs, frames, track);
}

static int sk_play(void *ctx) { return cmd(ctx, SHM_CMD_PLAY, 0, 0, 0); }
static int sk_pause(void *ctx) { return cmd(ctx, SHM_CMD_PAUSE, 0, 0, 0); }
static int sk_stop(void *ctx) { return cmd(ctx, SHM_CMD_STOP, 0, 0, 0); }

static uint32_t sk_free(void *ctx)
{
    return shm_hps_ring_free((shm_hps_t *)ctx);
}

static void sk_write(void *ctx, const uint32_t *frames, size_t n)
{
    shm_hps_ring_write((shm_hps_t *)ctx, frames, n);
}

static uint32_t sk_state(void *ctx)
{
    return shm_hps_state((shm_hps_t *)ctx);
}

static int sk_event(void *ctx, uint32_t *evt)
{
    return shm_hps_event_pop((shm_hps_t *)ctx, evt);
}

void shm_sink_init(player_sink_t *sink, shm_hps_t *h)
{
    sink->load = sk_load;
    sink->play = sk_play;
    sink->pause = sk_pause;
    sink->stop = sk_stop;
    sink->free_frames = sk_free;
    sink->write = sk_write;
    sink->state = sk_state;
    sink->poll_event = sk_event;
    sink->ctx = h;
}

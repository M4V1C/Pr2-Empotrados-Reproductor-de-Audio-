#include "player.h"

#include <string.h>

#include "../common/shm_protocol.h"

static void cerrar_lector(player_t *p)
{
    if (p->reader_open)
        track_close(&p->reader);
    p->reader_open = 0;
    p->reader_done = 0;
}

/* Llena el buffer hasta que se llene o se acabe la cancion. Nunca pide mas tramas de las que
 * caben: track_read consume, lo que no se escribe se perderia. */
static void rellenar(player_t *p)
{
    while (p->reader_open && !p->reader_done) {
        uint32_t libres = p->sink.free_frames(p->sink.ctx);
        size_t pedir, n;

        if (libres == 0u)
            break;
        pedir = libres < PLAYER_BLOCK_FRAMES ? libres : PLAYER_BLOCK_FRAMES;
        n = track_read(&p->reader, p->block, pedir);
        if (n == 0) {
            p->reader_done = 1; /* fin de la cancion, o error (p->reader.error) */
            break;
        }
        p->sink.write(p->sink.ctx, p->block, n);
    }
}

/* Abre la cancion 'idx' (si no se puede abrir prueba la siguiente en el sentido 'paso'),
 * la carga en el Nios y deja el buffer lleno. 0 si ok, -1 si ninguna se pudo cargar. */
static int iniciar_cancion(player_t *p, size_t idx, int paso)
{
    size_t n = p->pl->count, intentos;

    for (intentos = 0; intentos < n; intentos++) {
        const track_t *t = &p->pl->tracks[idx];

        cerrar_lector(p);
        if (track_open(&p->reader, t->path, &t->info) == 0) {
            p->reader_open = 1;
            p->index = idx;
            if (p->sink.load(p->sink.ctx, t->info.sample_rate, p->reader.total_frames,
                             (uint32_t)idx + 1u) != 0) {
                cerrar_lector(p);
                return -1;
            }
            rellenar(p);
            return 0;
        }
        idx = paso > 0 ? (idx + 1) % n : (idx + n - 1) % n;
    }
    return -1;
}

static void a_detenido(player_t *p)
{
    p->sink.stop(p->sink.ctx);
    cerrar_lector(p);
    p->state = PLAYER_STOPPED;
}

/* Siguiente (+1) o anterior (-1). */
static void mover(player_t *p, int paso)
{
    size_t n = p->pl->count;
    size_t idx = paso > 0 ? (p->index + 1) % n : (p->index + n - 1) % n;

    if (p->state == PLAYER_STOPPED) {
        p->index = idx; /* solo cambia la seleccion */
        return;
    }
    if (iniciar_cancion(p, idx, paso) == 0 && p->sink.play(p->sink.ctx) == 0)
        p->state = PLAYER_PLAYING;
    else
        a_detenido(p);
}

int player_init(player_t *p, const playlist_t *pl, const player_sink_t *sink)
{
    memset(p, 0, sizeof *p);
    if (!pl || pl->count == 0 || !sink)
        return -1;
    p->pl = pl;
    p->sink = *sink;
    p->state = PLAYER_STOPPED;
    return 0;
}

void player_play_pause(player_t *p)
{
    switch (p->state) {
    case PLAYER_STOPPED:
        if (iniciar_cancion(p, p->index, +1) == 0 && p->sink.play(p->sink.ctx) == 0)
            p->state = PLAYER_PLAYING;
        else
            a_detenido(p);
        break;
    case PLAYER_PLAYING:
        if (p->sink.pause(p->sink.ctx) == 0)
            p->state = PLAYER_PAUSED;
        break;
    case PLAYER_PAUSED:
        if (p->sink.play(p->sink.ctx) == 0)
            p->state = PLAYER_PLAYING;
        break;
    }
}

void player_stop(player_t *p)
{
    if (p->state != PLAYER_STOPPED)
        a_detenido(p);
}

void player_next(player_t *p) { mover(p, +1); }
void player_prev(player_t *p) { mover(p, -1); }

static void atender_evento(player_t *p, uint32_t evt)
{
    switch (SHM_EVT_CODE(evt)) {
    case SHM_EVT_BTN_PLAYPAUSE: player_play_pause(p); break;
    case SHM_EVT_BTN_STOP:      player_stop(p);       break;
    case SHM_EVT_BTN_NEXT:      player_next(p);       break;
    case SHM_EVT_BTN_PREV:      player_prev(p);       break;
    default: break;
    }
}

void player_tick(player_t *p)
{
    uint32_t evt;

    while (p->sink.poll_event(p->sink.ctx, &evt))
        atender_evento(p, evt);

    if (p->state == PLAYER_STOPPED)
        return;

    rellenar(p);

    /* Archivo cortado: el Nios esperaria tramas que ya no llegaran. Se salta a la siguiente. */
    if (p->reader_done && p->reader.error != TRACK_ERR_NONE) {
        mover(p, +1);
        return;
    }
    /* Reproduccion continua: al terminar una cancion empieza la siguiente. */
    if (p->state == PLAYER_PLAYING && p->sink.state(p->sink.ctx) == SHM_ST_ENDED)
        mover(p, +1);
}

player_state_t player_state(const player_t *p) { return p->state; }
size_t player_index(const player_t *p) { return p->index; }
const track_t *player_track(const player_t *p) { return &p->pl->tracks[p->index]; }

void player_close(player_t *p) { cerrar_lector(p); }

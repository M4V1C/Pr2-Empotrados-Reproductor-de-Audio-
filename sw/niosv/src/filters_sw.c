/*===============================================================================================
 *              ~~~~~ Filtros de software del Nios V (para issue F-07 del repo) ~~~~~
 *
 * Solo sumas, restas y desplazamientos: 
 * porque el Nios V/m (RV32I) no tiene multiplicador ni divisor por hardware
 *
 * Ojo: en C, '>>' sobre un entero con signo negativo depende del compilador.
 * Estamos usando GCC que usa desplazamiento aritmetico, igual que Python y que '>>>' en Verilog
 ================================================================================================
 */
#include "filters_sw.h"
// ======================================================
// ~~~ Estado (estatico: no hay malloc en el Nios) ~~~
// ======================================================
static pb_state_t pb_l, pb_r;
static eco_state_t eco_l, eco_r;
static int16_t eco_buf_l[ECHO_D_MAX];
static int16_t eco_buf_r[ECHO_D_MAX];
static uint8_t pb_k_hp = PB_KHP_44100;
static uint8_t pb_k_lp = PB_KLP_44100;
static uint32_t eco_d = ECHO_D_44100;

// ========================================================
// ~~~ Auxiliares (op de punto fijo) ~~~
// ========================================================
static inline int16_t sat16(int32_t v) {
    if (v > 32767) return 32767;
    if (v < -32768) return -32768;
    return (int16_t)v;
}

// v << n sin comportamiento indefinido para v negativo 
static inline int32_t shl(int32_t v, unsigned n) {
    return (int32_t)((uint32_t)v << n);
}

static void pb_clear(pb_state_t *st) {
    for (int i = 0; i < PB_STAGES; i++) {
        st->s_hp[i] = 0;
        st->s_lp[i] = 0;
    }
}

static void eco_clear(eco_state_t *st, int16_t *buf) {
    st->buf = buf;
    st->idx = 0;
    st->d = eco_d;
    for (uint32_t i = 0; i < ECHO_D_MAX; i++)
        buf[i] = 0;
}

// =============================================================================
// ~~~ API ~~~
// =============================================================================
int filters_sw_init(uint32_t fs) {
    if (fs == 8000) {
        pb_k_hp = PB_KHP_8000;  pb_k_lp = PB_KLP_8000;  eco_d = ECHO_D_8000;
    } else if (fs == 16000) {
        pb_k_hp = PB_KHP_16000; pb_k_lp = PB_KLP_16000; eco_d = ECHO_D_16000;
    } else if (fs == 44100) {
        pb_k_hp = PB_KHP_44100; pb_k_lp = PB_KLP_44100; eco_d = ECHO_D_44100;
    } else {
        return -1;
    }
    filters_sw_reset();
    return 0;
}

void filters_sw_reset(void) {
    pb_clear(&pb_l);
    pb_clear(&pb_r);
    eco_clear(&eco_l, eco_buf_l);
    eco_clear(&eco_r, eco_buf_r);
}

/*-----------------------------------------------------------------
 * Pasa-banda= Cada etapa guarda su estado escalado por 2^PB_FRAC:
 *     s += ((v << F) - s) >> k
 *     pasa-alto: v = v - (s >> F)
 *     pasa-bajo: v = s >> F
 ------------------------------------------------------------------
 */
int16_t pb_process(pb_state_t *st, int16_t x) {
    int32_t v = x;
    for (int i = 0; i < PB_STAGES; i++) {               /* pasa-altos */
        st->s_hp[i] += (shl(v, PB_FRAC) - st->s_hp[i]) >> pb_k_hp;
        v = v - (st->s_hp[i] >> PB_FRAC);
    }
    for (int i = 0; i < PB_STAGES; i++) {               /* pasa-bajos */
        st->s_lp[i] += (shl(v, PB_FRAC) - st->s_lp[i]) >> pb_k_lp;
        v = st->s_lp[i] >> PB_FRAC;
    }
    return sat16(v);
}

// Eco con realimentacion: y[n] = sat16(x[n] + (y[n-D] >> ECHO_SHIFT))
int16_t eco_process(eco_state_t *st, int16_t x) {
    int16_t y = sat16((int32_t)x + (st->buf[st->idx] >> ECHO_SHIFT));
    st->buf[st->idx] = y;
    if (++st->idx == st->d) // sin '%' porque el Nios no divide
        st->idx = 0;
    return y;
}

uint32_t pb_frame(uint32_t lr) {
    int16_t l = pb_process(&pb_l, (int16_t)(lr & 0xFFFFu));
    int16_t r = pb_process(&pb_r, (int16_t)(lr >> 16));
    return ((uint32_t)(uint16_t)r << 16) | (uint16_t)l;
}

uint32_t eco_frame(uint32_t lr) {
    int16_t l = eco_process(&eco_l, (int16_t)(lr & 0xFFFFu));
    int16_t r = eco_process(&eco_r, (int16_t)(lr >> 16));
    return ((uint32_t)(uint16_t)r << 16) | (uint16_t)l;
}

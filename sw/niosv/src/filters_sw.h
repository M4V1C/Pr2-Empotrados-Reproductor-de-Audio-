/* =============================================================================================================
 *                  ~~~~~ Filtros de software del Nios V (para issue F-07 del repo) ~~~~~
 *
 *   - Pasa-banda: 2 etapas pasa-altos + 2 etapas pasa-bajos IIR de 1er orden, alpha = 2^-k
 *   - Eco/reverberacion: y[n] = sat16(x[n] + (y[n-D] >> 1))
 *
 * El Nios V/m (RV32I) NO tiene multiplicador: todo se hace con sumas, restas y desplazamientos
 * Calculos por muestra no usan '*', '/' ni '%'
 *
 * Para pruebas comparamos contra comportamiento (bit a bit) del model_pb() y model_echo() de tools/gen_coefs.py
 * Los parametros salen de filters_params.h (generado)
 * ==============================================================================================================
 */
#ifndef FILTERS_SW_H
#define FILTERS_SW_H
#include <stdint.h>
#include "filters_params.h"

// Estado del pasa-banda de 1 canal (escalado por 2^PB_FRAC)
typedef struct {
    int32_t s_hp[PB_STAGES];
    int32_t s_lp[PB_STAGES];
} pb_state_t;

// Estado del eco de 1 canal
typedef struct {
    int16_t *buf; // buffer circular de ECHO_D_MAX muestras (salida y) 
    uint32_t idx; // posicion actual en el buffer                      
    uint32_t d;   // retardo en muestras (depende de fs)               
} eco_state_t;

// * Configura filtros para una frecuencia de muestreo y borra su estado.
// * Frecuencia de muestreo(fs): 8000, 16000 o 44100. Devuelve 0 si fs es valida, -1 si no.
// * Se llama al empezar cada cancion.
int filters_sw_init(uint32_t fs);

// Borra el estado de los filtros (al cambiar de filtro o de cancion)
void filters_sw_reset(void);

// Procesa una muestra de un canal
int16_t pb_process(pb_state_t *st, int16_t x);
int16_t eco_process(eco_state_t *st, int16_t x);

// Procesa un par empaquetado como en el WAV y en SAMPLE_IN/SAMPLE_OUT:
//bits [15:0] = L, bits [31:16] = R.
uint32_t pb_frame(uint32_t lr);
uint32_t eco_frame(uint32_t lr);

#endif

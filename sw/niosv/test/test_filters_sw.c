/*====================================================================================
 * ~~~~~ Prueba en la PC de filters_sw.c (para issue F-07 en repo) ~~~~~
 *
 * Para cada fs y cada caso, procesa <filtro>_<fs>_<caso>_in.txt y compara bit a bit
 * contra <filtro>_<fs>_<caso>_out.txt (generados por tools/gen_coefs.py)
 * Formato de cada linea: "L R" en decimal
 *
 * Se compila y corre con sw/niosv/test/run_test_filters_sw.sh
 =====================================================================================
 */
#include <stdio.h>
#include <stdint.h>
#include "filters_sw.h"
#define MAX_REPORT 10
typedef uint32_t (*frame_fn)(uint32_t);
static int total_err = 0;
static int total_fail = 0;
static int total_frames = 0;

static void run_case(const char *dir, const char *filtro, uint32_t fs, const char *caso, frame_fn fn) {
    char f_in[512], f_out[512];
    snprintf(f_in,  sizeof f_in,  "%s/%s_%u_%s_in.txt",  dir, filtro, fs, caso);
    snprintf(f_out, sizeof f_out, "%s/%s_%u_%s_out.txt", dir, filtro, fs, caso);
    FILE *fi = fopen(f_in, "r");
    FILE *fo = fopen(f_out, "r");
    if (!fi || !fo) {
        printf("[FAIL] no se pudo abrir %s o %s\n", f_in, f_out);
        total_fail++;
        if (fi) fclose(fi);
        if (fo) fclose(fo);
        return;
    }
    filters_sw_init(fs); // cada caso empieza con estado en 0 

    int l, r, el, er, frames = 0, errs = 0;
    while (fscanf(fi, "%d %d", &l, &r) == 2) {
        if (fscanf(fo, "%d %d", &el, &er) != 2) {
            printf("  [ERROR] %s tiene menos lineas que %s\n", f_out, f_in);
            errs++;
            break;
        }
        uint32_t in  = ((uint32_t)(uint16_t)r << 16) | (uint16_t)l;
        uint32_t out = fn(in);
        int16_t  yl  = (int16_t)(out & 0xFFFFu);
        int16_t  yr  = (int16_t)(out >> 16);
        if (yl != el || yr != er) {
            if (errs < MAX_REPORT)
                printf("  [ERROR] %s fs=%u %s par %d: L=%d R=%d  esperado L=%d R=%d\n",
                       filtro, fs, caso, frames, yl, yr, el, er);
            errs++;
        }
        frames++;
    }
    fclose(fi);
    fclose(fo);
    total_err    += errs;
    total_frames += frames;
    if (errs || frames == 0) total_fail++;
    printf("[%s] %s fs=%u %s: %d pares, %d errores\n", (errs == 0 && frames > 0) ? "PASS" : "FAIL", filtro, fs, caso, frames, errs);
}

int main(int argc, char **argv) {
    const char *dir = (argc > 1) ? argv[1] : "sim/vectors";
    const uint32_t fs_list[] = { 8000, 16000, 44100 };
    const char *casos_pb[]   = { "impulso", "escalon", "seno_paso", "seno_rechazo", "ruido" };
    const char *casos_eco[]  = { "impulso", "ruido" };
    printf("=== test_filters_sw (vectores en %s) ===\n", dir);
    if (filters_sw_init(12345) != -1) {
        printf("[FAIL] filters_sw_init acepto una fs invalida\n");
        total_fail++;
    } else {
        printf("[PASS] filters_sw_init rechaza fs invalida\n");
    }
    for (unsigned f = 0; f < 3; f++) {
        for (unsigned c = 0; c < 5; c++)
            run_case(dir, "pb", fs_list[f], casos_pb[c], pb_frame);
        for (unsigned c = 0; c < 2; c++)
            run_case(dir, "eco", fs_list[f], casos_eco[c], eco_frame);
    }

    printf("---------------------------------------------\n");
    printf("Pares procesados: %d | errores: %d\n", total_frames, total_err);
    printf("RESULTADO: %s\n", (total_err == 0 && total_fail == 0) ? "PASS" : "FAIL");
    printf("---------------------------------------------\n");
    return (total_err == 0 && total_fail == 0) ? 0 : 1;
}

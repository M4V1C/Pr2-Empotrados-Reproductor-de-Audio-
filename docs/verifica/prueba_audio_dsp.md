# Verificación de `audio_dsp` (módulo personalizado de HW)

Verificación **aislada** del módulo de hardware personalizado **antes de integrarlo** al sistema. El módulo se prueba completo, por el bus **Avalon-MM**, igual que si lo usara el Nios V.

## 1. Qué verifica?

| Elemento | Archivo |
|---|---|
| Módulo bajo prueba (DUT) | `hw/ip/audio_dsp/audio_dsp.v` (con `fir_pbajo.v`, `ganancia.v` y `time_7seg.v`) |
| Testbench | `sim/tb_audio_dsp.sv` |
| Script | `sim/run_audio_dsp.sh` |
| Vectores de referencia | `sim/vectors/` (generados por `tools/gen_coefs.py`) |
| Resultado de la corrida | `docs/verifica/tb_audio_dsp.txt` |

**Entorno:** Questa Altera Starter FPGA Edition 2025.2, reloj de 50 MHz (periodo de 20 ns)

## 2. Método utilizado

- **Acceso por el bus:** El testbench se comporta como lo haría el Nios, cada lectura y escritura respeta `waitrequest`. No se fuerzan cambios en señales internas.
- **Comparación bit a bit** contra el **modelo de referencia** diseñado en Python (`model_fir`), este tiene la misma aritmética que el RTL (Q1.15, acumulador de 37 bits, redondeo y saturación). Para la ganancia, el esperado se calcula en el testbench con la misma fórmula que `ganancia.v`.
- **Tres frecuencias de muestreo** (8, 16 y 44.1 kHz), cada una con su juego de coeficientes, cargado por el bus.
- **Casos límite del bus:** lecturas en todos los ciclos posibles durante el cálculo, y escrituras también.
- **Pruebas negativas:** se comprueba que una función **cambia** el resultado cuando debería (por ejemplo, sin `HIST_CLR` el resultado tiene que ser distinto).
- **Casos pendientes:** lo que depende de un módulo que todavía no está completo se marca `[PEND]` en lugar de `[FAIL]`. El mismo testbench lo verifica cuando el módulo esté listo, sin necesidad de realizar más cambios.

## 3. Casos de prueba y resultados obtenidos del TB

| Caso | Objetivo | Procedimiento | Criterio de aceptación | Resultado |
|---|---|---|---|---|
| **TC1** | Identificación | Leer `ID` | `0x41554431` ("AUD1") | PASS |
| **TC2** | Bypass | `FIR_EN = 0`, 2000 pares de ruido por `SAMPLE_IN` | `SAMPLE_OUT = SAMPLE_IN` en todos, **0 ciclos** de `waitrequest` | PASS |
| **TC3** | Respuesta al impulso | Por cada fs: cargar y releer `COEF[0..31]`, `HIST_CLR`, impulso | Coeficientes releídos iguales; salida igual al modelo (la lista de coeficientes) | PASS (8, 16 y 44.1 kHz) |
| **TC4** | Respuesta a señales | Por cada fs: escalón, seno en banda de paso y seno en banda de rechazo | Igual al modelo, bit a bit | PASS (8, 16 y 44.1 kHz) |
| **TC5** | Señal aleatoria | Por cada fs: 2000 pares de ruido en todo el rango de int16 | Igual al modelo, bit a bit | PASS (8, 16 y 44.1 kHz) |
| **TC6** | Saturación acumulada | Borrar `SAT`, procesar el vector de saturación, después un par normal; escribir 0 y luego 1 en `STATUS.SAT` | `SAT` se enciende, **sigue** encendida con pares normales, escribir 0 **no** la borra y escribir 1 **sí** (W1C) | PASS |
| **TC7** | `HIST_CLR` y recarga de coeficientes | Ensuciar el historial con coeficientes de 8 kHz, recargar los de 44.1 kHz, `HIST_CLR` e impulso. Repetir **sin** `HIST_CLR` | Con `HIST_CLR`: igual al modelo desde el primer par. Sin `HIST_CLR`: el resultado **difiere** (prueba negativa) | PASS |
| **TC8 (a)** | `SAMPLE_OUT` nunca devuelve un dato viejo | Para n = 0…70: dejar una marca en `SAMPLE_OUT`, escribir una muestra al FIR, esperar n ciclos y leer | Siempre el resultado nuevo, incluido el ciclo exacto en que termina el FIR | PASS |
| **TC8 (b)** | `STATUS` accesible durante el cálculo | Escribir una muestra y leer `STATUS` de inmediato | `BUSY = 1` sin `waitrequest`; `BUSY = 0` al terminar | PASS |
| **TC8 (c)** | Escrituras durante el cálculo | Escribir `SAMPLE_IN` y `COEF[0]` mientras el FIR calcula | La escritura **espera** (`waitrequest` > 0); el resultado y el coeficiente quedan correctos | PASS |
| **TC9** | Ganancia sobre el FIR | Seno a 44.1 kHz con `GAIN` = 2048, 0 y 4096; después `GAIN` = 8191 con muestras extremas | Igual a `sat16((y_modelo × GAIN) >>> 12)`; con ×2 la salida se satura y `SAT` se enciende | PASS |
| **TC10 (a)** | `FRAME_CNT` y `TIME_CLR` | `FS = 4`; contar 244 pares; `TIME_CLR`; contar con `TIME_EN = 0` | `FRAME_CNT` = 244, 0 tras `TIME_CLR`, y cuenta aunque `TIME_EN = 0` | PASS |
| **TC10 (b)** | Tiempo MM:SS | `FS = 4`, 244 pares con `TIME_EN = 1` (61 s) | `TIME` = 01:01; 00:00 tras `TIME_CLR` | **PEND**: `time_7seg` todavía está en proceso |

**Resumen:** 18 casos en PASS, 1 pendiente, **0 errores**. Detalle y fecha en `tb_audio_dsp.txt`.

## 4. Hallazgos durante la verificación y arreglos

| Hallazgo | Lugar | Corrección |
|---|---|---|
| El vector de saturación del modelo tenía en el canal R el valor −(−32768) = +32768, lo cual no cabe en int16. El testbench del FIR lo encontró y falló: el hardware recibía −32768 y el modelo calculaba con +32768 | `tools/gen_coefs.py` | Se satura el canal R con `sat16(-v)` y se regeneraron los vectores |
| En el ciclo en que el FIR termina (`done = 1`), `busy` ya vale 0 pero `SAMPLE_OUT` todavía no se actualizó: una lectura en ese ciclo devolvería el resultado anterior | `audio_dsp.v` | Señal `ocupado = busy OR done` para `waitrequest` y `STATUS.BUSY`. Se añade el caso para verificarlo: **TC8 (a)** |

## 5. Cómo repetir la verificación?

```bash
# Desde: raíz del repo (con vlib/vlog/vsim en el PATH)
python tools/gen_coefs.py  # solo si cambiaron los parámetros de los filtros
sim/run_audio_dsp.sh       # esta solo es por consola; genera el log en sim/audio_dsp.log
sim/run_audio_dsp.sh gui   # esta abre el waveform
```

## 6. Otros archivos de pruebas unitarias

| Prueba | Qué cubre | Resultado |
|---|---|---|
| `tb_fir_pbajo.txt` | `fir_pbajo` aislado: 10 032 pares en 3 fs, 67 ciclos por par | PASS |
| `tb_ganancia.txt` | `ganancia` aislada: bordes, ×1 exacto y 20 000 pares aleatorios | PASS |
| `tb_audio_dsp_humo.txt` | Smoke test inicial de `audio_dsp` | PASS |
| `test_filters_sw.txt` | Filtros de software del Nios (pasa-banda y eco) en PC host y revisión RV32I | PASS |

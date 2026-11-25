# sim/vectors - GENERADO por tools/gen_coefs.py (no editar a mano)

## Formatos
- `coefs_<fs>.hex`: 32 lineas, 4 hex por linea = coeficiente Q1.15 en complemento a 2.
- `fir_<fs>_<caso>_in.hex` / `_out.hex`: una linea por par de muestras,
  8 hex = `R[31:16] L[15:0]` (mismo empaquetado que SAMPLE_IN / SAMPLE_OUT).
  Para `$readmemh` en el testbench.
- `<filtro>_<fs>_<caso>_in.txt` / `_out.txt` (filtro = pb | eco): una linea por par,
  decimal `L R`. Para la prueba en PC de filters_sw.c.

## Casos
impulso, escalon, seno_paso, seno_rechazo, ruido (semilla fija) y, solo FIR, saturacion.
El estado de todos los filtros empieza en cero.

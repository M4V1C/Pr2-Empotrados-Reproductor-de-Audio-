# Módulo de almacenamiento — diseño detallado

Cubre `sw/storage/`: parser WAV, playlist y su verificación. Para uso rápido ver el
[README](../README.md).

## 1. Decisión: Linux mínimo en el HPS, no bare-metal

| Criterio | Linux mínimo (Buildroot) | Bare-metal |
|---|---|---|
| Controlador SD (DW-MMC) | Driver del kernel | Hay que escribirlo e inicializar la tarjeta |
| Sistema de archivos | FAT/VFAT del kernel, nombres largos | Integrar FatFs |
| Prueba en QEMU | El código se prueba tal cual; solo cambian kernel y device tree | QEMU emula PL181, la placa usa DW-MMC: el driver probado no sirve |
| Arranque < 10 s | Hay que medirlo y recortar el kernel | Inmediato |
| Latencia | Mayor y menos determinista | Mínima |
| Encaje con el enunciado | "SO mínimo" para ARM | Los punteros directos sin HAL aplican a Nios V |

**Conclusión:** la SD está conectada al HPS, y escribir y depurar un driver MMC y FAT no
aporta al objetivo del proyecto. Las partes de tiempo real (audio, filtros) quedan en el
Nios V bare-metal, donde el enunciado exige acceso directo por punteros.

**Riesgo abierto:** el arranque debe ser < 10 s en la placa. No se ha medido.

## 2. Capas

```
 UI / reproductor  (pendiente)
        │
  playlist.c   ── escaneo, orden, respaldo de metadatos
        │
  wav_meta.c   ── parser RIFF/WAV + LIST/INFO
        │
  stdio (fopen/fseeko/fread)
        │
  VFS de Linux ── FAT32 ── driver MMC ── SD
```

Solo se usa stdio y POSIX (`opendir`, `readdir`). Por eso el mismo código corre en el PC, en
`qemu-arm` y en el Linux emulado, sin cambios.

## 3. API

```c
/* wav_meta.h */
wav_status_t wav_parse(FILE *f, wav_info_t *out);
wav_status_t wav_parse_file(const char *path, wav_info_t *out);

/* playlist.h */
int playlist_scan(playlist_t *pl, const char *dir);   /* n canciones, o -1 */
```

`wav_status_t`:

| Valor | Significado |
|---|---|
| `WAV_OK` | Parseo correcto |
| `WAV_ERR_IO` | Fallo al abrir, leer o posicionar |
| `WAV_ERR_FORMAT` | No es RIFF/WAVE, o faltan los chunks `fmt ` o `data` |
| `WAV_ERR_UNSUPPORTED` | No es PCM 16 bit, 1–2 canales, 8000/16000/44100 Hz |

`wav_info_t` expone `sample_rate`, `channels`, `bits_per_sample`, `data_offset` y
`data_size` (para que el reproductor lea las muestras sin reparsear), `duration_ms` y las
tres etiquetas.

## 4. Algoritmo del parser

1. Valida `RIFF` … `WAVE` (12 bytes) y obtiene el tamaño del archivo.
2. Recorre los chunks con `fseeko`: lee 8 bytes (`id`, `size` little-endian) y avanza
   `size + (size & 1)`, porque los chunks se alinean a byte par.
3. Según el `id`:
   - `fmt `: valida PCM (`format == 1`), 16 bit, 1–2 canales y frecuencia soportada.
   - `data`: guarda `offset` y `size`; no lee las muestras.
   - `LIST`: si el tipo es `INFO`, recorre sus subchunks `INAM`, `IART`, `IPRD`.
   - Otros (`fact`, `bext`…): se saltan.
4. Calcula `duration_ms = data_size × 1000 / (rate × channels × 2)`.

### Casos que maneja

| Caso | Tratamiento |
|---|---|
| `LIST` antes o después de `data` | Ambos funcionan: se recorre todo el archivo |
| Etiqueta de longitud impar | Respeta el relleno de un byte |
| Cadenas con NUL o espacios finales | Se recortan |
| `data` declara más bytes de los que hay | Se acota al tamaño real del archivo |
| Chunk no-`data` truncado | Se detiene el recorrido y evalúa lo leído |
| Subchunk `INFO` corrupto | Se ignora el resto del `LIST` |
| Etiqueta mayor a 63 caracteres | Se trunca a 63 |
| Archivo vacío o que no es WAV | `WAV_ERR_FORMAT` |
| Archivo inexistente | `WAV_ERR_IO` |

El parser no hace asignación dinámica y solo guarda los 212 bytes de `wav_info_t`.

## 5. Playlist

1. `opendir` + `readdir`, filtrando `*.wav` sin distinguir mayúsculas, hasta
   `PLAYLIST_MAX` (32) entradas.
2. `qsort` por ruta con `strcasecmp`.
3. Parsea cada una; las que fallen (no WAV, formato no soportado) se descartan y la lista se
   compacta.
4. Rellena los campos vacíos desde el nombre (`fill_from_filename`).

Memoria: `playlist_t` es estática (~15 KB). El llamador la declara `static` para no
cargar la pila.

## 6. Verificación

### 6.1 Pruebas unitarias (`tests/test_storage.c`)

31 verificaciones sobre WAV sintéticos escritos en un directorio temporal:

| Prueba | Valida |
|---|---|
| `info_before_data` | Etiquetas, relleno de longitud impar, duración 2000 ms |
| `info_after_data_stereo` | `LIST` tras `data`, 44.1 kHz estéreo, 1000 ms |
| `no_info` | Etiquetas vacías sin error |
| `unsupported` | 8 bit, 22050 Hz y float → `WAV_ERR_UNSUPPORTED` |
| `bad_files` | Texto, archivo vacío, ruta inexistente |
| `truncated_data` | `data_size` acotado al tamaño real |
| `playlist` | Orden, respaldo por nombre, descarte de WAV malo y de `.txt` |

### 6.2 Tres niveles de ejecución

| Nivel | Qué cambia respecto al anterior |
|---|---|
| PC x86_64 | Lógica |
| `qemu-arm` (modo usuario) | Arquitectura: ARM 32 bit, `off_t`, endianness |
| `qemu-system-arm` + Linux 6.12.9 | Kernel real: driver MMC, montaje FAT32, nombres largos |

El nivel 3 usa Buildroot 2025.02 (toolchain glibc, Cortex-A9 con VFPv3), con el rootfs como
initramfs para dejar libre la única ranura SD de `vexpress-a9`. El kernel se configura con
`vexpress_defconfig` más `tools/buildroot/linux.fragment` (MMC, FAT, VFAT, `iso8859-1`).
El script `S99storage-test` espera a `/dev/mmcblk0`, monta la SD en solo lectura, ejecuta
`main_list` y apaga.

### 6.3 Lo que NO está verificado

- Controlador SD real (DW-MMC) en la DE1-SoC.
- Tiempos: arranque < 10 s y cambio de canción < 2 s.
- Lectura continua de muestras bajo carga; hoy solo se leen cabeceras.
- Etiquetas UTF-8 en el display.
- SD físicas de otros fabricantes o con FAT fragmentada.

## 7. Siguientes pasos

1. Lectura por bloques de `data_offset`/`data_size` hacia un buffer circular.
2. Definir con el Nios V el mailbox y el mapa de memoria compartida.
3. Kernel y device tree para el HPS de la DE1-SoC; medir el arranque.
4. Hilo de lectura con prioridad y manejo de fin de canción.

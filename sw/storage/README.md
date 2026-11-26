# Almacenamiento del HPS — guía de integración

Librería en C para el **HPS (Linux)** que lee las canciones de la tarjeta SD y las entrega
listas para enviarse al Nios V. Está pensada para que quien conecte el HPS con el Nios V la
use **sin leer su código**.

## Qué hace y qué no

| Hace | No hace (lo hacen otros) |
|---|---|
| Listar las canciones WAV de la SD con título, artista, álbum y duración | La comunicación HPS ↔ Nios V (buffer circular, comandos) |
| Entregar las muestras de una canción en bloques, listas para el Nios V | El Linux de arranque de la placa (issue A-09) |
| Funcionar igual en el PC, en QEMU y en la placa | Botones, pantalla y control de la lista (issue A-10) |

## Contenido del paquete

`make -C sw/storage dist` genera `sw/storage/build/storage-hps.tar.gz`:

```
storage-hps/
├── include/   wav_meta.h  playlist.h  track_reader.h
├── lib/       libstorage.a              (ARM de 32 bits, hard-float)
├── bin/       main_list  main_read      (ARM, estáticos: no necesitan librerías en la placa)
├── tools/     gen_wavs.py  mk_sdimg.sh  (WAV de prueba e imagen de SD para QEMU)
└── README.md  esta guía
```

## API

Tres módulos. Todos usan memoria del llamador, **sin `malloc`**.

### `playlist.h`: qué canciones hay

```c
static playlist_t pl;                       /* ~15 KB; declarar static, no en la pila */
int n = playlist_scan(&pl, "/mnt/sd");      /* n canciones, o -1 si no se pudo abrir */
/* pl.tracks[i].path, pl.tracks[i].info.title / .artist / .album */
/* pl.tracks[i].info.duration_ms, .sample_rate, .channels */
```

Las canciones salen ordenadas por nombre (sin distinguir mayúsculas). Los WAV no
soportados se descartan. Si un WAV no trae etiquetas se usa el nombre del archivo:
`Artista - Titulo.wav`.

### `track_reader.h`: las muestras de una canción

Bucle típico de un hilo productor (una canción). Las funciones `shm_load`, `ring_libres` y
`ring_escribir` son **de ejemplo**: las define quien conecte con el Nios V.

```c
track_reader_t r;
if (track_open(&r, pl.tracks[i].path, &pl.tracks[i].info) != 0) { /* error */ }
shm_load(pl.tracks[i].info.sample_rate, r.total_frames, i + 1);   /* avisar al Nios V */

uint32_t bloque[1024];
for (;;) {
    uint32_t libres = ring_libres();                    /* huecos en el buffer compartido */
    if (libres == 0) { usleep(10000); continue; }       /* lleno: esperar a que el Nios consuma */

    size_t pedir = libres < 1024 ? libres : 1024;       /* NUNCA pedir más de lo que cabe */
    size_t n = track_read(&r, bloque, pedir);
    if (n == 0)
        break;                                          /* 0 = fin de la canción (o error) */
    ring_escribir(bloque, n);                           /* copiar y avanzar el puntero */
}

if (r.error != TRACK_ERR_NONE) { /* archivo truncado o fallo de lectura */ }
track_close(&r);
```

> **Importante:** `track_read` *consume*: cada llamada avanza la posición en el archivo. Si se
> piden más tramas de las que caben en el buffer y se descartan, se pierden y se oye un salto.
> Por eso el ejemplo pide solo `libres` (o guarda el sobrante para la siguiente vuelta).
> `main_read.c` es el mismo bucle sin el buffer: sirve como ejemplo compilable.

Cómo encajan los controles del reproductor:

| Acción | Qué hace el HPS |
|---|---|
| Pausa | Enviar `PAUSE`; el hilo sigue hasta llenar el buffer y espera (`libres == 0`) |
| Siguiente / anterior | Cortar el bucle, `track_close`, abrir la otra canción y enviar un nuevo `LOAD` |
| Stop | Cortar el bucle, `track_close` y enviar `STOP` |
| Fin de canción | `track_read` devuelve 0; esperar a que el Nios V confirme y abrir la siguiente |

- Cada elemento es una **trama estéreo de 32 bits**: `[15:0]` = izquierdo y `[31:16]` =
  derecho, PCM de 16 bits con signo. Es el mismo formato que `SAMPLE_IN` de `audio_dsp`.
- Los WAV **mono se duplican** (L = R): siempre se recibe estéreo.
- `track_read` devuelve las tramas escritas. **`0` significa fin de la canción** (o error:
  revisar `r.error`).
- `r.total_frames` y `r.remaining` sirven para informar el total al Nios V (por ejemplo, en
  el comando `LOAD`) y para saber cuánto falta.
- `track_seek(&r, trama)` salta a otra posición; `track_seek(&r, 0)` reinicia la canción.
- La frecuencia (8000, 16000 o 44100 Hz) está en `info.sample_rate`. Hay que configurarla en
  el Nios V antes de empezar a enviar muestras.

### `wav_meta.h`: el parser (de bajo nivel)

`wav_parse_file(path, &info)` devuelve `WAV_OK`, `WAV_ERR_IO`, `WAV_ERR_FORMAT` o
`WAV_ERR_UNSUPPORTED`. Normalmente no hace falta llamarlo: `playlist_scan` ya lo usa.

## Formato de la tarjeta SD

- Sistema de archivos **FAT32**; los `.wav` en la **raíz**.
- WAV PCM de **16 bits**, 1 o 2 canales, **8000, 16000 o 44100 Hz**. Otros formatos se ignoran.
- Metadatos en el chunk `LIST/INFO`: `INAM` (título), `IART` (artista), `IPRD` (álbum), hasta
  63 caracteres cada uno. La duración se calcula del tamaño de los datos.
- Hasta **32 canciones** (`PLAYLIST_MAX` en `playlist.h`).
- Para escribir las etiquetas:
  `ffmpeg -i in.wav -metadata title="..." -metadata artist="..." -metadata album="..." out.wav`
- **En una tarjeta real basta con formatear en FAT32 y copiar los archivos.** No hace falta
  `mk_sdimg.sh`; esa herramienta arma una *imagen* para QEMU.

## Compilar

Requisitos (Debian): `build-essential`, `gcc-arm-linux-gnueabihf`, `python3`.

| Objetivo | Comando (desde `sw/storage/`) |
|---|---|
| Pruebas unitarias en el PC | `make test` |
| Compilar para el PC | `make` |
| Compilar para ARM (estático) | `make build/main_list_arm build/main_read_arm` |
| Paquete para integrar | `make dist` |
| WAV de prueba e imagen de SD | `make wavs` / `make sdimg` |

Para usar la librería en otro programa ARM:

```bash
arm-linux-gnueabihf-gcc -std=c11 -O2 -Iinclude mi_app.c lib/libstorage.a -o mi_app
```

## Cómo probar

| Dónde | Comando | Resultado esperado |
|---|---|---|
| PC | `make test` | `... verificaciones, 0 fallos` |
| PC | `make list` · `make read` | tabla de canciones · todas las tramas `OK` |
| ARM de usuario (`qemu-arm`) | `make list-arm` · `make read-arm` | igual que en el PC |
| Linux completo (QEMU) | `bash tools/run_qemu.sh` (desde la raíz del repo) | monta la SD y lista las 11 canciones |
| **Placa** | `main_list /mnt/sd` y `main_read /mnt/sd` | tabla de 11 canciones y `0 con fallo` |

En la placa, `main_read` imprime también el rendimiento de lectura (MB/s). Para audio a
44,1 kHz estéreo se necesitan ≈ **0,17 MB/s**, así que cualquier tarjeta sobra; el dato sirve
para detectar tarjetas defectuosas. (Bajo QEMU el valor no es representativo.)

## Límites conocidos

- Solo probado en PC y en QEMU. **Falta probarlo en la DE1-SoC** (issue A-11).
- Las etiquetas no se convierten: el texto no ASCII (UTF-8) puede verse mal en un display.
- Una ruta de más de 255 caracteres se omite.
- `track_read` es bloqueante: llamarlo desde un hilo dedicado, no desde la interfaz.

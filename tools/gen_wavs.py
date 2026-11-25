#!/usr/bin/env python3
"""Genera WAV sinteticos (PCM 16 bit) con metadatos LIST/INFO para probar el
reproductor. Solo usa la biblioteca estandar.

Uso: gen_wavs.py <directorio_salida>

Deja 10 canciones con INAM/IART/IPRD (8, 16 y 44.1 kHz; mono y estereo) y una
sin etiquetas, para ejercitar el respaldo por nombre de archivo.
"""
import math
import os
import struct
import sys

# (archivo, titulo, artista, album, frecuencia_Hz, canales, segundos, notas)
# Las notas son frecuencias en Hz; cada cancion suena distinta.
CATALOGO = [
    ("01_Aurora.wav",     "Aurora",          "Los Empotrados", "Primer Boot",   44100, 2, 8, [262, 330, 392, 523]),
    ("02_Interrupcion.wav", "Interrupcion",  "Los Empotrados", "Primer Boot",   44100, 2, 7, [440, 440, 523, 659]),
    ("03_Latencia.wav",   "Latencia",        "Nios Quartet",   "Registros",     44100, 1, 8, [330, 294, 262, 294]),
    ("04_Buffer.wav",     "Buffer Circular", "Nios Quartet",   "Registros",     44100, 2, 6, [392, 494, 587, 494]),
    ("05_Pipeline.wav",   "Pipeline",        "Cyclone Five",   "Logica",        16000, 1, 9, [220, 277, 330, 440]),
    ("06_Mailbox.wav",    "Mailbox",         "Cyclone Five",   "Logica",        16000, 2, 8, [349, 440, 523, 440]),
    ("07_Watchdog.wav",   "Watchdog",        "Cyclone Five",   "Logica",        16000, 1, 7, [262, 262, 392, 392]),
    ("08_Handshake.wav",  "Handshake",       "Bus Avalon",     "Maestro Esclavo", 8000, 1, 10, [294, 370, 440, 370]),
    ("09_Overflow.wav",   "Overflow",        "Bus Avalon",     "Maestro Esclavo", 8000, 1, 8, [247, 311, 370, 494]),
    ("10_Sin_Fin.wav",    "Sin Fin",         "Bus Avalon",     "Maestro Esclavo", 8000, 1, 9, [196, 247, 294, 392]),
    # Sin LIST/INFO: debe salir "Sin Etiquetas" / "Cancion Pelada" por el nombre
    ("Sin Etiquetas - Cancion Pelada.wav", None, None, None, 16000, 1, 6, [330, 330, 440, 330]),
]


def sub(cid, texto):
    datos = texto.encode("ascii") + b"\0"
    if len(datos) & 1:
        datos += b"\0"  # subchunks alineados a byte par
    return cid + struct.pack("<I", len(texto) + 1) + datos


def chunk_list(titulo, artista, album):
    cuerpo = b"INFO" + sub(b"INAM", titulo) + sub(b"IART", artista) + sub(b"IPRD", album)
    return b"LIST" + struct.pack("<I", len(cuerpo)) + cuerpo


def muestras(rate, canales, segundos, notas):
    n = rate * segundos
    por_nota = n // len(notas)
    out = bytearray()
    for i in range(n):
        f = notas[min(i // por_nota, len(notas) - 1)]
        t = (i % por_nota) / por_nota
        env = min(1.0, t * 20) * min(1.0, (1 - t) * 8)  # evita clics entre notas
        v = int(12000 * env * math.sin(2 * math.pi * f * i / rate))
        out += struct.pack("<h", v) * canales
    return bytes(out)


def escribir(ruta, titulo, artista, album, rate, canales, segundos, notas):
    datos = muestras(rate, canales, segundos, notas)
    fmt = b"fmt " + struct.pack("<IHHIIHH", 16, 1, canales, rate, rate * canales * 2, canales * 2, 16)
    lista = chunk_list(titulo, artista, album) if titulo else b""
    data = b"data" + struct.pack("<I", len(datos)) + datos
    cuerpo = b"WAVE" + fmt + lista + data
    with open(ruta, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(cuerpo)) + cuerpo)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    salida = sys.argv[1]
    os.makedirs(salida, exist_ok=True)
    for nombre, titulo, artista, album, rate, canales, seg, notas in CATALOGO:
        escribir(os.path.join(salida, nombre), titulo, artista, album, rate, canales, seg, notas)
        print(f"{nombre}: {rate} Hz, {canales} canal(es), {seg} s")


if __name__ == "__main__":
    main()

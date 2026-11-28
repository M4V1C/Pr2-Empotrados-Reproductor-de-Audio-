#!/usr/bin/env python3
"""
===========================================================================================
    ~~~~~ Pasa un WAV real por los 3 filtros del proyecto ~~~~~

Usa los modelos bit a bit de gen_coefs.py: lo que se escucha aqui es lo que dan el HW(FIR)
y el Nios V (pasa-banda y eco).

Entrada: WAV PCM de 16 bits, mono o estereo, a 8000, 16000 o 44100 Hz
Salida (por cada fragmento):
    <salida>/<nombre>_<fs>_{original,fir,pb,eco}.wav   para escuchar
    docs/img/espectro_<nombre>_<fs>.png                espectrogramas antes/despues
    docs/img/fft_<nombre>_<fs>.png                     espectro promedio de los 4

Uso (desde la raiz del repo):
  python tools/filtrar_wav.py "<archivo.wav>" [--inicio 45] [--dur 15]
  (comillas en el nombre del archivo si la ruta tiene espacios)
===========================================================================================
"""
import argparse
import re
import sys
import wave
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_coefs import (FS_LIST, PB_K, Q_FRAC, ECHO_MS, ECHO_SHIFT, FIR_FC, # noqa: E402
                       fir_coefs, model_fir, model_pb, model_echo, echo_delay)
ROOT = Path(__file__).resolve().parent.parent
N_VERIFICA = 4000 # muestras para comprobar que el FIR rapido = model_fir

# ===========================================================================================================
# Archivo WAV
# ===========================================================================================================
def leer_wav(ruta: Path, inicio_s: float, dur_s: float):
    """Devuelve (fs, L, R) como arreglos int16 del fragmento pedido."""
    with wave.open(str(ruta), "rb") as w:
        canales, ancho, fs, n_total = (w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes())
        if ancho != 2:
            sys.exit(f"El WAV debe ser de 16 bits (es de {8 * ancho}).")
        if fs not in FS_LIST:
            sys.exit(f"fs = {fs} Hz no es del proyecto {FS_LIST}. Convertir antes con ffmpeg.")
        primero = min(int(inicio_s * fs), n_total)
        w.setpos(primero)
        datos = np.frombuffer(w.readframes(int(dur_s * fs)), dtype="<i2")
    if canales == 1:
        return fs, datos.copy(), datos.copy()
    datos = datos.reshape(-1, canales)
    return fs, datos[:, 0].copy(), datos[:, 1].copy()

def nombre_limpio(ruta: Path) -> str:
    """'Suite Doble - Profanar.wav' -> 'suite_doble_profanar' (sin espacios ni tildes)."""
    return re.sub(r"[^a-z0-9]+", "_", ruta.stem.lower()).strip("_") or "audio"

def relativa(ruta: Path) -> str:
    """Ruta respecto a la raiz del repo (si esta dentro), para imprimirla."""
    ruta = ruta.resolve()
    return str(ruta.relative_to(ROOT)) if ruta.is_relative_to(ROOT) else str(ruta)


def escribir_wav(ruta: Path, fs: int, izq, der) -> None:
    estereo = np.empty(2 * len(izq), dtype="<i2")
    estereo[0::2] = izq
    estereo[1::2] = der
    with wave.open(str(ruta), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(fs)
        w.writeframes(estereo.tobytes())

# =============================================================================
# Filtros (bit a bit iguales a los modelos)
# =============================================================================
def fir_rapido(x: np.ndarray, h: list[int]) -> np.ndarray:
    """Mismo calculo que model_fir, con numpy (enteros de 64 bits, exacto)."""
    acc = np.convolve(x.astype(np.int64), np.array(h, dtype=np.int64))[:len(x)]
    y = (acc + (1 << (Q_FRAC - 1))) >> Q_FRAC
    return np.clip(y, -32768, 32767).astype(np.int16)

def aplicar(fs: int, x: np.ndarray, h: list[int]) -> dict[str, np.ndarray]:
    """Devuelve la salida de cada filtro para un canal."""
    y_fir = fir_rapido(x, h)
    referencia = model_fir(x[:N_VERIFICA].tolist(), h)
    if y_fir[:N_VERIFICA].tolist() != referencia:
        sys.exit("ERROR: el FIR rapido no coincide con model_fir.")
    lista = x.tolist()
    return {
        "fir": y_fir,
        "pb":  np.array(model_pb(lista, *PB_K[fs]), dtype=np.int16),
        "eco": np.array(model_echo(lista, echo_delay(fs)), dtype=np.int16),
    }

def porcentaje_saturadas(y: np.ndarray) -> float:
    return 100.0 * np.count_nonzero((y == 32767) | (y == -32768)) / len(y)

# =======================================================================================================
# Generar graficas
# =======================================================================================================
TITULOS = {
    "original": "Original",
    "fir": f"Pasa-bajos FIR (HDL), fc = {FIR_FC:.0f} Hz",
    "pb":  "Pasa-banda (Nios)",
    "eco": f"Eco (Nios), {ECHO_MS} ms, realimentacion 2^-{ECHO_SHIFT}",
}

def graficar_espectrogramas(ruta: Path, fs: int, senales: dict[str, np.ndarray], nombre: str) -> None:
    fig, ejes = plt.subplots(4, 1, figsize=(10, 11), sharex=True)
    for eje, (clave, y) in zip(ejes, senales.items()):
        eje.specgram(y.astype(float), NFFT=2048, Fs=fs, noverlap=1024, cmap="magma", vmin=-20, vmax=80)
        eje.set_ylim(0, min(fs / 2, 8000))
        eje.set_title(TITULOS[clave])
        eje.set_ylabel("Frecuencia [Hz]")
    ejes[-1].set_xlabel("Tiempo [s]")
    fig.suptitle(f"{nombre}, fs = {fs} Hz (canal L)")
    fig.tight_layout()
    fig.savefig(ruta, dpi=110)
    plt.close(fig)

def graficar_fft(ruta: Path, fs: int, senales: dict[str, np.ndarray], nombre: str) -> None:
    plt.figure(figsize=(9, 4.8))
    for clave, y in senales.items():
        bloques = y[: len(y) // 4096 * 4096].astype(float).reshape(-1, 4096)
        espectro = np.mean(np.abs(np.fft.rfft(bloques * np.hanning(4096), axis=1)), axis=0)
        f = np.fft.rfftfreq(4096, 1 / fs)
        plt.semilogx(f[1:], 20 * np.log10(espectro[1:] + 1e-9), lw=1, label=TITULOS[clave])
    plt.axvline(FIR_FC, ls="--", c="gray", lw=0.8)
    plt.grid(True, which="both", alpha=0.3)
    plt.title(f"Espectro promedio: {nombre}, fs = {fs} Hz (canal L)")
    plt.xlabel("Frecuencia [Hz]")
    plt.ylabel("Magnitud [dB]")
    plt.legend(fontsize=8)
    plt.tight_layout()
    plt.savefig(ruta, dpi=120)
    plt.close()

# ==============================================================================================================
# Main
# ==============================================================================================================
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("wav", type=Path)
    parser.add_argument("--inicio", type=float, default=45.0, help="segundo de inicio (45)")
    parser.add_argument("--dur", type=float, default=15.0, help="duracion en segundos (15)")
    parser.add_argument("--salida", type=Path, default=ROOT / "build" / "audio_filtros",
                        help="carpeta de los WAV (build/audio_filtros, fuera de git)")
    args = parser.parse_args()
    fs, izq, der = leer_wav(args.wav, args.inicio, args.dur)
    nombre = nombre_limpio(args.wav)
    h = fir_coefs(fs)
    print(f"{args.wav.name}: fs = {fs} Hz, {len(izq)} pares ({len(izq) / fs:.1f} s desde {args.inicio:.0f} s)")
    salida_izq = aplicar(fs, izq, h)
    salida_der = aplicar(fs, der, h)
    print(f"FIR rapido = model_fir en las primeras {N_VERIFICA} muestras de cada canal")
    args.salida.mkdir(parents=True, exist_ok=True)
    img = ROOT / "docs" / "img"
    img.mkdir(parents=True, exist_ok=True)
    escribir_wav(args.salida / f"{nombre}_{fs}_original.wav", fs, izq, der)
    for clave in ("fir", "pb", "eco"):
        escribir_wav(args.salida / f"{nombre}_{fs}_{clave}.wav", fs, salida_izq[clave], salida_der[clave])
    print("\nSalida       Pico   Muestras saturadas")
    senales_izq = {"original": izq, **salida_izq}
    for clave, y in senales_izq.items():
        y2 = np.concatenate([y, (der if clave == "original" else salida_der[clave])])
        print(f"{clave:<10} {int(np.max(np.abs(y2.astype(np.int32)))):>7}   {porcentaje_saturadas(y2):6.2f} %")

    graficar_espectrogramas(img / f"espectro_{nombre}_{fs}.png", fs, senales_izq, nombre)
    graficar_fft(img / f"fft_{nombre}_{fs}.png", fs, senales_izq, nombre)
    print(f"\nWAV:      {relativa(args.salida)}/{nombre}_{fs}_*.wav")
    print(f"Graficas: docs/img/espectro_{nombre}_{fs}.png, docs/img/fft_{nombre}_{fs}.png")

if __name__ == "__main__":
    main()

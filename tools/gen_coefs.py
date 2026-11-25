"""
gen_coefs.py - Para modelo de referencia bit-exact de los 3 filtros (issue F-01).

Genera, a partir de UNA sola fuente:
    -Coeficientes Q1.15 del pasa-bajos FIR para cada fs (filtro de HW, HDL)
    -Parametros de los filtros de SW del Nios (pasa-banda y eco)
    -Vectores de prueba (entrada + salida esperada) para:
       -el testbench del FIR/audio_dsp (F-02, F-04) -> .hex
       -la prueba en PC de filters_sw.c (F-07) -> .txt
    -Graficas de respuesta de los 3 filtros (F-01, F-09)

Uso (desde la RAIZ del repo, con el .venv activo):
    python tools/gen_coefs.py
"""
import argparse
from pathlib import Path
import numpy as np
from scipy.signal import firwin, freqz
import matplotlib
matplotlib.use("Agg")  # sin ventana: solo guarda PNG
import matplotlib.pyplot as plt

# ================================================================================
# ~~~ Parametros de los filtros ~~~
# ================================================================================
#frecuencias en Hz (enunciado)
FS_LIST = (8000, 16000, 44100)  

# ~~~~~~ Filtro 1: pasa-bajos FIR en HDL ~~~~~~
N_TAPS = 32  # taps COEF[0..31]
FIR_FC = 1000.0  # Hz, frecuencia de corte (-6 dB)
Q_FRAC = 15  # coeficientes Q1.15

# ~~~~~~ Filtro 2: pasa-banda SW en Nios ~~~~~~
# fs -> (k del pasa-altos, k del pasa-bajos); alpha = 2^-k
PB_K = {8000: (2, 1), 16000: (3, 1), 44100: (4, 2)}
PB_STAGES = 2  # 2 etapas en cascada de cada lado (12 dB/octava) para qeu se note
PB_FRAC = 8  # bits de precision

# ~~~~~~ Filtro 3: eco/reverberacion en Nios ~~~~~~
ECHO_MS = 100  # retardo en ms
ECHO_SHIFT = 1  # ganancia de realimentacion = 2^-ECHO_SHIFT (1 -> 0.5)

#semilla para los vectores aleatoreos poderlos testear
SEED = 1234  

#signed
INT16_MIN, INT16_MAX = -32768, 32767

# ==========================================================================
# ~~~ Auxiliares de punto fijo necesarios ~~~
# ==========================================================================
def sat16(v: int) -> int:
    #Satura un entero a int16
    return INT16_MAX if v > INT16_MAX else INT16_MIN if v < INT16_MIN else v

def echo_delay(fs: int) -> int:
    #Retardo del eco en muestras para una fs
    return fs * ECHO_MS // 1000

# ==========================================================================
# ~~~ Filtro 1: pasa-bajos FIR (modelo del RTL) ~~~
# ==========================================================================
def fir_coefs(fs: int) -> list[int]:
    #Coeficientes Q1.15 con signo (enteros), redondeados y saturados
    h = firwin(N_TAPS, FIR_FC, fs=fs)  # ventana Hamming por default
    return [sat16(int(round(c * (1 << Q_FRAC)))) for c in h]

def model_fir(x: list[int], h: list[int]) -> list[int]:
    """
    y[n] = sat16( (sum_{k} h[k]*x[n-k] + 2^14) >> 15 )
    - historial inicial en cero
    - acumulador ancho (37 bits en el RTL; acá es entero de Python)
    - '>>' es desplazamiento ARITMETICO (en Verilog: >>> sobre signed)
    """
    hist = [0] * len(h)  # hist[k] = x[n-k]
    y = []
    for s in x:
        hist = [s] + hist[:-1]
        acc = sum(hk * xk for hk, xk in zip(h, hist))
        y.append(sat16((acc + (1 << (Q_FRAC - 1))) >> Q_FRAC))
    return y

# ========================================================================================
# ~~~ Filtro 2: pasa-banda con IIR de 1er orden ~~~
# ========================================================================================
def model_pb(x: list[int], k_hp: int, k_lp: int, stages: int = PB_STAGES) -> list[int]:
    """
    Cada etapa guarda su estado escalado por 2^PB_FRAC:
        s += ((v << F) - s) >> k   (pasa-bajos interno)
        pasa-bajos: v = s >> F
        pasa-altos: v = v - (s >> F)
    Orden: 'stages' pasa-altos y luego 'stages' pasa-bajos; salida saturada.
    En C todo cabe en int32.
    """
    F = PB_FRAC
    s_hp = [0] * stages
    s_lp = [0] * stages
    y = []
    for v in x:
        for i in range(stages):  # pasa-altos
            s_hp[i] += ((v << F) - s_hp[i]) >> k_hp
            v = v - (s_hp[i] >> F)
        for i in range(stages):  # pasa-bajos
            s_lp[i] += ((v << F) - s_lp[i]) >> k_lp
            v = s_lp[i] >> F
        y.append(sat16(v))
    return y

# ===========================================================================
# ~~~ Filtro 3: eco con realimentacion ~~~
# ===========================================================================
def model_echo(x: list[int], d: int, shift: int = ECHO_SHIFT) -> list[int]:
    """
    y[n] = sat16( x[n] + (y[n-D] >> shift) ),  y[n-D] = 0 al inicio.
    En C: buffer circular int16 de D posiciones (guarda y ya saturada).
    """
    buf = [0] * d
    idx = 0
    y = []
    for s in x:
        out = sat16(s + (buf[idx] >> shift))
        buf[idx] = out
        idx = (idx + 1) % d
        y.append(out)
    return y

# =============================================================================================
# ~~~ Señales de prueba (L y R distintas para probar que los canales no se mezclan) ~~~
# =============================================================================================
def to_int16(a) -> list[int]:
    return [sat16(int(round(v))) for v in a]

def test_signals(fs: int, rng: np.random.Generator) -> dict[str, tuple[list[int], list[int]]]:
    n = np.arange
    f_stop = 3000 if fs == 8000 else 5000 # siempre por debajo de fs/2
    sig = {}
    imp = [0] * 64
    imp[0] = INT16_MAX
    sig["impulso"] = (imp, [-v for v in imp])
    sig["escalon"] = ([16384] * 128, [-16384] * 128)
    sig["seno_paso"] = (to_int16(20000 * np.sin(2 * np.pi * 200 * n(512) / fs)),
                        to_int16(20000 * np.cos(2 * np.pi * 300 * n(512) / fs)))
    sig["seno_rechazo"] = (to_int16(20000 * np.sin(2 * np.pi * f_stop * n(512) / fs)),
                           to_int16(20000 * np.cos(2 * np.pi * f_stop * n(512) / fs)))
    sig["ruido"] = (rng.integers(INT16_MIN, INT16_MAX + 1, 2000).tolist(),
                    rng.integers(INT16_MIN, INT16_MAX + 1, 2000).tolist())
    return sig

def saturation_signal(h: list[int], reps: int = 4) -> tuple[list[int], list[int]]:
    #Entrada que lleva al FIR a saturar: x[n-k] = sign(h[k]) * fondo de escala
    pat = [INT16_MAX if c >= 0 else INT16_MIN for c in reversed(h)]
    left = pat * reps
    # sat16: -(-32768) = 32768 no cabe en int16; se satura a 32767, se hace el fix
    return left, [sat16(-v) for v in left]

# ====================================================================================
# ~~~ Escritura de archivos ~~~
# ====================================================================================
def hex16(v: int) -> str:
    return f"{v & 0xFFFF:04X}"

def write_hex_pairs(path: Path, left: list[int], right: list[int]) -> None:
    #Una linea por par: 8 hex = R[31:16] L[15:0] (igual que SAMPLE_IN/OUT)
    path.write_text("".join(f"{hex16(r)}{hex16(l)}\n" for l, r in zip(left, right)))

def write_txt_pairs(path: Path, left: list[int], right: list[int]) -> None:
    #Una linea por par, decimal: 'L R' (para leer con fscanf en C)
    path.write_text("".join(f"{l} {r}\n" for l, r in zip(left, right)))

def write_coefs_h(path: Path, coefs: dict[int, list[int]]) -> None:
    lines = [
        "/* coefs_fir.h - GENERADO por tools/gen_coefs.py. */",
        "#ifndef COEFS_FIR_H",
        "#define COEFS_FIR_H",
        "",
        "#include <stdint.h>",
        "",
        f"#define FIR_N_TAPS {N_TAPS}",
        f"#define FIR_FC_HZ  {int(FIR_FC)}",
        "",
    ]
    for fs, h in coefs.items():
        body = ", ".join(str(c) for c in h)
        lines.append(f"static const int16_t FIR_COEF_{fs}[FIR_N_TAPS] = {{ {body} }};")
    lines += ["", "#endif /* COEFS_FIR_H */", ""]
    path.write_text("\n".join(lines))

def write_filters_params_h(path: Path) -> None:
    lines = [
        "/* filters_params.h - GENERADO por tools/gen_coefs.py. NO editar a mano. */",
        "#ifndef FILTERS_PARAMS_H",
        "#define FILTERS_PARAMS_H",
        "",
        f"#define PB_STAGES   {PB_STAGES}",
        f"#define PB_FRAC     {PB_FRAC}",
        f"#define ECHO_SHIFT  {ECHO_SHIFT}",
        f"#define ECHO_MS     {ECHO_MS}",
        f"#define ECHO_D_MAX  {max(echo_delay(fs) for fs in FS_LIST)}",
        "",
    ]
    for fs in FS_LIST:
        k_hp, k_lp = PB_K[fs]
        lines += [f"#define PB_KHP_{fs}  {k_hp}",
                  f"#define PB_KLP_{fs}  {k_lp}",
                  f"#define ECHO_D_{fs}  {echo_delay(fs)}"]
    lines += ["", "#endif /* FILTERS_PARAMS_H */", ""]
    path.write_text("\n".join(lines))

VECTORS_README = """# sim/vectors - GENERADO por tools/gen_coefs.py (no editar a mano)

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
"""

# =======================================================================================
# ~~~ Graficas de los filtros ~~~
# =======================================================================================
def plot_responses(img_dir: Path, coefs: dict[int, list[int]]) -> None:
    # FIR: respuesta en frecuencia con los coeficientes CUANTIZADOS
    plt.figure(figsize=(8, 4.5))
    for fs, h in coefs.items():
        w, H = freqz(np.array(h) / (1 << Q_FRAC), worN=4096, fs=fs)
        plt.semilogx(w[1:], 20 * np.log10(np.abs(H[1:]) + 1e-12), label=f"fs = {fs} Hz")
    plt.axvline(FIR_FC, ls="--", c="gray", lw=0.8)
    plt.ylim(-90, 5); plt.grid(True, which="both", alpha=0.3)
    plt.title(f"Pasa-bajos FIR (HDL): N={N_TAPS}, fc={FIR_FC:.0f} Hz, Q1.15")
    plt.xlabel("Frecuencia [Hz]"); plt.ylabel("Magnitud [dB]"); plt.legend()
    plt.tight_layout(); plt.savefig(img_dir / "resp_fir.png", dpi=120); plt.close()
    # Pasa-banda: respuesta medida con el MODELO de punto fijo (FFT de ruido blanco)
    rng = np.random.default_rng(SEED)
    plt.figure(figsize=(8, 4.5))
    for fs in FS_LIST:
        x = rng.integers(-8000, 8000, 1 << 15).tolist()
        y = model_pb(x, *PB_K[fs])
        X, Y = np.fft.rfft(x), np.fft.rfft(y)
        f = np.fft.rfftfreq(len(x), 1 / fs)
        mag = np.abs(Y) / (np.abs(X) + 1e-9)
        mag = np.convolve(mag, np.ones(64) / 64, mode="same")  # suavizado
        plt.semilogx(f[1:], 20 * np.log10(mag[1:] + 1e-12),
                     label=f"fs = {fs} Hz (k_hp={PB_K[fs][0]}, k_lp={PB_K[fs][1]})")
    plt.ylim(-50, 5); plt.grid(True, which="both", alpha=0.3)
    plt.title(f"Pasa-banda (Nios, desplazamientos): {PB_STAGES}+{PB_STAGES} etapas")
    plt.xlabel("Frecuencia [Hz]"); plt.ylabel("Magnitud [dB]"); plt.legend()
    plt.tight_layout(); plt.savefig(img_dir / "resp_pb.png", dpi=120); plt.close()
    # Eco: respuesta al impulso en el tiempo (fs = 44100)
    fs = 44100
    d = echo_delay(fs)
    x = [0] * (6 * d)
    x[0] = 16000
    y = model_echo(x, d)
    t = np.arange(len(y)) / fs * 1000
    plt.figure(figsize=(8, 3.5))
    plt.plot(t, y, lw=0.8)
    plt.title(f"Eco (Nios): D={ECHO_MS} ms, realimentacion 2^-{ECHO_SHIFT}, respuesta al impulso")
    plt.xlabel("Tiempo [ms]"); plt.ylabel("Amplitud"); plt.grid(alpha=0.3)
    plt.tight_layout(); plt.savefig(img_dir / "resp_eco.png", dpi=120); plt.close()

def measured_response_pb(fs: int, rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    #Respuesta del pasa-banda medida con el MODELO de punto fijo (ruido blanco + FFT)
    x = rng.integers(-8000, 8000, 1 << 15).tolist()
    y = model_pb(x, *PB_K[fs])
    X, Y = np.fft.rfft(x), np.fft.rfft(y)
    f = np.fft.rfftfreq(len(x), 1 / fs)
    mag = np.convolve(np.abs(Y) / (np.abs(X) + 1e-9), np.ones(64) / 64, mode="same")
    return f[1:], 20 * np.log10(mag[1:] + 1e-12)

def plot_comparison(img_dir: Path, coefs: dict[int, list[int]]) -> None:
    #Comparacion de los 4 modos que se eligen con los switches (bypass + 3 filtros), una grafica por fs.
    rng = np.random.default_rng(SEED)
    fig, axes = plt.subplots(len(FS_LIST), 1, figsize=(9, 3.2 * len(FS_LIST)), sharey=True)
    for ax, fs in zip(axes, FS_LIST):
        f = np.geomspace(20, fs / 2, 6000)
        # Original (bypass): ganancia 1 en todas las frecuencias
        ax.semilogx(f, np.zeros_like(f), "k--", lw=1.2, label="Original (bypass)")
        # Eco: H(z) = 1 / (1 - 2^-s z^-D)  -> peine entre -3.5 dB y +6 dB
        d = echo_delay(fs)
        g = 2.0 ** -ECHO_SHIFT
        h_eco = 1 / np.abs(1 - g * np.exp(-2j * np.pi * f * d / fs))
        ax.semilogx(f, 20 * np.log10(h_eco), c="tab:green", lw=0.4, alpha=0.45,
                    label=f"Eco (SW, {ECHO_MS} ms): peine {20*np.log10(1/(1+g)):.1f} a "
                          f"+{20*np.log10(1/(1-g)):.1f} dB")
        # Pasa-bajos FIR con los coeficientes cuantizados (lo que usa el HW)
        _, h_fir = freqz(np.array(coefs[fs]) / (1 << Q_FRAC), worN=f, fs=fs)
        ax.semilogx(f, 20 * np.log10(np.abs(h_fir) + 1e-12), c="tab:blue", lw=1.8,
                    label=f"Pasa-bajos FIR (HW), fc={FIR_FC:.0f} Hz")
        # Pasa-banda (modelo de punto fijo)
        f_pb, h_pb = measured_response_pb(fs, rng)
        ax.semilogx(f_pb, h_pb, c="tab:orange", lw=1.8,
                    label=f"Pasa-banda (SW), k=({PB_K[fs][0]},{PB_K[fs][1]})")
        ax.set_xlim(20, fs / 2)
        ax.set_ylim(-60, 10)
        ax.grid(True, which="both", alpha=0.3)
        ax.set_title(f"fs = {fs} Hz")
        ax.set_ylabel("Magnitud [dB]")
        ax.legend(loc="lower left", fontsize=8)
    axes[-1].set_xlabel("Frecuencia [Hz]")
    fig.suptitle("Comparacion de los 4 modos seleccionables por switches", fontsize=12)
    fig.tight_layout()
    fig.savefig(img_dir / "resp_comparacion.png", dpi=120)
    plt.close(fig)

def plot_fir_quantization(img_dir: Path, coefs: dict[int, list[int]]) -> None:
    #FIR con coeficientes originales (punto flotante) vs cuantizados Q1.15
    fig, axes = plt.subplots(1, len(FS_LIST), figsize=(12, 3.8), sharey=True)
    for ax, fs in zip(axes, FS_LIST):
        h_float = firwin(N_TAPS, FIR_FC, fs=fs)
        h_q = np.array(coefs[fs]) / (1 << Q_FRAC)
        for h, lab, sty in ((h_float, "Original (float64)", "-"), (h_q, "Cuantizado Q1.15", "--")):
            w, H = freqz(h, worN=4096, fs=fs)
            ax.semilogx(w[1:], 20 * np.log10(np.abs(H[1:]) + 1e-12), sty, lw=1.4, label=lab)
        err = np.max(np.abs(h_float - h_q)) * (1 << Q_FRAC)
        ax.set_title(f"fs = {fs} Hz  (error max = {err:.2f} LSB)", fontsize=10)
        ax.set_ylim(-100, 5)
        ax.grid(True, which="both", alpha=0.3)
        ax.set_xlabel("Frecuencia [Hz]")
    axes[0].set_ylabel("Magnitud [dB]")
    axes[0].legend(fontsize=8, loc="lower left")
    fig.suptitle(f"Pasa-bajos FIR: coeficientes originales vs Q1.15 (N={N_TAPS})", fontsize=12)
    fig.tight_layout()
    fig.savefig(img_dir / "resp_fir_cuantizacion.png", dpi=120)
    plt.close(fig)

# ======================================================================================================================
# ~~~ main ~~~
# ======================================================================================================================
def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1],
                    help="raiz del repo (por defecto: carpeta padre de tools/)")
    args = ap.parse_args()
    vec_dir = args.root / "sim" / "vectors"
    src_dir = args.root / "sw" / "niosv" / "src"
    img_dir = args.root / "docs" / "img"
    for d in (vec_dir, src_dir, img_dir):
        d.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(SEED)
    coefs = {fs: fir_coefs(fs) for fs in FS_LIST}
    for fs, h in coefs.items():
        (vec_dir / f"coefs_{fs}.hex").write_text("".join(hex16(c) + "\n" for c in h))
        sigs = test_signals(fs, rng)
        sigs_fir = dict(sigs, saturacion=saturation_signal(h))
        # FIR (hardware): .hex empaquetado R|L
        for name, (xl, xr) in sigs_fir.items():
            write_hex_pairs(vec_dir / f"fir_{fs}_{name}_in.hex", xl, xr)
            write_hex_pairs(vec_dir / f"fir_{fs}_{name}_out.hex", model_fir(xl, h), model_fir(xr, h))
        # Filtros de software: .txt decimal 'L R'
        k_hp, k_lp = PB_K[fs]
        d = echo_delay(fs)
        for name, (xl, xr) in sigs.items():
            write_txt_pairs(vec_dir / f"pb_{fs}_{name}_in.txt", xl, xr)
            write_txt_pairs(vec_dir / f"pb_{fs}_{name}_out.txt", model_pb(xl, k_hp, k_lp), model_pb(xr, k_hp, k_lp))
        # eco: la entrada debe durar mas que D para que aparezcan los rebotes
        xl = rng.integers(-12000, 12000, 3 * d).tolist()
        xr = rng.integers(-12000, 12000, 3 * d).tolist()
        write_txt_pairs(vec_dir / f"eco_{fs}_ruido_in.txt", xl, xr)
        write_txt_pairs(vec_dir / f"eco_{fs}_ruido_out.txt", model_echo(xl, d), model_echo(xr, d))
        imp = [0] * (4 * d)
        imp[0] = 16000
        write_txt_pairs(vec_dir / f"eco_{fs}_impulso_in.txt", imp, [-v for v in imp])
        write_txt_pairs(vec_dir / f"eco_{fs}_impulso_out.txt", model_echo(imp, d), model_echo([-v for v in imp], d))
        sum_abs = sum(abs(c) for c in h) / (1 << Q_FRAC)
        print(f"fs={fs:5d}: suma(h)={sum(h)/(1 << Q_FRAC):.4f}  suma|h|={sum_abs:.4f}  "
              f"PB k=({k_hp},{k_lp})  eco D={d}")
    (vec_dir / "README.md").write_text(VECTORS_README)
    write_coefs_h(src_dir / "coefs_fir.h", coefs)
    write_filters_params_h(src_dir / "filters_params.h")
    plot_responses(img_dir, coefs)
    plot_comparison(img_dir, coefs)
    plot_fir_quantization(img_dir, coefs)
    n_files = len(list(vec_dir.iterdir()))
    print(f"\nListo: {n_files} archivos en {vec_dir.relative_to(args.root)}/, "
          f"coefs_fir.h y filters_params.h en {src_dir.relative_to(args.root)}/, "
          f"graficas en {img_dir.relative_to(args.root)}/")

if __name__ == "__main__":
    main()
